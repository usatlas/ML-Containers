#!/bin/bash
# coding: utf-8
# version=2024-04-23-r01
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

if [[ -e $mySetup && ( $# -eq 0 || "$*" =~ "--rerun" ) ]]; then
    source $mySetup
    ret=$?
elif [[ $# -eq 1 && "$1" =~ ^[Jj]upyter$ ]]; then
    # source $mySetup jupyter
    echo "Jupyter is not ready yet"
    ret=$?
else
    if [ "X" != "X$BASH_SOURCE" ]; then
        shopt -s expand_aliases
    fi
    myDir=$(dirname $myScript)
    myDir=$(readlink -f $myDir)
    # myDir=$(py_readlink $myDir)
    if [[ $# -eq 0 ]]; then
        python3 -B -I "$myScript" --help
        ret=$?
    else
        now=$(date +"%s")
        python3 -B -I -S "$myScript" --shellFilename $mySetup "$@"
        ret=$?
        if [ -e $mySetup ]; then
            # check if the setup script is newly created
            # mtime_setup=$(py_stat $mySetup)
            mtime_setup=$(stat -c %Y $mySetup 2>/dev/null || stat -f %m $mySetup)
            if [ "$(( $mtime_setup - $now ))" -ge 0 ]; then
                echo -e "\nTo reuse the same container next time, just run"
                echo -e "\n\t source $mySetup \n or \n\t source $myScript"
                sleep 2
                source $mySetup
            fi
        fi
    fi
fi
[[ $sourced == 1 ]] && return $ret || exit $ret
'''


import getpass
import os
import sys
import io
from datetime import datetime, timezone
# from time import sleep

import argparse
import json
import pprint
import re
import subprocess
import fnmatch
import difflib

from shutil import which, rmtree
from subprocess import getstatusoutput
from urllib.request import urlopen, Request
from urllib.error import URLError, HTTPError
import ssl


GITHUB_REPO = "usatlas/ML-Containers"
GITHUB_PATH = "run-atlas_container.sh"
URL_SELF = "https://raw.githubusercontent.com/%s/main/%s" % (
            GITHUB_REPO, GITHUB_PATH)
URL_API_SELF = "https://api.github.com/repos/%s/commits?path=%s&per_page=100" % (
                GITHUB_REPO, GITHUB_PATH)
CONTAINER_CMDS = ["podman", "docker", "nerdctl", "apptainer", "singularity"]
ContCmds_available = []

DOCKERHUB_REPO = "https://hub.docker.com/v2/repositories/atlas"
# GITLAB_REPO = "https://gitlab.cern.ch/api/v4/projects"
GITLAB_REPO_ATLAS = "https://gitlab.cern.ch/api/v4/projects/53790/registry/repositories"
GITLAB_REPO_STAT = "https://gitlab.cern.ch/api/v4/projects/122672/registry/repositories"
IMAGE_CONFIG = {
     "analysisbase": {"url_repos": {"gitlab": GITLAB_REPO_ATLAS, "dockerhub": DOCKERHUB_REPO},
                      "pythonVersion": [["21.*", "python27"], ["22.*", "python37"],
                                        ["23.*", "python39"], ["24.*", "python39"]
                                        ],
                      },
     "athanalysis": {"url_repos": {"gitlab": GITLAB_REPO_ATLAS, "dockerhub": DOCKERHUB_REPO},
                    "pythonVersion": [["21.*", "python27"], ["22.*", "python37"],
                                      ["23.*", "python39"], ["24.*", "python39"]
                                      ],
                     },
     "analysistop": {"url_repos": {"gitlab": GITLAB_REPO_ATLAS, "dockerhub": DOCKERHUB_REPO},
                    "pythonVersion": [["21.*", "python27"], ["22.*", "python37"],
                                      ["23.*", "python39"], ["24.*", "python39"]
                                      ],
                     },
     "athsimulation": {"url_repos": {"gitlab": GITLAB_REPO_ATLAS, "dockerhub": DOCKERHUB_REPO},
                       "pythonVersion": [["21.*", "python27"], ["22.*", "python37"],
                                         ["23.*", "python39"], ["24.*", "python39"]
                                         ],
                       },
     "statanalysis": {"url_repos": {"gitlab": GITLAB_REPO_STAT, "dockerhub": None},
                      "pythonVersion": [["0-0-*", "python38"], ["*", "python310"]],
                      },
}
ATLAS_PROJECTS = list(IMAGE_CONFIG.keys())


class Version(str):

    def __lt__(self, other):

        va = re.split(r"[.-]", self)
        vb = re.split(r"[.-]", other)

        # print("va=",va, "; vb=",vb)

        for i in range(min(len(va), len(vb))):
            ai = va[i]
            bi = vb[i]
            if ai.isdigit() and bi.isdigit():
                if ai != bi:
                    return int(ai) < int(bi)
            elif ai != bi:
                return ai < bi

        return len(va) < len(vb)


def set_default_subparser(parser, default_subparser, index_action=1):
    """default subparser selection. Call after setup, just before parse_args()

    parser: the name of the parser you're making changes to
    default_subparser: the name of the subparser to call by default"""

    if len(sys.argv) <= index_action:
        parser.print_help()
        sys.exit(1)

    subparser_found = False
    for arg in sys.argv[1:]:
        if arg in ["-h", "--help",
                   "-V", "--version"]:  # global help or version, no default subparser
            break
        elif arg == "--gitlab" or arg == "--dockerhub":
            index_action += 1
            sys.argv.remove(arg)
            sys.argv.insert(1, arg)
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


def getUrlContent(url):
    try:
        response = urlopen(url)
    except (URLError, HTTPError) as e:
        print("Error fetching URL:", e)
        ssl_context = ssl._create_unverified_context()
        response = urlopen(url, context=ssl_context)
    return response.read().decode("utf-8")


def getUrlHeaders(url):
    try:
        response = urlopen(url)
    except (URLError, HTTPError) as e:
        print("Error fetching URL:", e)
        ssl_context = ssl._create_unverified_context()
        response = urlopen(url, context=ssl_context)
    return response.headers


def getLastCommit():
    json_obj = json.loads(getUrlContent(URL_API_SELF))
    recentCommit = json_obj[0]["commit"]["committer"]["date"]
    myScript = os.path.abspath(sys.argv[0])
    myMTime = datetime.fromtimestamp(
        os.path.getmtime(myScript), tz=timezone.utc)
    myDate = myMTime.strftime("%Y-%m-%dT%H:%M:%SZ")
    return myDate, recentCommit


def getVersion(myFile=None):
    if myFile is None:
        myScript = os.path.abspath(sys.argv[0])
        myFile = open(myScript, "r")
    else:
        if isinstance(myFile, str):
            myFile = myFile.split("\n")

    no = 0
    version = ""
    for line in myFile:
        no += 1
        if no > 10:
            break
        if re.search(r"^#.* version", line):
            version = line.split("=")[1]
            break

    if isinstance(myFile, io.IOBase):
        myFile.close()

    return version


def parseArgTags(inputArgs, requireRelease=False):
    argTags = []
    releaseTags = {}
    for arg in inputArgs:
        argTags += re.split(r"[,:]", arg)
    for tag in argTags:
        if len(tag) == 0:
            continue
        if tag.lower() in ATLAS_PROJECTS:
            releaseTags["project"] = tag.lower()
        # elif tag == "latest" or tag[0].isdigit():
        else:
            if "releases" not in releaseTags:
                releaseTags["releases"] = [tag]
            else:
                releaseTags["releases"] += [tag]
            # print("!!Warning!! Unrecognized input arg=", tag)

    if "project" not in releaseTags:
        print("The input arg tags=", argTags)
        print("!!Warning!! No project is given from the available choices:",
              ATLAS_PROJECTS)
        for argTag in argTags:
            closeProject = None
            argTag_1 = re.split(r"[-.=;]", argTag, 1)[0].lower()
            if argTag_1 in ATLAS_PROJECTS:
                closeProject = argTag_1
            if not closeProject:
                closeMatch = difflib.get_close_matches(
                    argTag.lower(), ATLAS_PROJECTS, n=1, cutoff=0.8)
                if closeMatch:
                    closeProject = closeMatch[0]
            if closeProject:
                print()
                if isinstance(closeProject, list):
                    closeProject = closeProject[0]
                print("The closest matched project=", closeProject)
                print("  against the input arg tag=", argTag)
                print("\nPlease correct it, then rerun\n")
                break
        sys.exit(1)

    if requireRelease and "releases" not in releaseTags:
        print("!!Warning!! No release is given")
        sys.exit(1)

    return releaseTags


def selfUpdate(args):
    currentVersion = getVersion()
    myDate, recentCommit = getLastCommit()
    print("The most recent GitHub commit's UTC timestamp is", recentCommit)

    content = getUrlContent(URL_SELF)
    latestVersion = getVersion(content)
    if latestVersion > currentVersion or (
            latestVersion == currentVersion and recentCommit > myDate):
        print("Update available, updating the script itself")
        myScript = os.path.abspath(sys.argv[0])
        os.rename(myScript, myScript + ".old")
        try:
            myfile = open(myScript, "w")
            myfile.write(content)
            myfile.close()
            print("Update finished")
        except Exception:
            err = sys.exc_info()[1]
            print("Failed to write out the latest version of this script\n", err)
            print("Keep the current version")
            os.rename(myScript + ".old", myScript)
        return

    print("Already up-to-date, no update needed")


def run_shellCmd(shellCmd, exitOnFailure=True):
    retCode, out = getstatusoutput(shellCmd)
    if retCode != 0 and exitOnFailure:
        print("!!Error!! Failed in running the following command")
        print("\t", shellCmd)
        sys.exit(1)
    return retCode, out


def listImageTags(project, imageSrc):
    if imageSrc is None or imageSrc == "gitlab":
        imageTags_gitlab, _ = listImageTags_gitlab(project)
    else:
        imageTags_gitlab = []
    if imageSrc is None or imageSrc == "dockerhub":
        imageTags_dockerhub = list(listImageTags_dockerhub(project).keys())
    else:
        imageTags_dockerhub = []
    return list(set(imageTags_gitlab + imageTags_dockerhub))


def listImageTags_gitlab(project):
    imageTags = []
    repoID = None
    gitlab_repo = (IMAGE_CONFIG[project])["url_repos"]["gitlab"]
    if gitlab_repo is None:
        return imageTags, repoID

    url_tags = gitlab_repo + "?tags=true"
    json_obj = json.loads(getUrlContent(url_tags))
    json_tags = {}
    for repo in json_obj:
        if repo["name"] == project or repo["path"].endswith("/" + project):
            json_tags = repo["tags"]
            repoID = repo["id"]
            break
    for tagObj in json_tags:
        imageTags += [tagObj["name"]]

    return imageTags, repoID


def listImageTags_dockerhub(project):
    dockerhub_repo = (IMAGE_CONFIG[project])["url_repos"]["dockerhub"]
    if dockerhub_repo is None:
        return {}

    url_tags = dockerhub_repo + "/" + project + "/tags?page_size=5000"
    json_obj = json.loads(getUrlContent(url_tags))
    json_tags = json_obj["results"]
    imageTags = {}
    latest_digest = ""
    latest_name = ""
    for tagObj in json_tags:
        name = tagObj["name"]
        digest = tagObj["images"][0]["digest"]
        imageSize = tagObj["full_size"]
        lastUpdate = tagObj["tag_last_pushed"]
        imageTags[name] = {
            "imageCompressedSize": imageSize,
            "lastUpdate": lastUpdate,
            "releaseName": name,
            "digest": digest}
        if name == "latest":
            latest_digest = digest
        elif latest_digest != "":
            if digest == latest_digest:
                latest_name = name

    if latest_name != "":
        imageTags["latest"]["releaseName"] = latest_name

    return imageTags


def listReleases(args):
    inputTags = args.tags
    if len(inputTags) == 0:
        print("Please specify a project name. The available projects are:\n\n",
              ATLAS_PROJECTS)
        sys.exit(1)

    releaseTags = parseArgTags(inputTags, requireRelease=False)
    project = releaseTags["project"]
    if "releases" in releaseTags:
        releases = releaseTags["releases"]
    else:
        releases = None

    imageSrc = None
    if args.dockerhub:
        imageSrc = "dockerhub"
    elif args.gitlab:
        imageSrc = "gitlab"

    imageTags = listImageTags(project, imageSrc)

    releasePrint = ""
    if releases is None:
        tags = imageTags
    else:
        tags = []
        releasesWild = []
        releasesNoWild = []
        for release in releases:
            if "*" in release or "?" in release:
                releasesWild += [release]
            else:
                releasesNoWild += [release]
        releasePrint = "matching release tag(s)=%s" % releases
        for tagName in imageTags:
            matchTag = True
            if len(releases) == 1 and tagName == releases[0]:
                tags = [tagName]
                break
            for releaseWild in releasesWild:
                if not fnmatch.fnmatch(tagName, releaseWild):
                    matchTag = False
                    break
            if not matchTag:
                continue
            for releaseNoWild in releasesNoWild:
                item_1 = releaseNoWild.split(r".")[0]
                if item_1.isdigit() and len(item_1) < 4:
                    if not tagName.startswith(releaseNoWild):
                        matchTag = False
                        break
                else:
                    if (releaseNoWild != tagName and
                        releaseNoWild not in re.split(r"[-.]", tagName)):
                        matchTag = False
                        break
            if matchTag:
                tags += [tagName]
    tags.sort(key=Version)
    if len(tags) > 0:
        columns = os.get_terminal_size().columns
        pp = pprint.PrettyPrinter(indent=4, compact=True, width=columns)
        print("Found the following release containers for the project= %s, %s\n" %
              (project, releasePrint))
        pp.pprint(tags)
        if len(tags) == 1:
            print()
            getImageInfo(project, tags[0], imageSrc)
            print("\nTo run the above image, just run")
            print("\tsource %s %s,%s" % (sys.argv[0], project, tags[0]))
    else:
        if len(releasePrint) == 0:
            print("No release container found for the project=%s" % project)
        else:
            print("No release container found for the project=%s, and %s" %
                  (project, releasePrint))


def getImageInfo(project, release, imageSrc, printOut=True):
    imageInfo = None
    if imageSrc is None or imageSrc == "gitlab":
        imageInfo = getImageInfo_gitlab(project, release, printOut)
    if imageInfo is None and (imageSrc is None or imageSrc == "dockerhub"):
        imageInfo = getImageInfo_dockerhub(project, release, printOut)
    if imageInfo is None:
        print("!!Warning!! release=%s is NOT available" % release)
        sys.exit(1)
    return imageInfo


def getImageInfo_dockerhub(project, release, printOut=True):
    imageInfo = {}
    imageTags = listImageTags_dockerhub(project)
    if release in imageTags:
        imageInfo = imageTags[release].copy()
        releaseName = imageInfo.pop("releaseName")
        imageInfo["dockerPath"] = "docker.io/atlas/%s:%s" % (
            project, releaseName)
    else:
        return None
    #     print("!!Warning!! release=%s is NOT available" % release)
    #     sys.exit(1)

    if len(imageInfo) > 0 and printOut:
        print("The matched image info:")
        print("\tdockerPath=", imageInfo["dockerPath"],
              "\n\timage compressed size=", imageInfo["imageCompressedSize"],
              "\n\tlast update time=", imageInfo["lastUpdate"],
              "\n\tdigest=", imageInfo["digest"])
    return imageInfo


def getImageInfo_gitlab(project, release, printOut=True):
    imageInfo = {}
    imageTags, repoID = listImageTags_gitlab(project)
    if release not in imageTags:
        return None
        # print("!!Warning!! release=%s is NOT available" % release)
        # sys.exit(1)

    url_tag = (IMAGE_CONFIG[project])["url_repos"]["gitlab"] + \
        "/%s/tags/%s" % (repoID, release)
    json_obj = json.loads(getUrlContent(url_tag))

    imageInfo["dockerPath"] = json_obj["location"]
    imageInfo["imageCompressedSize"] = json_obj["total_size"]
    imageInfo["lastUpdate"] = json_obj["created_at"]
    imageInfo["digest"] = json_obj["digest"]

    if len(imageInfo) > 0 and printOut:
        print("The matched image info:")
        print("\tdockerPath=", imageInfo["dockerPath"],
              "\n\timage compressed size=", imageInfo["imageCompressedSize"],
              "\n\tlast update time=", imageInfo["lastUpdate"],
              "\n\tdigest=", imageInfo["digest"])
    return imageInfo


def printImageInfo(args):
    releaseTags = parseArgTags(args.tags, requireRelease=True)
    project = releaseTags["project"]
    releases = releaseTags["releases"]
    if len(releases) > 1:
        print("Only one release tag is allowed, but multiple are given \n\t",
              releases)
        sys.exit(1)
    imageSrc = None
    if args.dockerhub:
        imageSrc = "dockerhub"
    elif args.gitlab:
        imageSrc = "gitlab"
    getImageInfo(project, releases[0], imageSrc)


# build Singularity sandbox
def build_sandbox(contCmd, sandboxPath, dockerPath, force=False):
    if os.path.exists(sandboxPath):
        if not force and os.path.exists(sandboxPath + "/entrypoint.sh"):
            print("%s already, and would not override it." % sandboxPath)
            print("\nTo override the existing sandbox, please add the option '-f'")
            print("Quit now")
            sys.exit(1)
        os.system("chmod -R +w %s; rm -rf %s" % (sandboxPath, sandboxPath))
    buildCmd = "%s build --sandbox --fix-perms -F %s docker://%s" % (
        contCmd, sandboxPath, dockerPath)
    print("\nBuilding Singularity sandbox\n")
    retCode = subprocess.call(buildCmd.split())
    if retCode != 0:
        print("!!Warning!! Building the Singularity sandbox failed. Exit now")
        sys.exit(1)


# write setup for Singularity sandbox
def write_sandboxSetup(filename, inputArgs, imageInfo, contCmd, sandboxPath,
                       bindOpt):
    imageSize = imageInfo["imageCompressedSize"]
    dockerPath = imageInfo["dockerPath"]
    lastUpdate = imageInfo["lastUpdate"]
    myScript = os.path.abspath(sys.argv[0])
    shellFile = open(filename, "w")
    shellFile.write("""
inputArgs="%s"
contCmd=%s
dockerPath=%s
imageCompressedSize=%s
imageLastUpdate=%s
sandboxPath=%s
bindOpt="%s"
releaseSetup1="/release_setup.sh"
releaseSetup2="/home/atlas/release_setup.sh"
if [ -e $sandboxPath$releaseSetup1 -o $sandboxPath$releaseSetup2 ]; then
   if [[ $# -eq 1 && "$1" =~ ^[Jj]upyter$ ]]; then
      runCmd="echo Jupyter is not ready yet"
      # runCmd=("$contCmd exec $bindOpt $sandboxPath /bin/bash -c "
      #         '"source $releaseSetup; jupyter lab"')
   else
      if [ -e $sandboxPath$releaseSetup1 ]; then
         releaseSetup=$releaseSetup1
      else
         releaseSetup=$releaseSetup2
      fi
      runCmd="$contCmd run $bindOpt $sandboxPath /bin/bash --init-file $releaseSetup"
   fi
   echo -e "\\n$runCmd\\n"
   eval $runCmd
else
   echo "The Singularity sandbox=$sandboxPath does not exist or is invalid"
   echo "Please rebuild the Singularity sandbox by running the following"
   echo -e "\n\t source %s $imageName"
fi
""" % (" ".join(inputArgs), contCmd, dockerPath, imageSize, lastUpdate,
       sandboxPath, bindOpt, myScript))
    shellFile.close()


# Failover another container command "apptainer" or "singularity"
def failOver_Singularity(args, imageInfo, oldContCmd):
    if "apptainer" in ContCmds_available or "singularity" in ContCmds_available:
        if args.contCmd != oldContCmd:
            if "apptainer" in ContCmds_available:
                newContCmd = "apptainer"
            else:
                newContCmd = "singularity"
            print("\t Next trying another container command %s again" % newContCmd)
            setup(args, imageInfo, newContCmd)
            sys.exit(0)
        else:
            print("\nYou may retry with the option --app or --sing")
            sys.exit(1)
    else:
        sys.exit(1)


# create docker/podman container
def create_container(contCmd, contName, imageInfo, bindOpt, args):
    force = args.force
    dockerPath = imageInfo["dockerPath"]
    pullCmd = "%s pull %s" % (contCmd, dockerPath)
    retCode = subprocess.call(pullCmd.split())
    # username = getpass.getuser()
    # home = os.path.expanduser("~")
    jupyterOpt = ""
    # jupyterOpt = "-p 8888:8888 -e NB_USER=%s -e HOME=%s -v %s:%s" % (username, home, home, home)
    # jupyterOpt += " -v /etc/passwd:/etc/passwd:ro -v /etc/group:/etc/group:ro"
    if retCode != 0:
        print("!!Warning!! Pulling the image %s failed, exit now" % dockerPath)
        failOver_Singularity(args, imageInfo, contCmd)

    _, out = run_shellCmd("%s ps -a -f name='%s' " % (contCmd, contName))
    if out.find(contName) > 0:
        if force:
            print("\nThe container=%s already exists, removing it now" %
                  contName)
            run_shellCmd("%s rm -f %s" % (contCmd, contName))
        else:
            print("\nThe container=%s already exists, "
                  "\n\tplease rerun the command with the option '-f' to remove it" %
                  contName)
            print("\nQuit now")
            sys.exit(1)

    pwd = os.getcwd()
    createOpt = "-it -v %s:%s -w %s %s %s" % (pwd,
                                              pwd, pwd, jupyterOpt, bindOpt)
    createCmd = "%s create %s --name %s %s" % \
                (contCmd, createOpt, contName, dockerPath)
    ret, _ = run_shellCmd(createCmd, False)
    if ret != 0:
        print("!!Error!! Failed in running the following command")
        print("\t", createCmd)
        failOver_Singularity(args, imageInfo, contCmd)

    startCmd = "%s start %s" % (contCmd, contName)
    ret, _ = run_shellCmd(startCmd, False)
    if ret != 0:
        print("!!Error!! Failed in running the following command")
        print("\t", startCmd)
        rmCmd = "%s rm -f %s" % (contCmd, contName)
        run_shellCmd(rmCmd, exitOnFailure=False)
        failOver_Singularity(args, imageInfo, contCmd)


# write setup for Docker/Podman container
def write_dockerSetup(filename, inputArgs, contCmd, contName, imageInfo,
                      bindOpt, override=False):
    imageSize = imageInfo["imageCompressedSize"]
    dockerPath = imageInfo["dockerPath"]
    lastUpdate = imageInfo["lastUpdate"]

    wcCmd = ("%s exec %s wc -l /release_setup.sh "
             "/home/atlas/release_setup.sh 2>/dev/null" % (contCmd, contName))
    _, releaseSetup = run_shellCmd(wcCmd, exitOnFailure=False)
    if len(releaseSetup.split("\n")) == 1:
        print("!!Error!! No 'release_setup.sh' is found in the image, exit now")
        sys.exit(1)
    else:
        items = releaseSetup.split()
        if "/release_setup.sh" in items:
            releaseSetup = "/release_setup.sh"
        else:
            releaseSetup = "/home/atlas/release_setup.sh"

    shellFile = open(filename, "w")
    shellFile.write("""
inputArgs="%s"
contCmd=%s
dockerPath=%s
imageCompressedSize=%s
imageLastUpdate=%s
contName=%s
bindOpt="%s"
releaseSetup=%s
jupyterOpt="-p 8888:8888 -e NB_USER=$USER -e HOME=$HOME -v ${HOME}:${HOME}"
re_exited="ago[\ ]+Exited"
re_up="ago[\ ]+Up"

listOut=$($contCmd ps -a -f name="$contName" 2>/dev/null | tail -1)

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
   createCmd=("$contCmd create -it $bindOpt -v $PWD:$PWD -w $PWD "
              "$jupyterOpt --name $contName $dockerPath")
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
   #    runCmd=("$contCmd exec -it -u ${uid}:${gid} -e USER=$USER $contName /bin/bash -c "
   #            '"source $releaseSetup; jupyter lab --ip 0.0.0.0"')
   # else
   #    echo "This release container can NOT run JupyterLab in non-root mode; exit now"
   #    runCmd=""
   # fi
else
   runCmd="$contCmd exec -it $contName /bin/bash --init-file $releaseSetup"
fi

if [[ "$runCmd" != "" ]]; then
   echo -e "\\n$runCmd\\n"
   eval $runCmd
fi

stopCmd="$contCmd stop $contName"
echo -e "\\n$stopCmd"
eval $stopCmd
""" % (" ".join(inputArgs), contCmd, dockerPath, imageSize, lastUpdate,
       contName, bindOpt, releaseSetup))
    shellFile.close()


def getMyImageInfo(filename):
    shellFile = open(filename, "r")
    myImageInfo = {}
    for line in shellFile:
        if re.search(r"^(cont|image|docker|sand|runOpt|lines).*=", line):
            key, value = line.strip().split("=")
            myImageInfo[key] = value
    return myImageInfo


def isLastRelease(filename, project, release, contCmd):
    if not os.path.exists(filename):
        return False

    myImageInfo = getMyImageInfo(filename)
    if "dockerPath" not in myImageInfo:
        return False

    dockerPath = myImageInfo["dockerPath"]
    if dockerPath.endswith("/%s:%s" % (project, release)):
        if contCmd is None or contCmd == myImageInfo["contCmd"]:
            print("The release was previously used in the current directory.\n\t Reuse it now")
            # sleep(1)
            os.utime(filename, None)
            return True

    return False


def printMe(args):
    if not os.path.exists(args.shellFilename):
        print("No previous container/sandbox setup is found")
        return None
    myImageInfo = getMyImageInfo(args.shellFilename)
    if "runOpt" in myImageInfo:
        myImageInfo.pop("runOpt")
    pp = pprint.PrettyPrinter(indent=4)
    print("The image/container used in the current work directory:")
    pp.pprint(myImageInfo)


def cleanLast(filename):
    if not os.path.exists(filename):
        return

    myImageInfo = getMyImageInfo(filename)
    if len(myImageInfo) > 0:
        contCmd = myImageInfo["contCmd"]
        if contCmd == "singularity" or contCmd == "apptainer":
            sandboxPath = myImageInfo["sandboxPath"]
            print("\nRemoving the last sandbox=%s\n" % sandboxPath)
            try:
                rmtree(sandboxPath)
            except BaseException:
                pass
            os.rename(filename, filename + ".last")
        else:
            contName = myImageInfo["contName"]
            print("\nRemoving the last container=%s\n" % contName)
            rmCmd = "%s rm -f %s" % (contCmd, contName)
            run_shellCmd(rmCmd, exitOnFailure=False)
            os.rename(filename, filename + ".last")


def prepare_setup(args):
    global ContCmds_available
    releaseTags = parseArgTags(args.tags, requireRelease=True)
    project = releaseTags["project"]
    releases = releaseTags["releases"]
    if len(releases) > 1:
        print("Only one release tag is allowed, but multiple are given \n\t",
              releases)
    release = releases[0]

    if not args.force:
        if isLastRelease(args.shellFilename, project, release, args.contCmd):
            sys.exit(0)

    imageSrc = None
    if args.dockerhub:
        imageSrc = "dockerhub"
    elif args.gitlab:
        imageSrc = "gitlab"
    imageInfo = getImageInfo(project, release, imageSrc)
    # dockerPath = imageInfo["dockerPath"]

    for cmd in CONTAINER_CMDS:
        cmdFound = which(cmd)
        if cmdFound is not None:
            ContCmds_available += [cmd]

    if len(ContCmds_available) == 0:
        print("Found none of container running commands:",
              CONTAINER_CMDS, "; exit now")
        print("Please install one of the above tool first")
        sys.exit(1)

    contCmd = ContCmds_available[0]
    if args.contCmd is not None:
        if args.contCmd in ContCmds_available:
            contCmd = args.contCmd
        else:
            print("The specified command=%s to run containers is NOT found" %
                  args.contCmd)
            print("Please choose the available command(s) on the machine to run containers")
            print("\t", ContCmds_available)
            sys.exit(1)

    cleanLast(args.shellFilename)
    return imageInfo, contCmd


def setup(args, imageInfo=None, contCmd=None):
    if imageInfo is None:
        imageInfo, contCmd = prepare_setup(args)

    dockerPath = imageInfo["dockerPath"]
    project, release = dockerPath.split("/")[-1].split(":")

    paths = args.volume
    volumes = []
    if paths is not None:
        pwd = os.getcwd()
        home = os.path.expanduser("~")
        for path in paths.split(","):
            localPath = path.split(":")[0]
            if os.path.samefile(pwd, localPath):
                continue
            elif (contCmd == "singularity" or
                  contCmd == "apptainer") and os.path.samefile(home, localPath):
                continue
            volumes += [path]

    if contCmd == "singularity" or contCmd == "apptainer":
        if not os.path.exists("singularity"):
            os.mkdir("singularity")
        sandboxPath = "singularity/%s-%s" % (project, release)
        build_sandbox(contCmd, sandboxPath, dockerPath, args.force)
        bindOpt = ""
        for path in volumes:
            bindOpt += " -B %s" % path
        write_sandboxSetup(args.shellFilename, args.tags, imageInfo, contCmd,
                           sandboxPath, bindOpt)

    elif contCmd == "podman" or contCmd == "docker" or contCmd == "nerdctl":
        testCmd = "%s info" % contCmd
        ret, _ = run_shellCmd(testCmd, False)
        if ret != 0:
            print("!!Error!! Failed in running the following command")
            print("\t", testCmd)
            failOver_Singularity(args, imageInfo, contCmd)

        contName = "_".join([getpass.getuser(), project, release])

        bindOpt = ""
        for path in volumes:
            if path.find(":") > 0:
                bindOpt += " -v %s" % path
            else:
                bindOpt += " -v %s:%s" % (path, path)

        create_container(contCmd, contName, imageInfo, bindOpt, args)
        write_dockerSetup(args.shellFilename, args.tags, contCmd, contName,
                          imageInfo, bindOpt, args.force)

    # sleep(1)


def jupyter(args):
    if not os.path.exists(args.shellFilename):
        print("No previous container/sandbox setup is found")
        myScript = os.path.abspath(sys.argv[0])
        print("Please run 'source %s setup ImageName' first" % myScript)
        return None


# Get a DockerHub token for a given scrope and username
def get_docker_hub_token(repo, username=None):
    """
    Get a Docker Hub token. If username is given, authenticate with that username.
    """
    url_token = "https://auth.docker.io/token?service=registry.docker.io&scope=repository:" + repo + ":pull"
    json_obj = json.loads(getUrlContent(url_token))
    token = json_obj["token"]
    return token


def getPullLimit(args):
    """
    Get the pull limit information for anonymous user or a given username
    """
    username = args.username
    repo = "ratelimitpreview/test"
    token = get_docker_hub_token(repo, username)
    url_digest = "https://registry-1.docker.io/v2/" + repo + "/manifests/latest"
    req = Request(url_digest, method="HEAD")
    req.add_header('Authorization', 'Bearer %s' % token)
    headers = getUrlHeaders(req)

    limit_info = {
        "ratelimit-limit": headers.get("ratelimit-limit"),
        "ratelimit-remaining": headers.get("ratelimit-remaining"),
        "docker-ratelimit-source": headers.get("docker-ratelimit-source"),
    }
    remaining = limit_info["ratelimit-remaining"]
    period_seconds = int(remaining.split('=')[-1])
    period_hours = period_seconds / 3600
    limit_remaining = int(remaining.split(';')[0])
    print("The pull limit info on the Docker Hub is:")
    print(
        "    The remaining pull limit=%i per %i hours" %
        (limit_remaining, period_hours))


def main():

    myScript = os.path.basename(os.path.abspath(sys.argv[0]))

    example_global = """Examples:

  ./%s list athanalysis,"21.2.2*"
  ./%s list AnalysisBase,24.2,alma9
  ./%s --dockerhub list athsimulation
  ./%s --gitlab list statanalysis
  ./%s    # Empty arg to rerun the already setup container
  ./%s setup AnalysisBase,21.2.132""" % ((myScript,) * 6)

    example_setup = """Examples:

  ./%s AnalysisBase,21.2.132
  ./%s --sing AnalysisBase,21.2.132""" % (myScript, myScript)

    parser = argparse.ArgumentParser(
            epilog=example_global,
            usage="%(prog)s [options]",
            formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
            "--shellFilename",
            action="store",
            help=argparse.SUPPRESS)
    parser.add_argument(
            "--rerun",
            action="store_true",
            help="rerun the already setup container")
    parser.add_argument(
            "-V", "--version",
            action="store_true",
            help="print out the script version")
    group_imageSrc = parser.add_mutually_exclusive_group()
    group_imageSrc.add_argument(
            "--gitlab",
            action="store_true",
            help="use container images from the CERN gitlab image registry")
    group_imageSrc.add_argument(
            "--dockerhub",
            action="store_true",
            help="use container images from the Docker Hub")
    sp = parser.add_subparsers(dest="command", help="Default=setup")

    sp_listReleases = sp.add_parser(
            "listReleases", aliases=["list"],
            help="list container releases",
            description="list all available ATLAS releases of a given project")
    # sp_listReleases.add_argument("projectName", metavar="<ProjectName>", help="Project name to list releases")
    sp_listReleases.add_argument(
            "tags", nargs="*", metavar="<ReleaseTags>",
            help="Project name to list releases, and release number with wildcard *")
    sp_listReleases.set_defaults(func=listReleases)

    sp_printImageInfo = sp.add_parser(
            "printImageInfo", aliases=["getImageInfo"],
            help="print Info of a container release",
            description="print the image size and last update date of the given image")
    sp_printImageInfo.add_argument("tags", nargs="+", metavar="<ReleaseTags>")
    sp_printImageInfo.set_defaults(func=printImageInfo)

    sp_printPullLimit = sp.add_parser(
        'printPullLimit',
        help='print the pull limit info on the Docker Hub',
        description='print out the pull limit info on the Docker Hub, for anonymous or a given user')
    sp_printPullLimit.add_argument(
        'username',
        nargs='?',
        metavar='<UserName>',
        help="A DockerHub name, otherwise anonymous user will be applied")
    sp_printPullLimit.set_defaults(func=getPullLimit)

    sp_printMe = sp.add_parser(
            "printMe",
            help="print info of the setup container",
            description="print the container/sandbox set up for the work directory")
    sp_printMe.set_defaults(func=printMe)

    desc = "update the script itself"
    sp_update = sp.add_parser("selfUpdate", help=desc, description=desc)
    sp_update.set_defaults(func=selfUpdate)

    sp_setup = sp.add_parser(
            "setup",
            help="set up a container release",
            description="create a container/sandbox for the given image",
            epilog=example_setup,
            formatter_class=argparse.RawDescriptionHelpFormatter)
    group_cmd = sp_setup.add_mutually_exclusive_group()
    for cmd in CONTAINER_CMDS:
        group_cmd.add_argument("--%s" % cmd, dest="contCmd",
                               action="store_const", const="%s" % cmd,
                               help="Use %s to the container" % cmd)
    sp_setup.add_argument(
            "-f", "--force",
            action="store_true", default=False,
            help="Force to override the existing container/sandbox")
    sp_setup.add_argument(
            "-B", "--volume",
            nargs="?", metavar="path[,srcPath:targePath]",
            help="Additional path(s) delimited by comma, to be mounted into the container")
    sp_setup.add_argument(
            "tags", nargs="+", metavar="<ReleaseTags>",
            help="A release to run")
    sp_setup.set_defaults(func=setup)
    set_default_subparser(parser, "setup", 3)

    sp_jupyter = sp.add_parser(
            "jupyter",
            help="(not ready) run Jupyter with the container",
            description="(not ready yet)run JupyterLab on the already created container/sandbox")
    sp_jupyter.set_defaults(func=jupyter)

    args, unknown = parser.parse_known_args()

    if unknown:
        print("Warning: Unknown options:", ", ".join(unknown))
        sys.exit(1)

    if args.version:
        version = getVersion()
        if version is not None:
            print("Version=", version)
        sys.exit(0)

    args.func(args)


if __name__ == "__main__":
    main()
