#!/bin/bash

myName="${BASH_SOURCE:-$0}"
myDir=$(dirname $myName)
myDir=$(readlink -f -- $myDir)

if [ "${myDir}" = "/" ]; then
   echo "Already inside the container, no need to source this setup script, exit now"
   return 0
fi

export MAMBA_EXE=$myDir/bin/micromamba

shellName=$(readlink /proc/$$/exe | awk -F "[/-]" '{print $NF}')
typeset -f micromamba >/dev/null || eval "$($MAMBA_EXE shell hook --shell=$shellName)"

# activate the env
CondaDir=/opt/conda
export CONDA_PREFIX=$myDir${CondaDir}
if [ ! -d $CONDA_PREFIX ]; then
   CondaDir=""
fi
export CONDA_PREFIX=$myDir${CondaDir}
export MAMBA_ROOT_PREFIX=$CONDA_PREFIX
if [ -d $CONDA_PREFIX/share/jupyter ]; then
   export JUPYTER_PATH=$CONDA_PREFIX/share/jupyter
fi
micromamba activate

unset PYTHONHOME

if [ "${CondaDir}" != "" ]; then
   export EnvTopDir=$myDir
   echo -e '\nTo create your own new env, run "source $EnvTopDir/create-newEnv-on-base.sh -h" for help'
fi
