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
   myDir=$(dirname $myScript)
   myDir=$(readlink -f $myDir)
   now=$(date +"%s")
   python3 -I "$myScript" --shellFilename $mySetup "$@"
   ret=$?
   if [ -e $mySetup ]; then
      # check if the setup script is newly created
      if [ "$(( $(stat -c "%Y" "$mySetup") - $now ))" -gt 0 ]; then
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


def list_images(args=None):
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


def get_imageInfo(args, imageFullName=None, printMe=True):
    if imageFullName == None:
       images_found = list_FoundImages(args.name)
       if len(images_found) == 0:
          print("\n!!Warning!! imageName=%s is NOT found.\n" % args.name) 
          list_images()
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
       if printMe:
          print("Found image name= %s\n" % imageFullName)
          print(" Image compressed size=", imageSize)
          print(" Last  update UTC time=", lastUpdate)
          print("     Image SHA256 hash=", imageDigest)
       else:
          return (imageSize, lastUpdate, imageDigest)
    else:
       print("!!Warning!! No tag name=%s is found for the image name=%s" % (tagName, imageName) )
       sys,exit(1)
    

def list_packages(args):
    images_found = list_FoundImages(args.name)
    if len(images_found) == 0:
       print("\n!!Warning!! imageName=%s is NOT found.\n" % args.name) 
       list_images()
       sys.exit(1)

    for imageName in images_found:
       baseName = imageName.split(':')[0]
       print("\nFound imageName=",imageName, " with the following installed pkgs:")
       url = IMAGE_CONFIG[imageName]["listURL"].replace("{Name}",baseName)
       resource = urlopen(url)
       content = resource.read().decode('utf-8')
       print(content)


# write setup for Singularity sandbox
def write_sandboxSetup(filename, imageName, dockerPath, sandboxPath, runOpt):
    imageSize, lastUpdate, imageDigest = get_imageInfo(None, imageName, False)
    myScript =  os.path.abspath(sys.argv[0])
    shellFile = open(filename, 'w')
    shellFile.write("""
imageName=%s
imageCompressedSize=%s
lastUpdate=%s
imageDigest=%s
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
""" % (imageName, imageSize, lastUpdate, imageDigest, dockerPath, sandboxPath, runOpt, myScript) )
    shellFile.close()


# write setup for Docker/Podman container
def write_dockerSetup(filename, imageName, dockerPath, contCmd, contName, override=False):
    imageSize, lastUpdate, imageDigest = get_imageInfo(None, imageName, False)
    if override:
       status, out = getstatusoutput("%s ps -a -f name='^%s$' | tail -1" % (contCmd, contName) )
       if out.find(contName) > 0:
          if re.search("ago\s+(Up|Exited)", out):
             print("\nThe container=%s already exists, removing it first" % contName)
             if re.search("ago\s+Up", out):
                status, out = getstatusoutput("%s stop %s" % (contCmd, contName) )
                if status != 0:
                   print("!!Error!! Failed in stopping the container=%s" % contName)
                   sys.exit(1)
             status, out = getstatusoutput("%s rm %s" % (contCmd, contName) )
             if status != 0:
                print("!!Error!! Failed in removing the container=%s" % contName)
                sys.exit(1)

    shellFile = open(filename, 'w')
    shellFile.write("""
imageName=%s
imageCompressedSize=%s
lastUpdate=%s
imageDigest=%s
imagePath=%s
contCmd=%s
contName=%s
re_exited="ago[\ ]+Exited"
re_up="ago[\ ]+Up"

listOut=$($contCmd ps -a -f name='^'$contName'$' 2>/dev/null | tail -1)

if [[ "$listOut" =~ $re_exited ]]; then
   startCmd="$contCmd start $contName"
   echo -e "\n$startCmd\n"
   eval $startCmd >/dev/null
elif [[ "$listOut" =~ $re_up ]]; then
   if [[ "$listOut" =~ "(Paused)" ]]; then
      unpauseCmd="$contCmd unpause $contName"
      echo -e "\n$unpauseCmd\n"
      eval $unpauseCmd >/dev/null
   fi
else
   createCmd="$contCmd create -it -v $PWD:$PWD -w $PWD --name $contName $imagePath"
   echo -e "\\n$createCmd\\n"
   eval $createCmd >/dev/null
   startCmd="$contCmd start $contName"
   echo -e "\n$startCmd\n"
   eval $startCmd >/dev/null
fi
runCmd="$contCmd exec -it $contName /bin/bash"
echo -e "\\n$runCmd\\n"
eval $runCmd
""" % (imageName, imageSize, lastUpdate, imageDigest, dockerPath, contCmd, contName) )
    shellFile.close()


def setup_image(args):
    images = list_FoundImages(args.name)
    if len(images) == 0:
       print("No found image matching the name=", args.name)
       list_images()
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
       if os.path.exists(sandboxPath):
          if not args.force and os.path.exists(sandboxPath + "/entrypoint.sh"):
             print("%s already, and would not override it." % sandboxPath)
             print("\nTo override the existing sandbox, please add the option '-f'")
             print("Quit now")
             sys.exit(1)
          os.system("chmod -R +w %s; rm -rf %s" % (sandboxPath, sandboxPath) )
       buildCmd = "singularity build --sandbox -F %s docker://%s" % (sandboxPath, dockerPath)
       print("\nBuilding Singularity sandbox\n")
       sleep(1)
       retCode = subprocess.call(buildCmd.split())
       if retCode != 0:
          print("!!Warning!! Building the Singularity sandbox failed. Exit now")
          sys.exit(1)

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
       retCode, out = getstatusoutput(testCmd)
       if retCode != 0:
          print("!!Warning!! %s is NOT setup properly, exit now" % contCmd)
          sys,exit(1)

       pullCmd = "%s pull %s" % (contCmd, dockerPath)
       retCode = subprocess.call(pullCmd.split())
       if retCode != 0:
          print("!!Warning!! Pulling the image %s failed, exit now" % dockerPath)
          sys.exit(1)

       runningContName = '_'.join([os.getlogin(), imageName, tagName])
       write_dockerSetup(args.shellFilename, imageFullName, dockerPath, contCmd, runningContName, args.force)

    sleep(1)


def main():

    myScript =  os.path.basename( os.path.abspath(sys.argv[0]) )

    example_global = """Examples:

  source %s listImages
  source %s ml-base
  source %s            # Empty arg to rerun the already setup container
  source %s setupImage ml-base""" % (myScript, myScript, myScript, myScript)

    example_setup = """Examples:

  source %s ml-base
  source %s --sing ml-base""" % (myScript, myScript)

    parser = argparse.ArgumentParser(epilog=example_global, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--shellFilename', action='store', help=argparse.SUPPRESS)
    parser.add_argument('--rerun', action='store_true', help="rerun the already setup container")
    sp = parser.add_subparsers(dest='command', help='Default=setupImage')

    sp_listImages = sp.add_parser('listImages', help='list all available ML images')
    sp_listImages.set_defaults(func=list_images)

    sp_listPackages = sp.add_parser('listPackages', help='list packages in the given image')
    sp_listPackages.add_argument('name', metavar='<ImageName>', help='Image name to list packages')
    sp_listPackages.set_defaults(func=list_packages)

    sp_getImageInfo = sp.add_parser('getImageInfo', help='get image size. last update date and SHA256 hash of the given image')
    sp_getImageInfo.add_argument('name', metavar='<ImageName>')
    sp_getImageInfo.set_defaults(func=get_imageInfo)

    sp_setupImage = sp.add_parser('setupImage', help='setup a ML image', 
                    epilog=example_setup, formatter_class=argparse.RawDescriptionHelpFormatter)
    group_cmd = sp_setupImage.add_mutually_exclusive_group()
    for cmd in CONTAINER_CMDS:
        group_cmd.add_argument("--%s" % cmd, dest="contCmd", 
                               action="store_const", const="%s" % cmd, 
                               help="Use %s to the container" % cmd)
    # sp_setupImage.add_argument('--contCmd', action='store',
    #               choices=CONTAINER_CMDS, help='command to run containers')
    sp_setupImage.add_argument('-f', '--force', action='store_true', default=False, help="Force to override the existing container/sandbox")
    sp_setupImage.add_argument('name', metavar='<ImageName>', help='image name to run')
    sp_setupImage.set_defaults(func=setup_image)
    set_default_subparser(parser, 'setupImage', 3)

    args, extra = parser.parse_known_args()

    args.func(args)


if __name__ == "__main__":
    main()
