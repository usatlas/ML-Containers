#!/bin/bash

myName="${BASH_SOURCE:-$0}"
myDir=$(dirname $myName)
myDir=$(readlink -f -- $myDir)

if [ "${myDir}" = "/" ]; then
   echo "Already inside the container, no need to source this setup script, exit now"
   return 0
fi

\which micromamba >/dev/null 2>&1
if [ $? -ne 0 ]; then
   export MAMBA_EXE=$myDir/bin/micromamba
else
   export MAMBA_EXE=$(\which micromamba)
fi

shellName=$(readlink /proc/$$/exe | awk -F "[/-]" '{print $NF}')
typeset -f micromamba >/dev/null || eval "$($MAMBA_EXE shell hook --shell=$shellName)"

# micromamba activate $myDir/opt/conda
unset PYTHONHOME
export CONDA_PREFIX=$myDir/opt/conda
export MAMBA_ROOT_PREFIX=$CONDA_PREFIX
micromamba activate
