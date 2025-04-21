#!/bin/bash

# Add usage function
usage() {
    cat << EOF
Usage: source ${BASH_SOURCE:-$0}

This script sets up a Singularity container sandbox as a virtual environment on the host machine.
It configures micromamba and conda environment settings without running an actual container.

Options:
    -h, --help    Show this help message and exit

Note: This script must be sourced, not executed directly.
EOF
}

# Add help argument handling
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    usage
    return 0
fi

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

# SSL CAFile location
export SSL_CERT_FILE=$CONDA_PREFIX/ssl/cert.pem

if [ "${CondaDir}" != "" ]; then
   export EnvTopDir=$myDir
   echo -e '\nTo create your own new env, run "source $EnvTopDir/create-newEnv-on-base.sh -h" for help'
fi
