#!/bin/bash

myName="${BASH_SOURCE:-$0}"
myDir=$(dirname $myName)
myDir=$(readlink -f -- $myDir)

if [ "${myDir}" = "/" ]; then
   echo "Already inside the container, no need to source this setup script, exit now"
   return 0
fi

if [ ${#PYTHONPATH} -gt 0 ]; then
   export PYTHONPATH=${PYTHONPATH}:$myDir/usr/local/lib/python3.8/site-packages
else
   export PYTHONPATH=$myDir/usr/local/lib/python3.8/site-packages
fi

CUDALIB=$myDir/usr/local/cuda-11.0/lib64
myLibs=$myDir/lib64:$myDir/usr/local/lib:$CUDALIB
if [ ${#LD_LIBRARY_PATH} -gt 0 ]; then
   grep -q  ":/lib64:" <<< ":$LD_LIBRARY_PATH:"
   if [ $? -eq 0 ]; then
      export LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:$myLibs
   else
      if [ -d /lib/x86_64-linux-gnu ]; then
         export LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:/lib64:/lib/x86_64-linux-gnu:$myLibs
      else
         export LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:/lib64:$myLibs
      fi
   fi
else
   if [ -d /lib/x86_64-linux-gnu ]; then
      export LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:/lib64:/lib/x86_64-linux-gnu:$myLibs
   else
      export LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:/lib64:$myLibs
   fi
fi

if [ ${#PATH} -gt 0 ]; then
   export PATH=$PATH:${myDir}/usr/local/bin:${myDir}/usr/bin
else
   export PATH=${myDir}/usr/local/bin:${myDir}/usr/bin
fi

alias python3=python3.8

echo "For the content in this container, please read the file $myDir/00Readme.txt"
