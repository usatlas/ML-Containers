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
- **ml-tensorflow-cpu**: add **Tensorflow-cpu** and some **keras** related packages on top of *ml-base*
- **ml-tensorflow-gpu**: add **Tensorflow-gpu** and some keras related packages on top of *ml-base*

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

For the full list of packages, please refer to the file [list-of-pkgs-inside.txt](centos7/ml-base/list-of-pkgs-inside.txt).

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

### Image ml-tensorflow-cpu and ml-tensorflow-gpu

On top base of the base image *ml-base*, the package **tensorflow** (no GPU support) and **tensorflow-gpu** are added accordingly, 
with the following additional packages:
- keras-cv: [KerasCV](https://keras.io/keras_cv/) is a library of modular computer vision components that work natively with TensorFlow, JAX, or PyTorch.
- keras-tuner: [KerasTuner](https://keras.io/keras_tuner/) is an easy-to-use, scalable hyperparameter optimization framework that solves the pain points of hyperparameter search.
- keras-nlp: [KerasNLP](https://keras.io/keras_nlp/) is a natural language processing library that works natively with TensorFlow, JAX, or PyTorch.
- tensorflow-datasets: [TensorFlow Datasets](https://www.tensorflow.org/datasets) is a collection of datasets ready to use, with TensorFlow or other Python ML frameworks, such as Jax.

## GitHub Link

The corresponding Dockerfiles and shell scripts are hosted on the following GitHub Repo:
[https://github.com/usatlas/ML-Containers](https://github.com/usatlas/ML-Containers).

- The subdir *centos7* for CentOS7-based images
- The subdir *alma9* for Alma9-based images.
 
## Docker Image Building

To build a Docker image, says, *ml-base*, just run the following command
```shell
docker build --build-arg PyVer=3.9 -t ml-base -f ml-base.Dockerfile .
```

We would tag it to "centos7-python39" for CentOS7-based image with python-3.9, or "alma9-python39" for Alma9-based image with python-3.9. For example
```shell
% docker tag ml-base yesw2000/ml-base:centos7-python39
% docker login
% docker push yesw2000/ml-base:centos7-python39
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
ml-base:alma9-python39    ml-pyroot:alma9-python39    ml-tensorflow-cpu:alma9-python39    ml-tensorflow-gpu:alma9-python39
ml-base:centos7-python38  ml-pyroot:centos7-python38  ml-tensorflow-cpu:centos7-python38  ml-tensorflow-gpu:centos7-python38
ml-base:centos7-python39  ml-pyroot:centos7-python39  ml-tensorflow-cpu:centos7-python39  ml-tensorflow-gpu:centos7-python39
pyroot-atlas:centos7-python39
```

## ML Images in Jupyter

To ensure having a clean Jupyter kernel list on the running Jupyter lab/hub with the ML images, the env variable **JUPYTER_PATH** is defined to the value */opt/conda/share/jupyter*.

Because the [jupyter_client/manager.py](https://github.com/jupyter/jupyter_client/blob/main/jupyter_client/manager.py) will 
replace `python`, `python3`, or `python3.9` with the python executable to start `jupyter-lab` or `jupyter-labhub`, the default python3 kernel 
is modified as follows (for images with *python3.9*):
```json
{
 "argv": [
 "python3-nohome", "-s",
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
where `python3-nohome` is defined as:
```shell
#!/bin/bash
myScript="${BASH_SOURCE:-$0}"
myDir=$(dirname $myScript)
myDir=$(readlink -f $myDir)
PYTHONHOME= $myDir/python3 "$@"
```

Using the script *python3-nohome* which will use the `python3` under the same path,
makes the Jupyter independent out of the outside python env,
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

> % singularity run /cvmfs/unpacked.cern.ch/registry.hub.docker.com/yesw2000/ml-base:alma9-python39
>
> For the content in this container,
>   please read the file /list-of-pkgs-inside.txt
>
> To create your own new env, run "**source /create-newEnv-on-base.sh** -h" for help
> Singularity>

As the message suggests, just run `source /create-newEnv-on-base.sh` to create a new extended env.
```shell
% Singularity> source /create-newEnv-on-base.sh -p myEnv
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
It would start up the associated Singularity image, then activate this new extended env:

```shell
% source /tmp/yesw/test-contEnv/myEnv/setup-UserEnv-in-container.sh
singularity exec --env CONTAINER_USERENV=yes -B /home/tmp/yesw/test-contEnv/myEnv /cvmfs/unpacked.cern.ch/registry.hub.docker.com/yesw2000/ml-base:alma9-python39 /bin/bash --rcfile /home/tmp/yesw/test-contEnv/myEnv/setup-UserEnv-in-container.sh
Activating the user env under /home/tmp/yesw/test-contEnv/myEnv
Singularity>
```

### Env Extension in Virtual Env

Since the images are built through `micromamba`, the images can also be used as virtual envs by sourcing the script *setupMe-on-host.sh*:

> % source /cvmfs/unpacked.cern.ch/registry.hub.docker.com/yesw2000/ml-base:alma9-python39/setupMe-on-host.sh
>
> To create your own new env, run "**source $EnvTopDir/create-newEnv-on-base.sh** -h" for help
> (base) %

Then we source the same script *create-newEnv-on-base.sh*** as in container running, to create an extended env:
```shell
(base) % source $EnvTopDir/create-newEnv-on-base.sh -p myEnv
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

       libmamba version : 1.5.7
     micromamba version : 1.5.7
           curl version : libcurl/8.5.0 OpenSSL/3.2.1 zlib/1.2.13 zstd/1.5.5 libssh2/1.11.0 nghttp2/1.58.0
     libarchive version : libarchive 3.7.2 zlib/1.2.13 bz2lib/1.0.8 libzstd/1.5.5
       envs directories : /home/tmp/yesw/test-env/myEnv/envs
          package cache : /home/tmp/yesw/test-env/myEnv/pkgs
                          /direct/usatlas+u/yesw2000/.mamba/pkgs
            environment : base (active)
           env location : /home/tmp/yesw/test-env/myEnv
      user config files : /usatlas/u/yesw2000/.mambarc
 populated config files : /usatlas/u/yesw2000/.mambarc
                          /usatlas/u/yesw2000/.condarc
       virtual packages : __unix=0=0
                          __linux=3.10.0=0
                          __glibc=2.17=0
                          __archspec=1=x86_64-v4
                          __cuda=11.6=0
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
> 	home = /cvmfs/unpacked.cern.ch/.flat/8e/8e1e32f4a80a16356dde5c933638471b7d43f042ee163b8cdba36c8b504227f6/opt/conda/bin
> 	**include-system-site-packages** = true
> 	version = 3.9.19
> Singularity>

In the file, the parameter *include-system-site-packages* is set to true, and the `python3` 
in the new environment directory is **sym-linked** to the `python3` from the image path.

```shell
Singularity> ls -l `which python3`
lrwxrwxrwx 1 yesw2000 usatlas 26 Mar 29 11:24 /home/tmp/yesw/myEnv/bin/python3 -> ../baseEnv_dir/bin/python3

Singularity> ls -l baseEnv_dir
lrwxrwxrwx 1 yesw2000 usatlas 10 Apr 15 09:45 baseEnv_dir -> /opt/conda

Singularity> python3 -s
Python 3.9.19 | packaged by conda-forge | (main, Mar 20 2024, 12:50:21) 
[GCC 12.3.0] on linux
Type "help", "copyright", "credits" or "license" for more information.
>>> import pprint
>>> pp = pprint.PrettyPrinter(indent=4)
>>> import sys
>>> pp.pprint(sys.path)
[   '',
    '/home/tmp/yesw/test-contEnv/myEnv/lib',
    '/home/tmp/yesw/test-contEnv/myEnv/lib/python3.9/site-packages',
    '/home/tmp/yesw/test-env/myEnv/lib',
    '/home/tmp/yesw/test-env/myEnv/lib/python3.9/site-packages',
    '/home/tmp/yesw/test-contEnv/myEnv/baseEnv_dir/lib/python39.zip',
    '/home/tmp/yesw/test-contEnv/myEnv/baseEnv_dir/lib/python3.9',
    '/home/tmp/yesw/test-contEnv/myEnv/baseEnv_dir/lib/python3.9/lib-dynload',
    '/home/tmp/yesw/test-contEnv/myEnv/baseEnv_dir/lib/python3.9/site-packages']
>>>
```

Four entries are present in the _sys.path_ that are associated with the `python3` from the image path:

- *baseEnv_dir/lib/python39.zip*
- *baseEnv_dir/lib/python3.9*
- *baseEnv_dir/lib/python3.9/site-packages*
- *baseEnv_dir/lib/python3.9/site-packages*

With the help of *pyvenv.cfg* and the pre-created archive of sym-links, a new extended environment could be created in less than one second.


## Using ML Images on Laptops

The above section describes how to use the **read-only ML images on CVMFS**.
This section describes how to use the ML images in **writable mode** on laptops or destktops **without CVMFS**.

A smart polyglot (shell+python) script [run-ml_container.sh](run-ml_container.sh) is developed, helping users to
list the available ML images, get the image info, and set up/run a container of the image.
Furthermore, running this script with no argument could reuse the previously created container or Singularity
sandbox.

### Usage Help of This Script

Just run **"source run-ml_container.sh -h"** or **"./run-ml-container.sh -h"** (if this script has been set to be executable),
to print the following usage help (click the expand icon ▶ to collapse the help content):

<details>
<summary>run-ml_container.sh -h</summary>
<blockquote><pre>
usage: run-ml_container.sh [options]

    positional arguments:
    {listImages,listPackages,printImageInfo,printPullLimitInfo,printMe,update,selfUpdate,setup,jupyter}
                          Default=setup
      listImages          list all available ML images
      listPackages        list packages in the given image
      printImageInfo      print Image Info
      printPullLimitInfo  print the pull limit info
      printMe             print info of the setup container
      update              update the container image
      selfUpdate          update the script itself
      setup               set up container
      jupyter             run Jupyter with the container

  optional arguments:
    -h, --help            show this help message and exit
    --rerun               rerun the already setup container
    -V, --version         print out the script version

  Examples:

    source run-ml_container.sh listImages
    source run-ml_container.sh ml-base:centos7-python39
    source run-ml_container.sh            # Empty arg to rerun the already setup container
    source run-ml_container.sh setup ml-base:centos7-python39
/pre></blockquote>
</details>

There are a few commands in this script:

- **listImages**:      list all available ML image names together with their tag.
- **listPackages** :   list packages in the given image.
- **printImageInfo**:  print the size. last update date and SHA256 hash of a ML image.
- **printMe**: print the container/sandbox previously set up for the work directory
- **setup**: create a container/sandbox for the given image
- **update**: check if the container/sandbox here is up-to-date and update it needed.
- **selfUpdate**: update the script itself
- **jupyter**: run Jupyter with the container

Among them. the main and default command is "**setup**".

You can **update the script itself** by running the command **selfUpdate**.

### Listing Packages in ML Images

To list the packages installed in a given image, just run:

```shell
$ source run-ml_container.sh listPackages ml-base:alma9-python39

Found imageName= ml-base:alma9-python39  with the following installed pkgs:
alembic 1.13.1
anyio 4.3.0
argon2-cffi 23.1.0
argon2-cffi-bindings 21.2.0
arrow 1.3.0
asdf 3.1.0
[...]
zstandard 0.22.0
zstd 1.5.5
_libgcc_mutex 0.1
_openmp_mutex 4.5
_py-xgboost-mutex 2.0
```

### Print Out the ML Image Info

To get the size. last update date and SHA256 hash of a ML image, just run:

```shell
$ source run-ml_container.sh printImageInfo ml-base:alma9-python39
Found image name= ml-base:alma9-python39

 Image compressed size= 607630023
        Image raw size= 1884641257
          imageVersion= 2024-04-04-r01
 Last  update UTC time= 2024-04-04T18:59:07.700114Z
     Image SHA256 hash= sha256:73aaf2e029b28eca50224b76e2dc6e2f623eb1eac6f014f6351f6adc82160bc0
```

### Container/Sandbox Setup

The script supports 5 types of container commands: **podman**, **docker**, **nerdctl**, and **apptainer/singularity**.
The script will pick up one automatically based on the availability. You can specify an option to choose one.
Run "**source run-ml_container.sh setup -h**" for more details.

> usage: run-ml_container.sh setup [-h] [--podman | --docker | --nerdctl | --apptainer | --singularity]
>                                  [-f]  \<ImageName\>
> 
> positional arguments:
>   \<ImageName\>    image name to run
> 
> optional arguments:
>   -h, --help     show this help message and exit
>   --podman       Use podman to the container
>   --docker       Use docker to the container
>   --nerdctl      Use nerdctl to the container
>   --apptainer    Use apptainer to the container
>   --singularity  Use singularity to the container
>   -f, --force    Force to override the existing container/sandbox
> 
> Examples:
> 
>   source run-ml_container.sh ml-base:alma9-python39
>   source run-ml_container.sh --sing ml-base:alma9-python39

#### Container Setup Through `podman`

On a computer with `podman` set up, the script will choose `podman` to run ML containers.

```shell
$ source run-ml_container.sh ml-base:alma9-python39
Found the image name= ml-base:alma9-python39  with the dockerPath= docker.io/yesw2000/ml-base:alma9-python39
Trying to pull docker.io/yesw2000/ml-base:alma9-python39...
Getting image source signatures
Copying blob 6097345d637a done
Copying blob 7a937440caca done
Copying blob d933cb84e3aa done
Copying blob 28130cb29ede done
Copying blob 530edc475e19 done
Copying blob c7f7646ff892 done
Copying blob 4c85af436900 done
Copying blob 3acd9b065b0a done
Copying blob f888eaa67bc6 done
Copying blob 9d98ec5991a7 done
Copying blob 16b7ec60d120 done
Copying blob 3331c62c6de8 done
Copying blob 5c70e679fbad done
Copying blob fc30790884f5 done
Copying blob 56c2bc116035 done
Copying blob 80b76dfb172b done
Copying blob c06b11ec7568 done
Copying blob ee4d109e1b58 done
Copying blob 2ba11ebdb71e done
Copying blob 5bf4205fcecd done
Copying config 8e1e32f4a8 done
Writing manifest to image destination
8e1e32f4a80a16356dde5c933638471b7d43f042ee163b8cdba36c8b504227f6

To reuse the same container next time, just run

         source runML-here.sh
 or
         source run-ml_container.sh

podman exec -it yesw_ml-base_alma9-python39 /bin/bash

root@9c33313100b4:[1]%
```

After entering the container, it prints out the guide:
- how to reuse the same container next time.
- how to install new pkg(s) in the container.

To **reuse the container** in a new session, simply run "**runMe-here.sh**" with no argument.

```shell
$ source run-ml_container.sh

podman exec -it yesw_ml-base_alma9-python39 /bin/bash

For the content in this container,
  please read the file /list-of-pkgs-inside.txt

To install new pkg(s), run "micromamba install pkg1 [pkg2 ...]"
root@9c33313100b4:[1]%
```

Inside the container, to **install a new package** *dask*, just run "*micromamba install -y dask*" (click the expand icon ▶ for details).

<details>
<summary>micromamba install -y dask</summary>
<blockquote><pre>
(base) [root@e2a5269c74dd yesw]# micromamba install -y dask
conda-forge/noarch                                  14.3MB @  19.6MB/s  0.8s
    conda-forge/linux-64                                33.7MB @  29.0MB/s  1.4s

    Pinned packages:
    - python 3.9.*


  Transaction

    Prefix: /opt/conda

    Updating specs:

     - dask


    Package                       Version  Build               Channel           Size
  ─────────────────────────────────────────────────────────────────────────────────────
    Install:
  ─────────────────────────────────────────────────────────────────────────────────────

    + locket                        1.0.0  pyhd8ed1ab_0        conda-forge     Cached
    + zict                          3.0.0  pyhd8ed1ab_0        conda-forge     Cached
  [...]
Linking distributed-2024.4.1-pyhd8ed1ab_0
  Linking pyarrow-hotfix-0.6-pyhd8ed1ab_0
  Linking dask-expr-1.0.11-pyhd8ed1ab_0
  Linking dask-2024.4.1-pyhd8ed1ab_0

  Transaction finished

To activate this environment, use:

    micromamba activate base

Or to execute a single command in this environment, use:

    micromamba run -n base mycommand

(base) [root@e2a5269c74dd yesw]#

</pre></blockquote>
</details>

The command **printMe** could help print out the information about the built container and the corresponding image.
Just run "**./run-ml_container.sh printMe**":

```shell
$ source ./run-ml_container.sh printMe
The image/container used in the current work directory:
{   'contCmd': 'podman',
    'contName': 'yesw2000_ml-base_alma9-python39',
    'dockerPath': 'docker.io/yesw2000/ml-base:alma9-python39',
    'imageCompressedSize': '607630023',
    'imageDigest': 'sha256:73aaf2e029b28eca50224b76e2dc6e2f623eb1eac6f014f6351f6adc82160bc0',
    'imageLastUpdate': '2024-04-04T18:59:07.700114Z',
    'imageName': 'ml-base:alma9-python39'}

The following additional pkgs and their dependencies are installed
['dask']
```

#### Container Setup Through `singularity`

If a computer does not have either `podman`, or `docker`, and `singularity` is installed,
or specifying the option `--singularity`,
the script will build (which would take a while) a Singularity sandbox for the given ML image,
and run a container with the built sandbox.
Just run "./run-ml_container.sh --sing ml-base:alma9-python39" (click the expand icon ▶ for details)

<details>
<summary>./run-ml_container.sh --sing ml-base:alma9-python39</summary>
<blockquote><pre>
$ source ./run-ml_container.sh --sing ml-base:alma9-python39
Found the image name= ml-base:alma9-python39  with the dockerPath= docker.io/yesw2000/ml-base:alma9-python39

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
INFO:    Build complete: singularity/ml-base:alma9-python39

To reuse the same container next time, just run

         source runMe-here.sh 
 or 
         source ./run-ml_container.sh

singularity run -w -H /home/yesw singularity/ml-base:alma9-python39

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

singularity run -w -H /home/yesw singularity/ml-base:alma9-python39

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
    'dockerPath': 'docker.io/yesw2000/ml-base:alma9-python39',
    'imageCompressedSize': '549449620',
    'imageDigest': 'sha256:78fe364bd448c48b476b344940b70c1b968c743c8aa4d2b0aa7351283d2d8270',
    'imageLastUpdate': '2023-09-07T14:43:58.171805Z',
    'imageName': 'ml-base:alma9-python39',
    'sandboxPath': 'singularity/ml-base:alma9-python39'}
```
### Run Jupyter Locally with the Setup ML Container

After having set up a ML container, you can start up a Jupyter lab with the set up ML image.

```shell
$ ./run-ml_container.sh jupyter

docker exec -it -u 1000:1000 -e USER=yesw2000 yesw2000_ml-base_alma9-python39 jupyter lab --ip 0.0.0.0      

[...]
[C 2023-12-07 19:35:35.901 ServerApp]

    To access the server, open this file in a browser:
        file:///home/yesw2000/.local/share/jupyter/runtime/jpserver-49-open.html
    Or copy and paste one of these URLs:
        http://7140f84ebda5:8888/lab?token=1530678993878f9b3736671933a6dce2741163b1afe30f63
        http://127.0.0.1:8888/lab?token=1530678993878f9b3736671933a6dce2741163b1afe30f63
[...]
```
Then just follow the printed instruction, open the URL on your local browser.
