# Container Images for Machine Learning

## Introduction

Why do we create custom container images for Machine Learning?

Our objective is to construct machine learning (ML) images with the following attributes:

- Tailored to our distinct requirements for customization
- Readily accessible through CVMFS deployment
- Compatible with all three AF Jupyter servers
- Facilitate seamless extensibility by users.
- Friendly and convenient user interface.

## Image Types

Currently there are 4 types of ML (Machine Learning) images built:
- **ml-base**: the **base image** of the other 3 images
- **ml-pyroot**: add **PyROOT** on top of *ml-base*
- **ml-tensorflow**: add **Tensorflow** on top of *ml-base*
- **ml-tensorflow-gpu**: add **Tensorflow-gpu** on top of *ml-base*

## Package Manager `micromamba`

`conda` could resolve package dependency very well. We use the tool `micromamba` (a very fast package manger in place of `conda`) 
to install and manage packages in image building. 

[micromamba](https://mamba.readthedocs.io/en/latest/user_guide/micromamba.html) is a tiny statically linked C++ executable. 
It supports a subset of all  `conda` commands and implements a command line interface from scratch. 
And it does not come with a default version of Python.

## Image Content

A full list of packages is saved in the file *list-of-pkgs-inside.txt* under the top directory in all images. 
This file is generated during image building, and is also uploaded into the GitHub repository.

### Packages in Image *ml-base*

The packages in the image **ml-base** are:
* package manager: micromamba
* python package manager: pipenv
* python 3.8 or 3.9
- uproot
- pandas
- scikit-learn
- seaborn
- plotly_express
- jupyterlab
- lightgbm
- xgboost
- catboost
- bash
- zsh
- tcsh

Other dependency packages:
- numpy
- scipy
- akward
- matplotlib
- plotly

For the full list of packages, please refer to the file *list-of-pkgs-inside.txt*.

### Image *ml-pyroot*

The package **PyROOT** is added into the image with the command `micromamba install ROOT`.

#### Missing Library *libGL.so*

Due to [the issue with libGL.so](https://github.com/conda-forge/pygridgen-feedstock/issues/10), 
the library *libGL.so* is not automatically installed with **ROOT** and cannot be installed by `micromamba`. 
It must be installed by the system package manager `yum`.

#### RPATH in the executable files

In the executable files in the installed **PyROOT**, the parameter **RPATH** is:
```shell
% objdump -p /opt/conda/bin/root.exe | grep PATH
  RPATH                /opt/conda/lib:$ORIGIN:$ORIGIN/../lib:/home/conda/feedstock_root/build_artifacts/root_base_1689430670413/_build_env/lib
```

The hard-coded path */opt/conda/lib* could be problematic to run this image as a virtual env on a machine which has the same directory */opt/conda/lib*. 
Since the entity *$ORIGIN/../lib* could sufficiently help find the depended libraries, we had better remove the hard-coded path */opt/conda/lib*, 
which is done by replacing it by an equal-length string */0000000000000* with the command `sed`.

#### Missing *libz* in `root-config`

The *libz* is installed together with ROOT, but it is not compatible with the system *libz*. 
The command `root-config --libs` does not include *libz*, resulting in that the incompatible system *libz* 
would be used in compiling ROOT applications. To resolve this problem, *libz* is added manually in `root-config`.

## GitHub Link

The corresponding Dockerfiles and shell scripts are hosted on the following GitHub Repo:
[https://github.com/usatlas/ML-Containers](https://github.com/usatlas/ML-Containers).

- The subdir *centos7* for CentOS7-based images
- The subdir *alma9* for Alma9-based images.
 
## Docker Image Building

To build a Docker image, says, *ml-base*, just run the following command
```shell
docker build --build-arg PyVer=3.8 -t ml-base -f ml-base.Dockerfile .
```

We would tag it to "centos7-python38" for CentOS7-based image with python-3.8, or "alma9-python39" for Alma9-based image with python-3.9. For example
```shell
% docker tag ml-base yesw2000/ml-base:centos7-python38
% docker login
% docker push yesw2000/ml-base:centos7-python38
```

The above command pushes the image onto [the Docker hub](https://hub.docker.com/) under the personal account of *yesw2000*.

### CUDA-Enabled Image Building on Machines Without a GPU

If we built the image **ml-tensorflow-gpu** on a machine without a GPU, installing the package **tensorflow-gpu** would fail with error message of *python
nothing provides \__cuda needed by tensorflow*. It is [designed by purpose](https://conda-forge.org/blog/posts/2021-11-03-tensorflow-gpu/).

To enable installing the package **tensorflow-gpu** on machines without a GPU, a special env variable **CONDA_OVERRIDE_CUDA** should be defined.

## Deployment of Singularity Images onto CVMFS

The ML images are deployed onto both BNL CVMFS and CVMFS-unpacked in Singularity sandbox format.

### Images on BNL CVMFS

The images are **manually** deployed onto BNL CVMFS under */cvmfs/atlas.sdcc.bnl.gov/users/yesw/singularity/* on the machine *cvmfswrite01* at BNL, with the following command:

```shell
% singularity build --sandbox --fix-perms -F ml-base:centos7-python38 docker://yesw2000/ml-base:centos7-python38
```

### Images on CVMFS-Unpacked

All 4 ML images are deployed onto CVMFS-unpacked **automatically** via [the wishlist](https://gitlab.cern.ch/unpacked/sync/-/blob/master/recipe.yaml) 
under */cvmfs/unpacked.cern.ch/registry.hub.docker.com/yesw2000/*.

```shell
% ls /cvmfs/unpacked.cern.ch/registry.hub.docker.com/yesw2000 
ml-base:centos7-python38            ml-tensorflow-gpu:centos7-python38
ml-pyroot:centos7-python38          pyroot-atlas:centos7-python39
ml-tensorflow-cpu:centos7-python38
```

## ML Images in Jupyter

To ensure having a clean Jupyter kernel list on the running Jupyter lab/hub with the ML images, the env variable **JUPYTER_PATH** is defined to the value */opt/conda/share/jupyter*.

Because the [jupyter_client/manager.py](https://github.com/jupyter/jupyter_client/blob/main/jupyter_client/manager.py) will 
replace `python`, `python3`, or `python3.8` with the python executable to start `jupyter-lab` or `jupyter-labhub`, the default python3 kernel 
is modified as follows (for images with *python3.8*):
```json
{
 "argv": [
  "/usr/bin/env", "python3.8", "-s",
  "-m",
  "ipykernel_launcher",
  "-f",
  "{connection_file}"
 ],
 "display_name": "ML-Python3",
 "language": "python",
 "metadata": {
  "debugger": true
 }
}
```

Here the specific version of python3, that is, **python3.8**, is used, to make it work on the BNL Jupyter hub where the outside host python path 
is **prepended** into the env variable **PATH** inside running containers. So the python3 from the inside containers, 
not from the outside host, will be used.

Using the command `env`, instead of the absolute path of command `python3`, makes the images **flexible**, 
allowing the images to be used in either containers or as virtual envs.

The python option ""**-s**"" is used to ignore user site directory under *$HOME/.local/*, which may contain incompatible packages with the images.

Meanwhile, the images also add another python3 kernel **ML-Python3-usersite**, providing an option to use user site directory in Jupyter notebook.

A screenshot of the Jupter launcher at BNL is enclosed below, which shows the two available options of 
**ML-Python3** and **ML-Python3-usersite** for Console and Notebook.

![screen of BNL Jupyter Launcher](BNL-Jupyter-Launch.png)


## Extension of ML Image Envs

Certain tools have been developed within the images to facilitate the fast extension of environments, 
enabling users to effortlessly incorporate new packages on top of the existing environment. 
These extended user environments can subsequently be conveniently reused.
### Env Extension in Container Running

Upon the container startup of the ML images, the following message would be printed out:

> % singularity run /cvmfs/unpacked.cern.ch/registry.hub.docker.com/yesw2000/ml-base:centos7-python38 
> 
> For the content in this container,
>   please read the file /list-of-pkgs-inside.txt
> 
> To create your own new env, run "**source /create-newEnv-on-base.sh** -h" for help
> Singularity>

As the message suggests, just run `source /create-newEnv-on-base.sh` to create a new extended env.
```shell
% Singularity> source /create-newEnv-on-base.sh -p myEnv

                                           __
          __  ______ ___  ____ _____ ___  / /_  ____ _
         / / / / __ `__ \/ __ `/ __ `__ \/ __ \/ __ `/
        / /_/ / / / / / / /_/ / / / / / / /_/ / /_/ /
       / .___/_/ /_/ /_/\__,_/_/ /_/ /_/_.___/\__,_/
      /_/

Empty environment created at prefix: /tmp/yesw/test-contEnv/myEnv
Next time, you can just run the following to activate your extended env
        source /tmp/yesw/test-contEnv/myEnv/setup-UserEnv-in-container.sh
(myEnv) Singularity> 
(myEnv) Singularity> ls -1 myEnv
baseEnv_dir
bin
conda-meta
etc
lib
pyvenv.cfg
sbin
setup-UserEnv-in-container.sh
share
x86_64-conda-linux-gnu
```

A new extended env is created **instantly** (**<1s**) under the current directory, 
and the env destination subdir is *myEnv* (as the option **-p myEnv"** specifies). 

A shell script *setup-UserEnv-in-container.sh* is created, saving the Singularity image path and the bind-mount paths used.

To reuse this new extended in a new session, just simply run `source /tmp/yesw/test-contEnv/myEnv/setup-UserEnv-in-container.sh`. 
It would start up the associated Singulary image, then activate this new extended env:

```shell
% source /tmp/yesw/test-contEnv/myEnv/setup-UserEnv-in-container.sh
singularity exec --env CONTAINER_USERENV=yes -B /home/tmp/yesw/test-contEnv/myEnv /cvmfs/unpacked.cern.ch/registry.hub.docker.com/yesw2000/ml-base:centos7-python38 /bin/bash --rcfile /home/tmp/yesw/test-contEnv/myEnv/setup-UserEnv-in-container.sh
Activating the user env under /home/tmp/yesw/test-contEnv/myEnv
Singularity> 
```

### Env Extension in Virtual Env

Since the images are built through `micromamba`, the images can also be used as virtual envs by sourcing the script *setupMe-on-host.sh*:

> % source /cvmfs/unpacked.cern.ch/registry.hub.docker.com/yesw2000/ml-base:centos7-python38/setupMe-on-host.sh 
> 
> To create your own new env, run "**source $EnvTopDir/create-newEnv-on-base.sh** -h" for help
> (base) %

Then we source the same script *create-newEnv-on-base.sh*** as in container running, to create an extended env:
```shell
(base) % source $EnvTopDir/create-newEnv-on-base.sh -p myEnv

                                           __
          __  ______ ___  ____ _____ ___  / /_  ____ _
         / / / / __ `__ \/ __ `/ __ `__ \/ __ \/ __ `/
        / /_/ / / / / / / /_/ / / / / / / /_/ / /_/ /
       / .___/_/ /_/ /_/\__,_/_/ /_/ /_/_.___/\__,_/
      /_/

Empty environment created at prefix: /home/tmp/yesw/test-env/myEnv
Next time, you can just run the following to activate your extended env
        source /home/tmp/yesw/test-env/myEnv/setupMe-on-host.sh
(myEnv) %
(myEnv) % ls -1 myEnv 
baseEnv_dir
bin
conda-meta
etc
lib
pyvenv.cfg
sbin
setupMe-on-host.sh
share
x86_64-conda-linux-gnu
```

The script *setupMe-on-host.sh* is copied from the image path into the new extended env subdir *myEnv*. 
And the script can be sourced to **reuse** the extended env **in a new session**:

```shell
% source /home/tmp/yesw/test-env/myEnv/setupMe-on-host.sh
(base) % micromamba info

                                           __
          __  ______ ___  ____ _____ ___  / /_  ____ _
         / / / / __ `__ \/ __ `/ __ `__ \/ __ \/ __ `/
        / /_/ / / / / / / /_/ / / / / / / /_/ / /_/ /
       / .___/_/ /_/ /_/\__,_/_/ /_/ /_/_.___/\__,_/
      /_/


            environment : base (active)
           env location : /home/tmp/yesw/test-env/myEnv
      user config files : /usatlas/u/yesw2000/.mambarc
 populated config files : /usatlas/u/yesw2000/.mambarc
                          /usatlas/u/yesw2000/.condarc
       libmamba version : 1.4.3
     micromamba version : 1.4.3
           curl version : libcurl/7.88.1 OpenSSL/3.1.0 zlib/1.2.13 zstd/1.5.2 libssh2/1.10.0 nghttp2/1.52.0
     libarchive version : libarchive 3.6.2 zlib/1.2.13 bz2lib/1.0.8 libzstd/1.5.2
       virtual packages : __unix=0=0
                          __linux=3.10.0=0
                          __glibc=2.17=0
                          __archspec=1=x86_64
               channels : https://conda.anaconda.org/conda-forge/linux-64
                          https://conda.anaconda.org/conda-forge/noarch
       base environment : /home/tmp/yesw/test-env/myEnv
               platform : linux-64
(base) %
```

### Fast Way of Env Extension

Normally, a fresh new environment is created using _micromamba_ (or _conda_) from scratch. 
To enhance efficiency, conserve space, and save time, it's preferable to construct the new environment 
on top of an existing image environment. The following steps are implemented to facilitate this process.

All subdirs and files under *$CONDA_PREFIX*, except some special files, are **sym-linked** to the new env directory. 
So we could still reuse those packages in the image env without reinstallation.

But there are about 7K subdirs and more than 60K files in the image *ml-base*. 
There are more subdirs and files in other ML images. It would take quite a while (**a few minutes**).

To speed up the above process, we can create all the sym-links in advance, and make an archive of them. 
Then just unpack the archive in the new env creation. It could reduce the time to **10s~20s**.

Upon closer examination of the subdirectories and files, it becomes evident that a significant portion of them 
originates from the Python **site-packages** directory. Nevertheless, establishing an environmental variable 
such as **PYTHONPATH** to reference the Python site-packages within the image path is not feasible. 
This is due to the fact that entries in the **PYTHONPATH** would take precedence in the Python `sys.path`, 
consequently concealing packages with identical names in the new environment.

Thankfully, the [pyvenv.cfg](https://python.readthedocs.io/en/latest/library/site.html?highlight=pyvenv%20cfg) file, 
specifically designed for Python virtual environments, offers a solution to the above challenge:

> Singularity> cat pyvenv.cfg 
> 	home = /opt/conda/bin
> 	**include-system-site-packages** = true
> 	version = 3.8.17
> Singularity> 

In the file, the parameter *include-system-site-packages* is set to true, and the `python3` 
in the new environment directory is **sym-linked** to the `python3` from the image path.

```shell
Singularity> ls -l `which python3`
lrwxrwxrwx 1 yesw2000 usatlas 26 Aug 21 21:32 /home/tmp/yesw/test-contEnv/myEnv/bin/python3 -> ../baseEnv_dir/bin/python3

Singularity> ls -l baseEnv_dir
lrwxrwxrwx 1 yesw2000 usatlas 10 Aug 22 16:21 baseEnv_dir -> /opt/conda

Singularity> python3 -s
Python 3.8.17 | packaged by conda-forge | (default, Jun 16 2023, 07:06:00) 
[GCC 11.4.0] on linux
Type "help", "copyright", "credits" or "license" for more information.
>>> import pprint
>>> pp = pprint.PrettyPrinter(indent=4)
>>> import sys
>>> pp.pprint(sys.path)
[   '',
    '/home/tmp/yesw/test-contEnv/myEnv/lib',
    '/home/tmp/yesw/test-contEnv/myEnv/lib/python3.8/site-packages',
    '/home/tmp/yesw/test-contEnv/myEnv/baseEnv_dir/lib/python38.zip',
    '/home/tmp/yesw/test-contEnv/myEnv/baseEnv_dir/lib/python3.8',
    '/home/tmp/yesw/test-contEnv/myEnv/baseEnv_dir/lib/python3.8/lib-dynload',
    '/home/tmp/yesw/test-contEnv/myEnv/baseEnv_dir/lib/python3.8/site-packages']
>>> 
```

Four entries are present in the _sys.path_ that are associated with the `python3` from the image path:

- *baseEnv_dir/lib/python38.zip*
- *baseEnv_dir/lib/python3.8*
- *baseEnv_dir/lib/python3.8/site-packages*
- *baseEnv_dir/lib/python3.8/site-packages*

With the help of *pyvenv.cfg* and the pre-created archive of sym-links, a new extended environment could be created in less than one second.


## Using ML Images on Laptops

The above section describes how to use the **read-only ML images on CVMFS**. 
This section describes how to use the ML images in **writable mode** on laptops or destktops **without CVMFS**.

A smart polyglot (shell+python) scipt [run-ml_container.sh](run-ml_container.sh) is developed, helping users to 
list the available ML images, get the image info, and set up/run a container of the image. 
Furthermore, running this script with no argument could reuse the previously created container or Singularity 
sandbox.

### Usage Help of This Script

Just run **"source run-ml_container.sh -h"** or **"./run-ml-container.sh -h"** (if this script has been set to be executable), to print the following usage help (click the expand icon ▶ to collapse the help content):

<details>
<summary>run-ml_container.sh -h</summary>
<blockquote><pre>
usage: run-ml_container.sh [-h] [--rerun]
                            {listImages,listPackages,getImageInfo,printMe,update,setup} ...

positional arguments:
  {listImages,listPackages,getImageInfo,printMe,update,setup}
                        Default=setup
    listImages          list all available ML images
    listPackages        list packages in the given image
    getImageInfo        get image size. last update date and SHA256 hash of the given image
    printMe             print the container/image set up for the work directory
    update              (not ready yet) check if the container/image here is up-to-date and
                        update it needed
    setup               create a container/sandbox for the given image

optional arguments:
  -h, --help            show this help message and exit
  --rerun               rerun the already setup container

Examples:

  source run-ml_container.sh listImages
  source run-ml_container.sh ml-base
  source run-ml_container.sh            # Empty arg to rerun the already setup container
  source run-ml_container.sh setup ml-base

</pre></blockquote>
</details>

There are a few commands in this script:

- **listImages**:       list all available ML image names together with their tag.
- **listPackages** :  list packages in the given image.
- **getImageInfo**:   get the size. last update date and SHA256 hash of a ML image.
- **setup**: create a container/sandbox for the given image
- **printMe**: print the container/sandbox previously set up for the work directory
- **update**: check if the container/sandbox here is up-to-date and update it needed.

Among them. the main command is "**setup**".

### Listing Packages in ML Images

To list the packages installed in a given image, just run:

```shell
$ source run-ml_container.sh listPackages ml-base

Found imageName= ml-base:centos7-python38
      with the following installed pkgs:
Name Version
────────────────────────────────────────────────────────────────────────────
_libgcc_mutex 0.1
_openmp_mutex 4.5
_py-xgboost-mutex 2.0
anyio 4.0.0
argon2-cffi 23.1.0
[...]
bzip2.x86_64 1.0.6-13.el7
file.x86_64 5.11-37.el7
git.x86_64 1.8.3.1-25.el7_9
which.x86_64 2.20-7.el7
```

### Print Out the ML Image Info

To get the size. last update date and SHA256 hash of a ML image, just run:

```shell
$ source run-ml_container.sh getImageInfo ml-base
Found image name= ml-base:centos7-python38

 Image compressed size= 549449620
 Last  update UTC time= 2023-09-07T14:43:58.171805Z
     Image SHA256 hash= sha256:78fe364bd448c48b476b344940b70c1b968c743c8aa4d2b0aa7351283d2d8270
```

### Container/Sandbox Setup

It supports 3 types of container commands: **podman**, **docker**, and **singularity**. The script will pick up one automatically based on the availability. You can specify an option to choose one. Just run "**source run-ml_container.sh setup -h**" for more details.

> usage: run-ml_container.sh setup [-h] [--podman | --docker | --singularity]
>                                  [-f]  \<ImageName\>
> 
> positional arguments:
>   \<ImageName\>    image name to run
> 
> optional arguments:
>   -h, --help     show this help message and exit
>   --podman       Use podman to the container
>   --docker       Use docker to the container
>   --singularity  Use singularity to the container
>   -f, --force    Force to override the existing container/sandbox
> 
> Examples:
> 
>   source run-ml_container.sh ml-base
>   source run-ml_container.sh --sing ml-base

#### Container Setup Through `podman`

On a computer with `podman` set up, the script will choose `podman` to run ML containers.

```shell
$ ./run-ml_container.sh ml-base
Found the image name= ml-base:centos7-python38  with the dockerPath= docker.io/yesw2000/ml-base:centos7-python38
Trying to pull docker.io/yesw2000/ml-base:centos7-python38...
Getting image source signatures
Copying blob 7d00c655bf55 done  
Copying blob 2ea4b90db453 done  
Copying blob b0dd0262d20c done  
Copying blob 7d00c655bf55 done  
Copying blob 2ea4b90db453 done  
Copying blob b0dd0262d20c done  
Copying blob 777139c0ccd6 done  
Copying blob 64a6649957f7 done  
Copying blob 5282a0ff22f7 done  
Copying blob 074e2b1f4561 done  
Copying blob d93432e122ad done  
Copying blob 2a7cf6658beb done  
Copying blob cab7d2991b3a done  
Copying blob d166ab952b1c done  
Copying blob 2be4cd2151f6 done  
Copying blob 17d4a1de8ca7 done  
Copying blob 0399ab42a564 done  
Copying blob 92ce03eaefb1 done  
Copying blob 679007b0c85b done  
Copying blob 7a8b17a36c6d done  
Copying config 808e3792ff done  
Writing manifest to image destination
Storing signatures
808e3792ff76a2870ff3bffeefc38bf062f56d1f3a2cc680825919c4b7b5bbb8

To reuse the same container next time, just run

         source runMe-here.sh 
 or 
         source ./run-ml_container.sh

podman exec -it yesw_ml-base_centos7-python38 /bin/bash


For the content in this container,
  please read the file /list-of-pkgs-inside.txt

To install new pkg(s), run "micromamba install pkg1 [pkg2 ...]"
(base) [root@e2a5269c74dd yesw]# 
```

After entering the container, it prints out the guide:
- how to reuse the same container next time.
- how to install new pkg(s) in the container.

To **reuse the container** in a new sesion, simply run "**runMe-here.sh**" with no argument.

```shell
$ ./run-ml_container.sh

podman exec -it yesw_ml-base_centos7-python38 /bin/bash


For the content in this container,
  please read the file /list-of-pkgs-inside.txt

To install new pkg(s), run "micromamba install pkg1 [pkg2 ...]"
(base) [root@e2a5269c74dd yesw]# 
```

The command **printMe** could help print out the information about the built container and the corresponding image. Just run "**./run-ml_container.sh printMe**":

```shell
$ ./run-ml_container.sh printMe
The image/container used in the current work directory:
{   'contCmd': 'podman',
    'contName': 'yesw_ml-base_centos7-python38',
    'dockerPath': 'docker.io/yesw2000/ml-base:centos7-python38',
    'imageCompressedSize': '549449620',
    'imageDigest': 'sha256:78fe364bd448c48b476b344940b70c1b968c743c8aa4d2b0aa7351283d2d8270',
    'imageLastUpdate': '2023-09-07T14:43:58.171805Z',
    'imageName': 'ml-base:centos7-python38'}
```

#### Container Setup Through `docker`

If a computer has `docker`, but no `podman`, running "**./run-ml_container.sh ml-base**" will create a container with the image *ml-base*, and enter into the created container:

```shell
$ ./run-ml_container.sh ml-base
Found the image name= ml-base:centos7-python38  with the dockerPath= docker.io/yesw2000/ml-base:centos7-python38
centos7-python38: Pulling from yesw2000/ml-base
777139c0ccd6: Already exists 
b0dd0262d20c: Pull complete 
64a6649957f7: Pull complete 
7d00c655bf55: Pull complete 
5282a0ff22f7: Pull complete 
2ea4b90db453: Pull complete 
074e2b1f4561: Pull complete 
d93432e122ad: Pull complete 
2a7cf6658beb: Pull complete 
cab7d2991b3a: Pull complete 
d166ab952b1c: Pull complete 
2be4cd2151f6: Pull complete 
17d4a1de8ca7: Pull complete 
0399ab42a564: Pull complete 
92ce03eaefb1: Pull complete 
679007b0c85b: Pull complete 
7a8b17a36c6d: Pull complete 
Digest: sha256:78fe364bd448c48b476b344940b70c1b968c743c8aa4d2b0aa7351283d2d8270
Status: Downloaded newer image for yesw2000/ml-base:centos7-python38
docker.io/yesw2000/ml-base:centos7-python38

To reuse the same container next time, just run

         source runMe-here.sh 
 or 
         source ./run-ml_container.sh

docker exec -it yesw_ml-base_centos7-python38 /bin/bash


For the content in this container,
  please read the file /list-of-pkgs-inside.txt

To install new pkg(s), run "micromamba install pkg1 [pkg2 ...]"
(base) [root@17ae52b4e5d4 yesw]#
```

#### Container Setup Through `singularity`

If a computer does not have either `podman`, or `docker`, and `singularity` is installed, or specifying the option `--singularity`, the script will build a Singularity sandbox for the given ML image, and run a container with the built sandbox. Just run "run-ml_container.sh -h" (click the expand icon ▶ for details)

<details>
<summary>run-ml_container.sh -h</summary>
<blockquote><pre>
$ ./run-ml_container.sh --sing ml-base                     
Found the image name= ml-base:centos7-python38  with the dockerPath= docker.io/yesw2000/ml-base:centos7-python38

Building Singularity sandbox

INFO:    Environment variable SINGULARITY_CACHEDIR is set, but APPTAINER_CACHEDIR is preferred
INFO:    Starting build...
Getting image source signatures
Copying blob 2ea4b90db453 skipped: already exists  
Copying blob 64a6649957f7 skipped: already exists  
Copying blob b0dd0262d20c skipped: already exists  
Copying blob 777139c0ccd6 skipped: already exists  
Copying blob 7d00c655bf55 skipped: already exists  
Copying blob 5282a0ff22f7 skipped: already exists  
Copying blob 074e2b1f4561 skipped: already exists  
Copying blob d93432e122ad skipped: already exists  
Copying blob 2a7cf6658beb skipped: already exists  
Copying blob cab7d2991b3a skipped: already exists  
Copying blob d166ab952b1c skipped: already exists  
Copying blob 2be4cd2151f6 skipped: already exists  
Copying blob 17d4a1de8ca7 skipped: already exists  
Copying blob 0399ab42a564 skipped: already exists  
Copying blob 92ce03eaefb1 skipped: already exists  
Copying blob 679007b0c85b skipped: already exists  
Copying blob 7a8b17a36c6d skipped: already exists  
Copying config 808e3792ff done  
Writing manifest to image destination
Storing signatures
2023/09/21 11:11:59  info unpack layer: sha256:777139c0ccd6c68e3ca9cca37b18f34fa7d2e763c9b439cb010784dfeb4d0c70
2023/09/21 11:12:00  warn rootless{usr/bin/newgidmap} ignoring (usually) harmless EPERM on setxattr "security.capability"
2023/09/21 11:12:00  warn rootless{usr/bin/newuidmap} ignoring (usually) harmless EPERM on setxattr "security.capability"
2023/09/21 11:12:00  warn rootless{usr/bin/ping} ignoring (usually) harmless EPERM on setxattr "security.capability"
2023/09/21 11:12:01  warn rootless{usr/sbin/arping} ignoring (usually) harmless EPERM on setxattr "security.capability"
2023/09/21 11:12:01  warn rootless{usr/sbin/clockdiff} ignoring (usually) harmless EPERM on setxattr "security.capability"
2023/09/21 11:12:02  info unpack layer: sha256:b0dd0262d20c84321a7527144d0f8c216048a19ea0acc8f8bc53d1c29ae18e84
2023/09/21 11:12:02  warn rootless{usr/bin/ssh-agent} ignoring (usually) harmless EPERM on setxattr "user.rootlesscontainers"
2023/09/21 11:12:03  warn rootless{usr/libexec/openssh/ssh-keysign} ignoring (usually) harmless EPERM on setxattr "user.rootlesscontainers"
2023/09/21 11:12:03  info unpack layer: sha256:64a6649957f7e754e004e7ee01146f7114b1fcd7ae4a6daccd59a37e6401c46c
2023/09/21 11:12:03  info unpack layer: sha256:7d00c655bf5523f9a44c0366ca90ed84b613e5e6df78bebca4c02cf72c5b33bf
2023/09/21 11:12:03  info unpack layer: sha256:5282a0ff22f7ecab93f0ba837a0a1794be43b00386e3744ef715dd3ca31458d3
2023/09/21 11:12:14  info unpack layer: sha256:2ea4b90db453cafb5e5f3cf8442819956b48059e16667b371ce52305fa570f17
2023/09/21 11:12:16  info unpack layer: sha256:074e2b1f4561bdd00c06142b5193481644e61e66ecbdbdcffcb6e621b4a3c59b
2023/09/21 11:12:22  info unpack layer: sha256:d93432e122ad83193ca00518ab5ac8a74422ccd2aaf6355784fc746e6a8900f9
2023/09/21 11:12:22  info unpack layer: sha256:2a7cf6658beb5378b1c57adcfecc5026c90b194df8c88f0c7390411351318fcd
2023/09/21 11:12:22  info unpack layer: sha256:cab7d2991b3a78b45486f9d4d34d3b988fb9e4ee13533c7542a5a60fe35469ac
2023/09/21 11:12:22  info unpack layer: sha256:d166ab952b1cebfc01fa010409025a518cc8dd6eb72a24f9934fc7318fec9a53
2023/09/21 11:12:22  info unpack layer: sha256:2be4cd2151f6d648cac2577d985eff0276fc9142dbbd5edeb22748ea2fd3c3d4
2023/09/21 11:12:22  info unpack layer: sha256:17d4a1de8ca77eb5e13f64951c23ee2275e9dad43502c31eedcee6bf54f3aee0
2023/09/21 11:12:22  info unpack layer: sha256:0399ab42a5641b92ad79deb315db60a8fdadb69087729e3d927589d684b39480
2023/09/21 11:12:22  info unpack layer: sha256:92ce03eaefb16be49eaeaf04ad08cdbed6ff03c3cf6a63bd8dc9178c6b2dcae3
2023/09/21 11:12:22  info unpack layer: sha256:679007b0c85b6877df6338c441b71e57576f7606ad3a33d513241d4f03cfcc16
2023/09/21 11:12:22  info unpack layer: sha256:7a8b17a36c6d92c7da8f2f18ceaee093286570c1c09d6b4da9a1a684f37e067a
WARNING: The --fix-perms option modifies the filesystem permissions on the resulting container.
INFO:    Creating sandbox directory...
INFO:    Build complete: singularity/ml-base:centos7-python38

To reuse the same container next time, just run

         source runMe-here.sh 
 or 
         source ./run-ml_container.sh

singularity run -w -H /home/yesw singularity/ml-base:centos7-python38

WARNING: nv files may not be bound with --writable
WARNING: Skipping mount /cvmfs [binds]: /cvmfs doesn't exist in container
WARNING: Skipping mount /home/condor [binds]: /home/condor doesn't exist in container
WARNING: Skipping mount /bin/nvidia-smi [files]: /usr/bin/nvidia-smi doesn't exist in container
WARNING: Skipping mount /bin/nvidia-debugdump [files]: /usr/bin/nvidia-debugdump doesn't exist in container
WARNING: Skipping mount /bin/nvidia-persistenced [files]: /usr/bin/nvidia-persistenced doesn't exist in container
WARNING: Skipping mount /bin/nvidia-cuda-mps-control [files]: /usr/bin/nvidia-cuda-mps-control doesn't exist in container
WARNING: Skipping mount /bin/nvidia-cuda-mps-server [files]: /usr/bin/nvidia-cuda-mps-server doesn't exist in container
WARNING: Skipping mount /var/run/nvidia-persistenced/socket [files]: /var/run/nvidia-persistenced/socket doesn't exist in container

For the content in this container,
  please read the file /list-of-pkgs-inside.txt

To install new pkg(s), run "micromamba install pkg1 [pkg2 ...]"
Apptainer> 
</pre></blockquote>
</details>

After starting a container of the built sandbox in **writable mode**, it also prints out the guide:
- how to reuse the same sandbox next time.
- how to install new pkg(s) in the sandbox.

Similarly, run "**./run-ml_container.sh**" with no argument to **reuse the sandbox** in a new session.

```shell
$ ./run-ml_container.sh               

singularity run -w -H /home/yesw singularity/ml-base:centos7-python38

WARNING: nv files may not be bound with --writable
WARNING: Skipping mount /cvmfs [binds]: /cvmfs doesn't exist in container
WARNING: Skipping mount /home/condor [binds]: /home/condor doesn't exist in container
WARNING: Skipping mount /bin/nvidia-smi [files]: /usr/bin/nvidia-smi doesn't exist in container
WARNING: Skipping mount /bin/nvidia-debugdump [files]: /usr/bin/nvidia-debugdump doesn't exist in container
WARNING: Skipping mount /bin/nvidia-persistenced [files]: /usr/bin/nvidia-persistenced doesn't exist in container
WARNING: Skipping mount /bin/nvidia-cuda-mps-control [files]: /usr/bin/nvidia-cuda-mps-control doesn't exist in container
WARNING: Skipping mount /bin/nvidia-cuda-mps-server [files]: /usr/bin/nvidia-cuda-mps-server doesn't exist in container
WARNING: Skipping mount /var/run/nvidia-persistenced/socket [files]: /var/run/nvidia-persistenced/socket doesn't exist in container

For the content in this container,
  please read the file /list-of-pkgs-inside.txt

To install new pkg(s), run "micromamba install pkg1 [pkg2 ...]"
Apptainer> 
```

To print out the information about the built container and the corresponding image, Just run "**./run-ml_container.sh printMe**":

```shell
$ ./run-ml_container.sh printMe
The image/container used in the current work directory:
{   'contCmd': 'singularity',
    'dockerPath': 'docker.io/yesw2000/ml-base:centos7-python38',
    'imageCompressedSize': '549449620',
    'imageDigest': 'sha256:78fe364bd448c48b476b344940b70c1b968c743c8aa4d2b0aa7351283d2d8270',
    'imageLastUpdate': '2023-09-07T14:43:58.171805Z',
    'imageName': 'ml-base:centos7-python38',
    'sandboxPath': 'singularity/ml-base:centos7-python38'}
```
