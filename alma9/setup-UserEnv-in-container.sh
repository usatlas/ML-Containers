#!/bin/bash
# A script to help set up the extended user env:
#   1. Run the associated Singularity image
#   2. Activate the user env via passing the script itself to the Singularity running

myName="${BASH_SOURCE:-$0}"
myName=$(readlink -f $myName)
myDir=$(dirname $myName)

if [ "${myDir}" = "/" ]; then
   echo "This script is to set up an extended user env, not the base env inside the container"
   return 0
fi

Image=
BindPaths=$myDir

activate_me()
{
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

   [[ -e ~/.bashrc ]] && source ~/.bashrc

   # activate the env
   unset PYTHONHOME
   echo "Activating the user env under $myDir"
   micromamba activate $myDir
}


if [ "X$Image" = "X" ]; then
   echo "!!Error!! No Singularity image path is saved in $myName; exit now"
   return 1
fi

if [ "$Image" = "$SINGULARITY_CONTAINER" ]; then
   # Already inside the container
   activate_me
   return 0
fi

if [ ! -e $Image ]; then
   echo -e "!!Error!! The following saved Singularity image path does not exist; exit now"
   echo -e "\t$Image"
   return 1
fi

cmd="singularity exec --env CONTAINER_USERENV=yes -B $BindPaths $Image /bin/bash --rcfile $myName"
echo "$cmd"
eval $cmd
