# Image Types

Currently there are 4 types of ML (Machine Learning) images built:
- **ml-base**: the **base image** of the other 3 images
- **ml-pyroot**: add **PyROOT** on top of *ml-base*
- **ml-tensorflow**: add **Tensorflow** on top of *ml-base*
- **ml-tensorflow-gpu**: add **Tensorflow-gpu** on top of *ml-base*

# Package Manager `micromamba`

`conda` could resolve package dependency very well. We use the tool `micromamba` (a very fast package manger in place of `conda`) 
to install and manage packages in image building. 

[micromamba](https://mamba.readthedocs.io/en/latest/user_guide/micromamba.html) is a tiny statically linked C++ executable. 
It supports a subset of all  `conda` commands and implements a command line interface from scratch. 
And it does not come with a default version of Python.

# Image Content

A full list of packages is saved in the file *list-of-pkgs-inside.txt* under the top directory in all images. 
This file is generated during image building, and is also uploaded into the GitHub repository.

## Packages in Image *ml-base*

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

## Image *ml-pyroot*

The package **PyROOT** is added into the image with the command `micromamba install ROOT`.

### Missing Library *libGL.so*

Due to [the issue with libGL.so](https://github.com/conda-forge/pygridgen-feedstock/issues/10), 
the library *libGL.so* is not automatically installed with **ROOT** and cannot be installed by `micromamba`. 
It must be installed by the system package manager `yum`.

### RPATH in the executable files

In the executable files in the installed **PyROOT**, the parameter **RPATH** is:
```shell
% objdump -p /opt/conda/bin/root.exe | grep PATH
  RPATH                /opt/conda/lib:$ORIGIN:$ORIGIN/../lib:/home/conda/feedstock_root/build_artifacts/root_base_1689430670413/_build_env/lib
```

The hard-coded path */opt/conda/lib* could be problematic to run this image as a virtual env on a machine which has the same directory */opt/conda/lib*. 
Since the entity *$ORIGIN/../lib* could sufficiently help find the depended libraries, we had better remove the hard-coded path */opt/conda/lib*, 
which is done by replacing it by an equal-length string */0000000000000* with the command `sed`.

# GitHub Link

The corresponding Dockerfiles and shell scripts are hosted on the following GitHub Repo:
[https://github.com/usatlas/ML-Containers](https://github.com/usatlas/ML-Containers).

- The subdir *centos7* for CentOS7-based images
- The subdir *alma9* for Alma9-based images.
 
# Docker Image Building

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

## CUDA-Enabled Image Building on Machines Without a GPU

If we built the image **ml-tensorflow-gpu** on a machine without a GPU, installing the package **tensorflow-gpu** would fail with error message of *python
nothing provides \__cuda needed by tensorflow*. It is [designed by purpose](https://conda-forge.org/blog/posts/2021-11-03-tensorflow-gpu/).

To enable installing the package **tensorflow-gpu** on machines without a GPU, a special env variable **CONDA_OVERRIDE_CUDA** should be defined.

# Deployment of Singularity Images onto CVMFS

The ML images are deployed onto both BNL CVMFS and CVMFS-unpacked in Singularity sandbox format.

## Images on BNL CVMFS

The images are **manually** deployed onto BNL CVMFS under */cvmfs/atlas.sdcc.bnl.gov/users/yesw/singularity/* on the machine *cvmfswrite01* at BNL, with the following command:

```shell
% singularity build --sandbox --fix-perms -F ml-base:centos7-python38 docker://yesw2000/ml-base:centos7-python38
```

## Images on CVMFS-Unpacked

All 4 ML images are deployed onto CVMFS-unpacked **automatically** via [the wishlist](https://gitlab.cern.ch/unpacked/sync/-/blob/master/recipe.yaml) 
under */cvmfs/unpacked.cern.ch/registry.hub.docker.com/yesw2000/*.

```shell
% ls /cvmfs/unpacked.cern.ch/registry.hub.docker.com/yesw2000 
ml-base:centos7-python38            ml-tensorflow-gpu:centos7-python38
ml-pyroot:centos7-python38          pyroot-atlas:centos7-python39
ml-tensorflow-cpu:centos7-python38
```

# ML Images in Jupyter

To ensure having a clean Jupyter kernel list on the running Jupyter lab/hub with the ML images, the env variable **JUPYTER_PATH** is defined to the value */opt/conda/share/jupyter*.

Because the [jupyter_client/manager.py](https://github.com/jupyter/jupyter_client/blob/main/jupyter_client/manager.py) will 
replace `python`, `python3`, or `python3.8` with the python executable to start `jupyter-lab` or `jupyter-labhub`, the default python3 kernel 
is modified as follows (for images with *python3.8*):
```json
{
 "argv": [
  "/usr/bin/env", "python3.8", "-I",
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
is **prepended** into the env variable **PATH** inside running containers. So the python3 from the inside containers, not from the outside host, will be used.

Using the command `env`, instead of the absolute path of command `python3`, makes the images **flexible**, allowing the images to be used in either containers or as virtual envs.

The python option ""**-I**"" is used to make python run in an isolated mode, free from the outside python-related env variables 
such as **PYTHONHOME** and **PYTHONPATH**, and free from the users' private site-packages under *$HOME/.local/*.

