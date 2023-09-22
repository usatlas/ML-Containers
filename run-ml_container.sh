#!/bin/bash
# coding: utf-8
"true" '''\'
myScript="${BASH_SOURCE:-$0}"
ret=0

sourced=0
if [ -n "$ZSH_VERSION" ]; then 
   case $ZSH_EVAL_CONTEXT in *:file) sourced=1; esac
else
   case ${0##*/} in bash|-bash|zsh|-zsh) sourced=1; esac
fi

mySetup=runMe-here.sh

if [[ -e $mySetup && ( $# -eq 0 || "$@" =~ "--rerun" ) ]]; then
   source $mySetup
   ret=$?
else
   if [ "X" != "X$BASH_SOURCE" ]; then
      shopt -s expand_aliases
   fi
   alias py_readlink="python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))'"
   alias py_stat="python3 -c 'import os,sys; print(int(os.path.getmtime(sys.argv[1])))'"
   myDir=$(dirname $myScript)
   myDir=$(py_readlink $myDir)
   now=$(date +"%s")
   python3 -I "$myScript" --shellFilename $mySetup "$@"
   ret=$?
   if [ -e $mySetup ]; then
      # check if the setup script is newly created
      mtime_setup=$(py_stat $mySetup)
      if [ "$(( $mtime_setup - $now ))" -gt 0 ]; then
         echo -e "\nTo reuse the same container next time, just run"
         echo -e "\n\t source $mySetup \n or \n\t source $myScript"
         sleep 3
         source $mySetup
      fi
   fi
fi
[[ $sourced == 1 ]] && return $ret || exit $ret
'''

import os, sys
pythonMajor = sys.version_info[0]
import argparse
import re
import pprint
import json
import subprocess
import ast
from time import sleep
if pythonMajor < 3:
   from urllib import urlopen
   from distutils.spawn import find_executable as which
   from commands import getstatusoutput
else:
   from urllib.request import urlopen
   from shutil import which
   from subprocess import getstatusoutput


CONTAINER_CMDS = ['podman', 'docker', 'singularity']
DOCKERHUB_REPO = "https://hub.docker.com/v2/repositories/"
IMAGE_CONFIG = {
    "ml-base:centos7-python38":
        {"dockerPath": "docker.io/yesw2000/{FullName}",
              "listURL":"https://raw.githubusercontent.com/usatlas/ML-Containers/main/centos7/{Name}/list-of-pkgs-inside.txt",
              "cvmfsPath": ["/cvmfs/atlas.sdcc.bnl.gov/users/yesw/singularity/centos7-py38/{Name}",
                            "/cvmfs/unpacked.cern.ch/registry.hub.docker.com/yesw2000/{FullName}"]
        },
    "ml-pyroot:centos7-python38":
        {"dockerPath": "docker.io/yesw2000/{FullName}",
              "listURL":"https://raw.githubusercontent.com/usatlas/ML-Containers/main/centos7/{Name}/list-of-pkgs-inside.txt",
              "cvmfsPath": ["/cvmfs/atlas.sdcc.bnl.gov/users/yesw/singularity/centos7-py38/{Name}",
                            "/cvmfs/unpacked.cern.ch/registry.hub.docker.com/yesw2000/{FullName}"]
        },
    "ml-tensorflow-cpu:centos7-python38":
        {"dockerPath": "docker.io/yesw2000/{FullName}",
              "listURL":"https://raw.githubusercontent.com/usatlas/ML-Containers/main/centos7/{Name}/list-of-pkgs-inside.txt",
              "cvmfsPath": ["/cvmfs/atlas.sdcc.bnl.gov/users/yesw/singularity/centos7-py38/{Name}",
                            "/cvmfs/unpacked.cern.ch/registry.hub.docker.com/yesw2000/{FullName}"]
        },
    "ml-tensorflow-gpu:centos7-python38":
        {"dockerPath": "docker.io/yesw2000/{FullName}",
              "listURL":"https://raw.githubusercontent.com/usatlas/ML-Containers/main/centos7/{Name}/list-of-pkgs-inside.txt",
              "cvmfsPath": ["/cvmfs/atlas.sdcc.bnl.gov/users/yesw/singularity/centos7-py38/{Name}",
                            "/cvmfs/unpacked.cern.ch/registry.hub.docker.com/yesw2000/{FullName}"]
        }
}


def set_default_subparser(parser, default_subparser, index_action=1):
    """default subparser selection. Call after setup, just before parse_args()

    parser: the name of the parser you're making changes to
    default_subparser: the name of the subparser to call by default"""

    if len(sys.argv) <= index_action:
       parser.print_help()
       sys.exit(1)

    subparser_found = False
    for arg in sys.argv[1:]:
        if arg in ['-h', '--help']:  # global help if no subparser
            break
    else:
        for x in parser._subparsers._actions:
            if not isinstance(x, argparse._SubParsersAction):
                continue
            for sp_name in x._name_parser_map.keys():
                if sp_name in sys.argv[1:]:
                    subparser_found = True
        if not subparser_found:
            # insert default in first position before all other arguments
            sys.argv.insert(index_action, default_subparser) 


def run_shellCmd(shellCmd, exitOnFailure=True):
    retCode, out = getstatusoutput(shellCmd)
    if retCode != 0 and exitOnFailure:
       print("!!Error!! Failed in running the following command")
       print("\t", shellCmd)
       sys.exit(1)
    return out


def listImages(args=None):
    images = list(IMAGE_CONFIG.keys())
    pp = pprint.PrettyPrinter(indent=4)
    print("Available images=")
    pp.pprint(images)


def list_FoundImages(name):
    images = list(IMAGE_CONFIG.keys())
    images_found = []
    for imageFullName in images:
        imageBaseName = imageFullName.split(':')[0]
        if imageFullName == name or imageBaseName == name:
           images_found += [imageFullName]
    return images_found


def getImageInfo(args, imageFullName=None, printOut=True):
    if imageFullName == None:
       images_found = list_FoundImages(args.name)
       if len(images_found) == 0:
          print("\n!!Warning!! imageName=%s is NOT found.\n" % args.name) 
          listImages()
          sys.exit(1)
       elif len(images_found) > 1:
          print("\nMultiple images matching %s are found:" % args.name)
          print("\t",images_found)
       imageFullName = images_found[0]
    imageName, tagName = imageFullName.split(':')
    dockerPath = IMAGE_CONFIG[imageFullName]["dockerPath"].replace("{FullName}",imageName)
    url_tags = DOCKERHUB_REPO + dockerPath.replace("docker.io/","") +"/tags"
    # print("tags_url=", url_tags)
    response = urlopen(url_tags)
    json_obj = json.loads(response.read().decode('utf-8'))
    json_tags = json_obj['results']
    json_tag = None
    for dict_tag in json_tags:
        if dict_tag['name'] == tagName:
           json_tag = dict_tag
           break
    if json_tag:
       # pp = pprint.PrettyPrinter(indent=4)
       # pp.pprint(json_tag)
       imageSize  = json_tag['full_size']
       lastUpdate = json_tag['last_updated']
       imageDigest = json_tag['digest']
       if printOut:
          print("Found image name= %s\n" % imageFullName)
          print(" Image compressed size=", imageSize)
          print(" Last  update UTC time=", lastUpdate)
          print("     Image SHA256 hash=", imageDigest)
       else:
          return {"imageSize":imageSize, "lastUpdate":lastUpdate, "imageDigest":imageDigest}
    else:
       print("!!Warning!! No tag name=%s is found for the image name=%s" % (tagName, imageName) )
       sys,exit(1)
    

def listPackages(args):
    images_found = list_FoundImages(args.name)
    if len(images_found) == 0:
       print("\n!!Warning!! imageName=%s is NOT found.\n" % args.name) 
       listImages()
       sys.exit(1)

    for imageName in images_found:
       baseName = imageName.split(':')[0]
       print("\nFound imageName=",imageName, " with the following installed pkgs:")
       url = IMAGE_CONFIG[imageName]["listURL"].replace("{Name}",baseName)
       resource = urlopen(url)
       content = resource.read().decode('utf-8')
       print(content)


def listNewPkgs(contCmd, contNamePath, lastLineN):
    history = "/opt/conda/conda-meta/history"
    if contCmd == 'singularity':
       grepCmd = 'egrep -n "specs:|cmd:" %s/%s' % (contNamePath, history)
    else:
       startCmd = '%s start %s' % (contCmd, contNamePath)
       output = run_shellCmd(startCmd)
       grepCmd = '%s exec %s egrep -n "specs:|cmd:" %s' % (contCmd, contNamePath, history)

    output = run_shellCmd(grepCmd)
    pkgs = {}
    channels = []
    for line in output.split('\n'):
        lineN, lineH, lineObj = line.split(':', 2)
        if int(lineN) <= int(lastLineN):
           continue
        if lineH.find("specs") > 0:
           if lineH.find("remove") > 0:
              removeIt = True
           else:
              removeIt = False
           items = ast.literal_eval(lineObj.strip())
           for item in items:
               key, delim, value = (re.split('(<|=|>)', item, 1) + [None]*2)[:3]
               if value is None:
                  value = ''
               else:
                  value = delim + value
               if key not in pkgs:
                  if not removeIt:
                     pkgs[key] = value
                  else:
                     print("!!Warning!! Removing non new primary pkg=%s is NOT supported" % key)
               elif key in pkgs:
                  if removeIt:
                     del pkgs[key]
                  elif value != '':
                     pkgs[key] = value
        elif lineObj.find(" -c ") > 0 or lineObj.find(" --channel") > 0:
           items = lineObj.split()
           channelNext = False
           for item in items:
               if channelNext:
                  if item not in channels and item != 'conda-forge':
                     channels += [item]
                  channelNext = False
                  continue
               if item == '-c' or item == "--channel":
                  channelNext = True
               elif item.startswith("--channel="):
                  value = item.split('=')[1]
                  if value not in channels and value != 'conda-forge':
                     channels += [ value ]

    pkgs_list = []
    for k, v in pkgs.items():
        pkgs_list += [ k + v ]
    return pkgs_list, channels


# install users new pkgs
def install_newPkgs(contCmd, contNamePath, pkgs, channels):
    channels_pkgs = ''
    for channel in channels:
        channels_pkgs += ' -c ' + channel
    for pkg in pkgs:
        channels_pkgs += ' ' + pkg
    bash_cmd = "/bin/bash -c 'micromamba install -y %s'" % channels_pkgs
    if contCmd == 'singularity':
       installCmd = "singularity exec -w -H %s %s %s" \
                    % (os.getcwd(), contNamePath, bash_cmd)
    else:
       installCmd = "%s exec %s %s" % (contCmd, contNamePath, bash_cmd)
    print("\nGoing to install new pkg(s) with the following command\n")
    print("\t", installCmd)
    run_shellCmd(installCmd)


# build Singularity sandbox
def build_sandbox(sandboxPath, dockerPath, force=False):
    if os.path.exists(sandboxPath):
       if not force and os.path.exists(sandboxPath + "/entrypoint.sh"):
          print("%s already, and would not override it." % sandboxPath)
          print("\nTo override the existing sandbox, please add the option '-f'")
          print("Quit now")
          sys.exit(1)
       os.system("chmod -R +w %s; rm -rf %s" % (sandboxPath, sandboxPath) )
    buildCmd = "singularity build --sandbox --fix-perms -F %s docker://%s" % (sandboxPath, dockerPath)
    print("\nBuilding Singularity sandbox\n")
    retCode = subprocess.call(buildCmd.split())
    if retCode != 0:
       print("!!Warning!! Building the Singularity sandbox failed. Exit now")
       sys.exit(1)


# write setup for Singularity sandbox
def write_sandboxSetup(filename, imageName, dockerPath, sandboxPath, runOpt):
    imageInfo = getImageInfo(None, imageName, printOut=False)
    imageSize = imageInfo["imageSize"]
    lastUpdate = imageInfo["lastUpdate"]
    imageDigest = imageInfo["imageDigest"]
    output = run_shellCmd("wc -l %s/opt/conda/conda-meta/history" % sandboxPath)
    linesCondaHistory = output.split()[0]
    myScript =  os.path.abspath(sys.argv[0])
    shellFile = open(filename, 'w')
    shellFile.write("""
contCmd=singularity
imageName=%s
imageCompressedSize=%s
imageLastUpdate=%s
imageDigest=%s
linesCondaHistory=%s
dockerPath=%s
sandboxPath=%s
runOpt="%s"
if [ -e $sandboxPath/entrypoint.sh ]; then
   runCmd="singularity run $runOpt $sandboxPath"
   echo -e "\\n$runCmd\\n"
   eval $runCmd
else
   echo "The Singularity sandbox=$sandboxPath does not exist or is invalid"
   echo "Please rebuild the Singularity sandbox by running the following"
   echo -e "\n\t source %s $imageName"
fi
""" % (imageName, imageSize, lastUpdate, imageDigest, linesCondaHistory, 
       dockerPath, sandboxPath, runOpt, myScript) )
    shellFile.close()


# create docker/podman container
def create_container(contCmd, contName, dockerPath, force=False):
    pullCmd = "%s pull %s" % (contCmd, dockerPath)
    retCode = subprocess.call(pullCmd.split())
    if retCode != 0:
       print("!!Warning!! Pulling the image %s failed, exit now" % dockerPath)
       sys.exit(1)

    out = run_shellCmd("%s ps -a -f name='^%s$' " % (contCmd, contName) )
    if out.find(contName) > 0:
       if force:
          print("\nThe container=%s already exists, removing it now" % contName)
          out = run_shellCmd("%s rm -f %s" % (contCmd, contName) )
       else:
          print("\nThe container=%s already exists, \n\tplease rerun the command with the option '-f' to remove it" % contName)
          print("\nQuit now")
          sys.exit(1)

    pwd = os.getcwd()
    createCmd = "%s create -it -v %s:%s -w %s --name %s %s" % \
                (contCmd, pwd, pwd, pwd, contName, dockerPath)
    out = run_shellCmd(createCmd)

    startCmd = "%s start %s" % (contCmd, contName)
    out = run_shellCmd(startCmd)


# write setup for Docker/Podman container
def write_dockerSetup(filename, imageName, dockerPath, contCmd, contName, override=False):
    imageInfo = getImageInfo(None, imageName, printOut=False)
    imageSize = imageInfo["imageSize"]
    lastUpdate = imageInfo["lastUpdate"]
    imageDigest = imageInfo["imageDigest"]

    output = run_shellCmd("%s run --rm %s wc -l /opt/conda/conda-meta/history" % (contCmd, dockerPath) )
    linesCondaHistory = output.split()[0]
      

    shellFile = open(filename, 'w')
    shellFile.write("""
contCmd=%s
imageName=%s
imageCompressedSize=%s
imageLastUpdate=%s
imageDigest=%s
dockerPath=%s
linesCondaHistory=%s
contName=%s
re_exited="ago[\ ]+Exited"
re_up="ago[\ ]+Up"

listOut=$($contCmd ps -a -f name='^'$contName'$' 2>/dev/null | tail -1)

if [[ "$listOut" =~ $re_exited ]]; then
   startCmd="$contCmd start $contName"
   echo -e "\\n$startCmd"
   eval $startCmd >/dev/null
elif [[ "$listOut" =~ $re_up ]]; then
   if [[ "$listOut" =~ "(Paused)" ]]; then
      unpauseCmd="$contCmd unpause $contName"
      echo -e "\\n$unpauseCmd"
      eval $unpauseCmd >/dev/null
   fi
else
   createCmd="$contCmd create -it -v $PWD:$PWD -w $PWD --name $contName $dockerPath"
   echo -e "\\n$createCmd"
   eval $createCmd >/dev/null
   startCmd="$contCmd start $contName"
   echo -e "\\n$startCmd"
   eval $startCmd >/dev/null
fi
runCmd="$contCmd exec -it $contName /bin/bash"
echo -e "\\n$runCmd\\n"
eval $runCmd
""" % (contCmd, imageName, imageSize, lastUpdate, imageDigest, 
       dockerPath, linesCondaHistory, contName) )
    shellFile.close()


def setup(args):
    images = list_FoundImages(args.name)
    if len(images) == 0:
       print("No found image matching the name=", args.name)
       listImages()
       sys.exit(1)
    elif len(images) > 1:
       print("Multiple images matching the name=", args.name)
       print("Please specify the full name of the following images:")
       pp = pprint.PrettyPrinter(indent=4)
       pp.pprint(images)
    imageFullName = images[0]

    (imageName, tagName) = imageFullName.split(':')
    dockerPath = IMAGE_CONFIG[imageFullName]["dockerPath"].replace("{FullName}",imageFullName)
    print("Found the image name=",imageFullName," with the dockerPath=",dockerPath)

    contCmds = []
    for cmd in CONTAINER_CMDS:
        cmdFound = which(cmd)
        if cmdFound != None:
           contCmds += [cmd]

    if len(contCmds) == 0:
       print("None of container running commands: docker, podman, singularity; exit now")
       print("Please install one of the above tool first")
       sys.exit(1)

    contCmd = contCmds[0]
    if args.contCmd != None:
       if args.contCmd in contCmds:
          contCmd = args.contCmd
       else:
          print("The specified command=%s to run containers is NOT found" % args.contCmd)
          print("Please choose the available command(s) on the machine to run containers")
          print("\t",contCmds)
          sys,exit(1)

    if contCmd == "singularity":
       if not os.path.exists("singularity"):
          os.mkdir("singularity")
       sandboxPath = "singularity/%s" % imageFullName
       build_sandbox(sandboxPath, dockerPath, args.force)

       imageFullPath = os.path.join(os.getcwd(), sandboxPath)
       runCmd = "singularity run -w %s" % imageFullPath
       runOpt = '-w'

       # Check if Home bind-mount works with --writable mode
       # if not, add the option --no-home
       testCmd = runCmd + " ls /dev/null >/dev/null 2>&1"
       retCode, out = getstatusoutput(testCmd)
       if retCode != 0:
          runOpt = '-w -H $PWD'
       write_sandboxSetup(args.shellFilename, imageFullName, dockerPath, sandboxPath, runOpt)

    elif contCmd == "podman" or contCmd == "docker":
       testCmd = "%s info" % contCmd
       out = run_shellCmd(testCmd)
       contName = '_'.join([os.getlogin(), imageName, tagName])

       create_container(contCmd, contName, dockerPath, args.force)
       write_dockerSetup(args.shellFilename, imageFullName, dockerPath, 
                         contCmd, contName, args.force)

    sleep(1)


def getMyImageInfo(filename):
    shellFile = open(filename, 'r')
    myImageInfo = {}
    contCmd = None
    for line in shellFile:
       if re.search(r'^(cont|image|docker|sand|runOpt|lines).*=', line):
          key, value = line.strip().split('=')
          myImageInfo[key] = value
    return myImageInfo


def printMe(args):
    if not os.path.exists(args.shellFilename):
       print("No previous container/sandbox setup is found")
       return None
    myImageInfo = getMyImageInfo(args.shellFilename)
    contCmd = myImageInfo["contCmd"]
    linesCondaHistory = myImageInfo.pop("linesCondaHistory")
    if "runOpt" in myImageInfo:
       myImageInfo.pop("runOpt")
    pp = pprint.PrettyPrinter(indent=4)
    print("The image/container used in the current work directory:")
    pp.pprint(myImageInfo)
    if contCmd == 'singularity':
       contNamePath = myImageInfo["sandboxPath"]
    else:
       contNamePath = myImageInfo["contName"]
    pkgs, channels = listNewPkgs(contCmd, contNamePath, linesCondaHistory)
    if len(pkgs) > 0:
       print("\nThe following additional pkgs and their dependencies are installed")
       pp.pprint(pkgs)
    if len(channels) > 0:
       print("\nThe following channels besides the default channel 'conda-forge' are needed")
       pp.pprint(channels)


def update(args):
    if not os.path.exists(args.shellFilename):
       print("No previous container/sandbox setup is found")
       return None

    myImageInfo = getMyImageInfo(args.shellFilename)
    myImageName = myImageInfo["imageName"]
    myImageUpdate = myImageInfo["imageLastUpdate"]
    myImageDigest = myImageInfo["imageDigest"]
    latestImageInfo = getImageInfo(None, myImageName, printOut=False)
    latestUpdate = latestImageInfo["lastUpdate"]
    latestDigest = latestImageInfo["imageDigest"]
    if latestUpdate > myImageUpdate and myImageDigest != latestDigest:
       print("Update is available with the last update date=%s" % latestUpdate)
       print("\twith the corresponding image digest =", latestDigest)
    else:
       print("The current container/sandbox is already up-to-date")
       sys.exit(0)

    contCmd = myImageInfo["contCmd"]
    linesCondaHistory = myImageInfo.pop("linesCondaHistory")
    dockerPath = myImageInfo['dockerPath']

    if contCmd == 'singularity':
       contNamePath = myImageInfo["sandboxPath"]
    else:
       contNamePath = myImageInfo["contName"]
    pkgs, channels = listNewPkgs(contCmd, contNamePath, linesCondaHistory)

    if contCmd == 'singularity':
       build_sandbox(contNamePath, dockerPath, force=True)
       write_sandboxSetup(args.shellFilename, myImageName, dockerPath, \
                                 contNamePath, myImageInfo["runOpt"].strip('"'))
    else:
       create_container(contCmd, contNamePath, dockerPath, force=True)
       write_dockerSetup(args.shellFilename, myImageName, dockerPath, \
                                contCmd, contNamePath, override=True)
    if len(pkgs) > 0:
       install_newPkgs(contCmd, contNamePath, pkgs, channels)


def main():

    myScript =  os.path.basename( os.path.abspath(sys.argv[0]) )

    example_global = """Examples:

  source %s listImages
  source %s ml-base
  source %s            # Empty arg to rerun the already setup container
  source %s setup ml-base""" % (myScript, myScript, myScript, myScript)

    example_setup = """Examples:

  source %s ml-base
  source %s --sing ml-base""" % (myScript, myScript)

    parser = argparse.ArgumentParser(epilog=example_global, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--shellFilename', action='store', help=argparse.SUPPRESS)
    parser.add_argument('--rerun', action='store_true', help="rerun the already setup container")
    sp = parser.add_subparsers(dest='command', help='Default=setup')

    sp_listImages = sp.add_parser('listImages', help='list all available ML images')
    sp_listImages.set_defaults(func=listImages)

    sp_listPackages = sp.add_parser('listPackages', help='list packages in the given image')
    sp_listPackages.add_argument('name', metavar='<ImageName>', help='Image name to list packages')
    sp_listPackages.set_defaults(func=listPackages)

    sp_getImageInfo = sp.add_parser('getImageInfo', help='get image size. last update date and SHA256 hash of the given image')
    sp_getImageInfo.add_argument('name', metavar='<ImageName>')
    sp_getImageInfo.set_defaults(func=getImageInfo)

    sp_printMe = sp.add_parser('printMe', help='print the container/image set up for the work directory')
    sp_printMe.set_defaults(func=printMe)

    sp_update = sp.add_parser('update', help='(not ready yet) check if the container/image here is up-to-date and update it needed')
    sp_update.set_defaults(func=update)

    sp_setup = sp.add_parser('setup', help='create a container/sandbox for the given image', 
                    epilog=example_setup, formatter_class=argparse.RawDescriptionHelpFormatter)
    group_cmd = sp_setup.add_mutually_exclusive_group()
    for cmd in CONTAINER_CMDS:
        group_cmd.add_argument("--%s" % cmd, dest="contCmd", 
                               action="store_const", const="%s" % cmd, 
                               help="Use %s to the container" % cmd)
    sp_setup.add_argument('-f', '--force', action='store_true', default=False, help="Force to override the existing container/sandbox")
    sp_setup.add_argument('name', metavar='<ImageName>', help='image name to run')
    sp_setup.set_defaults(func=setup)
    set_default_subparser(parser, 'setup', 3)

    args, extra = parser.parse_known_args()

    args.func(args)


if __name__ == "__main__":
    main()
