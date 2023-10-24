#!/bin/bash
# coding: utf-8
# version=2023-10-24-alpha03
# author: Shuwei Ye <yesw@bnl.gov>
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
elif [[ $# -eq 1 && "$1" =~ ^[Jj]upyter$ ]]; then
   source $mySetup jupyter
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

import getpass
import os
import sys

pythonMajor = sys.version_info[0]
import argparse
import ast
import json
import pprint
import re
import subprocess
from time import sleep
import fnmatch

from shutil import which
from subprocess import getstatusoutput
from urllib.request import urlopen, Request


URL_MYSELF = "https://raw.githubusercontent.com/usatlas/ML-Containers/main/run-atlas_container.sh"
CONTAINER_CMDS = ['podman', 'docker', 'singularity']
ATLAS_PROJECTS = ['athena', 'analysisbase', 'athanalysis', 'analysistop', 'athanalysis']
DOCKERHUB_REPO = "https://hub.docker.com/v2/repositories/atlas"


def set_default_subparser(parser, default_subparser, index_action=1):
    """default subparser selection. Call after setup, just before parse_args()

    parser: the name of the parser you're making changes to
    default_subparser: the name of the subparser to call by default"""

    if len(sys.argv) <= index_action:
       parser.print_help()
       sys.exit(1)

    subparser_found = False
    for arg in sys.argv[1:]:
        if arg in ['-h', '--help', '--version']:  # global help or version, no default subparser
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


def getVersion(myFile=None):
    isFileOpen = False
    if myFile is None:
       myScript =  os.path.abspath(sys.argv[0])
       myFile = open(myScript, 'r')
       isFileOpen = True
    no = 0
    version = None
    for line in myFile:
        no += 1
        if no > 10:
           break
        if re.search('^#.* version', line):
           version = line.split('=')[1]
           break

    if isFileOpen:
       myFile.close()

    return version


def parseArgTags(inputArgs, requireRelease=False):
    argTags = []
    releaseTags = {}
    for arg in inputArgs:
        argTags += re.split(',|:', arg)
    for tag in argTags:
       if tag in ATLAS_PROJECTS:
          releaseTags['project'] = tag
       # elif tag == 'latest' or tag[0].isdigit():
       else:
          releaseTags['release'] = tag
          # print("!!Warning!! Unrecognized input arg=", tag)

    if 'project' not in releaseTags:
       print("!!Warning!! No project is provided from the choice of ", ATLAS_PROJECTS)
       sys.exit(1)
    if requireRelease and 'release' not in releaseTags:
       print("!!Warning!! No release is given")
       sys.exit(1)

    return releaseTags

    
def selfUpdate(args):
    currentVersion = getVersion()

    resource = urlopen(URL_MYSELF)
    content = resource.read().decode('utf-8')
    latestVersion = getVersion(content.split('\n'))
    if latestVersion is not None:
       if currentVersion is None or latestVersion > currentVersion:
          print("Update available, updating the script itself")
          myScript =  os.path.abspath(sys.argv[0])
          os.rename(myScript, myScript + '.old')
          try:
             myfile = open(myScript, 'w')
             myfile.write(content)
             myfile.close()
             print("Update finished")
          except Exception:
             err = sys.exc_info()[1]
             print("Failed to write out the latest version of this script\n", err)
             print("Keep the current version")
             os.rename(myScript + '.old', myScript) 
    else:
       print("Already up-to-date, no update needed")


def run_shellCmd(shellCmd, exitOnFailure=True):
    retCode, out = getstatusoutput(shellCmd)
    if retCode != 0 and exitOnFailure:
       print("!!Error!! Failed in running the following command")
       print("\t", shellCmd)
       sys.exit(1)
    return out


def listImageTags(project):
    url_tags = DOCKERHUB_REPO + '/' + project + '/tags?page_size=5000'
    response = urlopen(url_tags)
    json_obj = json.loads(response.read().decode('utf-8'))
    json_tags = json_obj['results']
    imageTags = {}
    latest_digest = ''
    latest_name = ''
    latest_index = None
    for tagObj in json_tags:
        name = tagObj['name']
        digest = tagObj['images'][0]['digest']
        imageSize = tagObj['full_size']
        lastUpdate = tagObj['tag_last_pushed']
        imageTags[name] = {'imageCompressedSize':imageSize, 'lastUpdate':lastUpdate, 'releaseName':name}
        if name == 'latest':
           latest_digest = digest
        elif latest_digest != '':
           if digest == latest_digest:
              latest_name = name

    if latest_name != '':
       imageTags['latest']['releaseName'] = latest_name

    return imageTags
           

def listReleases(args):
    releaseTags = parseArgTags(args.tags, requireRelease=False)
    project = releaseTags['project']
    if 'release' in releaseTags:
       release = releaseTags['release']
    else:
       release = None
    imageTags = listImageTags(project)
    releasePrint = ""
    if release is None:
       tags = list(imageTags.keys())
    else:
       tags = []
       releasePrint = " matching release=%s" % release
       for tagKey in imageTags.keys():
           if fnmatch.fnmatch(tagKey, release):
              tags += [ tagKey ]
    if len(tags) > 0:
       pp = pprint.PrettyPrinter(indent=4, compact=True)
       print("Found the following release container list for the project=", project, releasePrint)
       pp.pprint(tags)
    else:
       print("No release container found for the project=", project, releasePrint)


def getImageInfo(project, release, printOut=True):
    imageInfo = {}
    imageTags = listImageTags(project)
    if release in imageTags:
       imageInfo = imageTags[release].copy()
       releaseName = imageInfo.pop('releaseName')
       imageInfo['dockerPath'] = "atlas/%s:%s" % (project, releaseName)
    else:
       print("!!Warning!! release%s is NOT available")
       sys.exit(1)

    if len(imageInfo) > 0 and printOut:
       print("Found an image")
       print("\tdockerPath=", imageInfo['dockerPath'], 
             "; image compressed size=", imageInfo['imageCompressedSize'],
             "\n\tlast update time=", imageInfo['lastUpdate'])
    return imageInfo
    

def printImageInfo(args):
    releaseTags = parseArgTags(args.tags, requireRelease=True)
    project = releaseTags['project']
    release = releaseTags['release']
    getImageInfo(project, release)


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
def write_sandboxSetup(filename, imageInfo, sandboxPath, runOpt):
    imageSize = imageInfo["imageCompressedSize"]
    dockerPath = imageInfo["dockerPath"]
    lastUpdate = imageInfo["lastUpdate"]
    myScript =  os.path.abspath(sys.argv[0])
    shellFile = open(filename, 'w')
    shellFile.write("""
contCmd=singularity
dockerPath=%s
imageCompressedSize=%s
imageLastUpdate=%s
sandboxPath=%s
runOpt="%s"
releaseSetup1="/release_setup.sh"
releaseSetup2="/home/atlas/release_setup.sh"
if [ -e $sandboxPath$releaseSetup1 -o $sandboxPath$releaseSetup2 ]; then
   if [[ $# -eq 1 && "$1" =~ ^[Jj]upyter$ ]]; then
      runCmd="echo Jupyter is not ready yet"
      # runCmd="singularity exec $runOpt $sandboxPath /bin/bash -c "'"source $releaseSetup; jupyter lab"'
   else
      if [ -e $releaseSetup1 ]; then
         releaseSetup=$releaseSetup1
      else
         releaseSetup=$releaseSetup2
      fi
      runCmd="singularity run $runOpt $sandboxPath /bin/bash --init-file $releaseSetup"
   fi
   echo -e "\\n$runCmd\\n"
   eval $runCmd
else
   echo "The Singularity sandbox=$sandboxPath does not exist or is invalid"
   echo "Please rebuild the Singularity sandbox by running the following"
   echo -e "\n\t source %s $imageName"
fi
""" % (dockerPath, imageSize, lastUpdate, sandboxPath, runOpt, myScript) )
    shellFile.close()


# create docker/podman container
def create_container(contCmd, contName, imageInfo, force=False):
    dockerPath = imageInfo['dockerPath']
    pullCmd = "%s pull %s" % (contCmd, dockerPath)
    retCode = subprocess.call(pullCmd.split())
    username = getpass.getuser()
    home = os.path.expanduser("~")
    jupyterOpt = "-p 8888:8888 -e NB_USER=%s -e HOME=%s -v %s:%s" % (username, home, home, home)
    jupyterOpt += " -v /etc/passwd:/etc/passwd:ro -v /etc/group:/etc/group:ro"
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
    createOpt = "-it -v %s:%s -w %s %s" % (pwd, pwd, pwd, jupyterOpt)
    createCmd = "%s create %s --name %s %s" % \
                (contCmd, createOpt, contName, dockerPath)
    out = run_shellCmd(createCmd)

    startCmd = "%s start %s" % (contCmd, contName)
    out = run_shellCmd(startCmd)


# write setup for Docker/Podman container
def write_dockerSetup(filename, contCmd, contName, imageInfo, override=False):
    imageSize = imageInfo["imageCompressedSize"]
    dockerPath = imageInfo["dockerPath"]
    lastUpdate = imageInfo["lastUpdate"]

    # lsCmd = "%s exec %s ls /release_setup.sh /home/atlas/release_setup.sh 2>/dev/null" % (contCmd, contName)
    # releaseSetup = run_shellCmd(lsCmd, exitOnFailure=False)
    # if len(releaseSetup) == 0:
    #    print("!!Error!! No 'release_setup.sh' is found in the image, exit now")
    #    sys.exit(1)
    # else:
    #    items = releaseSetup.split()
    #    if len(items) > 0 and '/release_setup.sh' in items:
    #       releaseSetup = '/release_setup.sh'
    #    else:
    #       releaseSetup = items[0]

    shellFile = open(filename, 'w')
    shellFile.write("""
contCmd=%s
dockerPath=%s
imageCompressedSize=%s
imageLastUpdate=%s
contName=%s
# releaseSetup1="/release_setup.sh"
releaseSetup="/home/atlas/release_setup.sh"
jupyterOpt="-p 8888:8888 -e NB_USER=$USER -e HOME=$HOME -v ${HOME}:${HOME}"
jupyterOpt="$jupyterOpt -v /etc/passwd:/etc/passwd:ro -v /etc/group:/etc/group:ro"
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
   createCmd="$contCmd create -it -v $PWD:$PWD -w $PWD $jupyterOpt --name $contName $dockerPath"
   echo -e "\\n$createCmd"
   eval $createCmd >/dev/null
   startCmd="$contCmd start $contName"
   echo -e "\\n$startCmd"
   eval $startCmd >/dev/null
fi

if [[ $# -eq 1 && "$1" =~ ^[Jj]upyter$ ]]; then
   uid=$(id -u)
   gid=$(id -g)
   runCmd="echo Jupyter is not ready yet"
   # $contCmd exec -u ${uid}:${gid} -e USER=$USER $contName ls $releaseSetup >/dev/null
   # if [ $? -eq 0 ]; then
   #    runCmd="$contCmd exec -it -u ${uid}:${gid} -e USER=$USER $contName /bin/bash -c "'"source $releaseSetup; jupyter lab --ip 0.0.0.0"'
   # else
   #    echo "This release container can NOT run JupyterLab in non-root mode; exit now"
   #    runCmd=""
   # fi
else
   runCmd="$contCmd exec -it $contName /bin/bash --init-file $releaseSetup"
fi

if [[ $runCmd != '' ]]; then
   echo -e "\\n$runCmd\\n"
   eval $runCmd
fi

stopCmd="$contCmd stop $contName"
echo -e "\\n$stopCmd"
eval $stopCmd
""" % (contCmd, dockerPath, imageSize, lastUpdate, contName) )
    shellFile.close()


def setup(args):
    releaseTags = parseArgTags(args.tags, requireRelease=True)
    project = releaseTags['project']
    release = releaseTags['release']
    imageInfo = getImageInfo(project, release)
    # print("Found the release=%s:%s" %(project, release),"\n\t with the dockerPath=",dockerPath, "; image compressed size=",imageSize)
    # sys.exit(0)

    dockerPath = imageInfo["dockerPath"]
    contCmds = []
    for cmd in CONTAINER_CMDS:
        cmdFound = which(cmd)
        if cmdFound is not None:
           contCmds += [cmd]

    if len(contCmds) == 0:
       print("None of container running commands: docker, podman, singularity; exit now")
       print("Please install one of the above tool first")
       sys.exit(1)

    contCmd = contCmds[0]
    if args.contCmd is not None:
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
       sandboxPath = "singularity/%s-%s" % (project, release)
       build_sandbox(sandboxPath, dockerPath, args.force)
       runOpt = ''
       write_sandboxSetup(args.shellFilename, imageInfo, sandboxPath, runOpt)

    elif contCmd == "podman" or contCmd == "docker":
       testCmd = "%s info" % contCmd
       run_shellCmd(testCmd)
       contName = '_'.join([getpass.getuser(), project, release])

       create_container(contCmd, contName, imageInfo, args.force)
       write_dockerSetup(args.shellFilename, contCmd, contName, imageInfo, args.force)

    sleep(1)


def getMyImageInfo(filename):
    shellFile = open(filename, 'r')
    myImageInfo = {}
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
    if "runOpt" in myImageInfo:
       myImageInfo.pop("runOpt")
    pp = pprint.PrettyPrinter(indent=4)
    print("The image/container used in the current work directory:")
    pp.pprint(myImageInfo)


def jupyter(args):
    if not os.path.exists(args.shellFilename):
       print("No previous container/sandbox setup is found")
       myScript =  os.path.abspath(sys.argv[0])
       print("Please run 'source %s setup {ImageName}' first" % myScript)
       return None


def main():

    myScript =  os.path.basename( os.path.abspath(sys.argv[0]) )

    example_global = """Examples:

  source %s listReleases AthAnalysis
  source %s listReleases AthAnalysis,"21.2.2*"
  source %s AnalysisBase:21.2.132
  source %s            # Empty arg to rerun the already setup container
  source %s setup AnalysisBase,21.2.132""" % ((myScript,)*5)

    example_setup = """Examples:

  source %s AnalysisBase,21.2.132
  source %s --sing 21.2.132""" % (myScript, myScript)

    parser = argparse.ArgumentParser(epilog=example_global, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--shellFilename', action='store', help=argparse.SUPPRESS)
    parser.add_argument('--rerun', action='store_true', help="rerun the already setup container")
    parser.add_argument('--version', action='store_true', help="print out the script version")
    sp = parser.add_subparsers(dest='command', help='Default=setup')

    sp_listReleases = sp.add_parser('listReleases', help='list all available ATLAS releases of a given project')
    # sp_listReleases.add_argument('projectName', metavar='<ProjectName>', help='Project name to list releases')
    sp_listReleases.add_argument('tags', nargs='+', metavar='<ReleaseTags>', help='Project name to list releases, and release number with wildcard *')
    sp_listReleases.set_defaults(func=listReleases)

    sp_printImageInfo = sp.add_parser('printImageInfo', help='print the image size and last update date of the given image')
    sp_printImageInfo.add_argument('tags', nargs='+', metavar='<ReleaseTags>')
    sp_printImageInfo.set_defaults(func=printImageInfo)

    sp_printMe = sp.add_parser('printMe', help='print the container/sandbox set up for the work directory')
    sp_printMe.set_defaults(func=printMe)

    sp_update = sp.add_parser('selfUpdate', help='update the script itself')
    sp_update.set_defaults(func=selfUpdate)

    sp_setup = sp.add_parser('setup', help='create a container/sandbox for the given image', 
                    epilog=example_setup, formatter_class=argparse.RawDescriptionHelpFormatter)
    group_cmd = sp_setup.add_mutually_exclusive_group()
    for cmd in CONTAINER_CMDS:
        group_cmd.add_argument("--%s" % cmd, dest="contCmd", 
                               action="store_const", const="%s" % cmd, 
                               help="Use %s to the container" % cmd)
    sp_setup.add_argument('-f', '--force', action='store_true', default=False, help="Force to override the existing container/sandbox")
    sp_setup.add_argument('tags', nargs='+', metavar='<ReleaseTags>', help='A release to run')
    sp_setup.set_defaults(func=setup)
    set_default_subparser(parser, 'setup', 3)

    sp_update = sp.add_parser('jupyter', help='(not ready yet)run JupyterLab on the already created container/sandbox')
    sp_update.set_defaults(func=jupyter)

    args, extra = parser.parse_known_args()

    if args.version:
       version = getVersion()
       if version is not None:
          print("Version=",version)
       sys.exit(0)

    args.func(args)


if __name__ == "__main__":
    main()
