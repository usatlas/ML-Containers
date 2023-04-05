#!/bin/bash

# export LD_LIBRARY_PATH=/usr/lib64:/usr/local/nvidia/lib:/usr/local/nvidia/lib64:/usr/local/cuda-11.1/lib64:/usr/local/cuda-11.2/lib64

## Do whatever you need with env vars here ...
source /usr/local/bin/_activate_current_env.sh
# source /printme.sh

# Hand off to the CMD
if [ "$@" == "/bin/bash" ]; then
   CMD="$@ -rcfile /usr/local/bin/_activate_current_env.sh"
   eval "set $CMD"
fi
exec "$@"
