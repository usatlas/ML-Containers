if [ "X$CONTAINER_USERENV" = "X" ]; then
   echo -e "\nFor the content in this container,\n  please read the file /list-of-pkgs-inside.txt\n"
   if [ -e /singularity ]; then
      echo -e '\nTo create your own new env, run "source /create-newEnv-on-base.sh -h" for help'
   fi
fi

libCUDA=""
if [ -e /singularity ]; then
   libCUDA=$(ls /.singularity.d/libs/libcuda.so 2>/dev/null)
else
   libCUDA=$(ls /usr/local/nvidia/lib64/libcuda.so /usr/local/cuda/lib64/libcuda.so 2>/dev/null)
fi

if [ "X$libCUDA" == "X" ]; then
   lspci | grep -i nvidia > /dev/null 2>&1
   if [ $? -eq 0 ]; then
      echo "GPU is found on the machine"
      echo "    Please bind-mount libcuda.so onto /usr/local/cuda/lib64 from the host machine"
   fi
fi
