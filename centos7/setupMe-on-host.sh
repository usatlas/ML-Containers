#!/bin/bash

myName="${BASH_SOURCE:-$0}"
myDir=$(dirname $myName)
myDir=$(readlink -f -- $myDir)

if [ "${myDir}" = "/" ]; then
   echo "Already inside the container, no need to source this setup script, exit now"
   return 0
fi

if [ "X$MAMBA_EXE" = "X" ]; then
   \which micromamba >/dev/null 2>&1
   if [ $? -ne 0 ]; then
      export MAMBA_EXE=$myDir/bin/micromamba
   else
      export MAMBA_EXE=$(\which micromamba)
   fi
fi

shellName=$(readlink /proc/$$/exe | awk -F "[/-]" '{print $NF}')
typeset -f micromamba >/dev/null || eval "$($MAMBA_EXE shell hook --shell=$shellName)"

# activate the env
unset PYTHONHOME
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
