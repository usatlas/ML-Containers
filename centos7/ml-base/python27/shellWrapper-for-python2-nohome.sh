#!/bin/bash
# coding: utf-8
"true" '''\'
myScript="${BASH_SOURCE:-$0}"
ret=0
if [ -e $0 ]; then
   myDir=$(dirname $myScript)
   myDir=$(readlink -f $myDir)
   PYTHONHOME=$myDir/.. PYTHONPATH=$myDir/../lib/python2.7/site-packages:${PYTHONPATH} $myDir/python2 -S "$myScript" "$@"
   ret=$?
fi
exit $ret
'''
