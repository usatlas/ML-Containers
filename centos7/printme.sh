if [ "X$CONTAINER_USERENV" = "X" ]; then
   echo -e "\nFor the content in this container,\n  please read the file /list-of-pkgs-inside.txt"
   if [ -e /singularity ]; then
      echo -e '\nTo create your own new env, run "source /create-newEnv-on-base.sh -h" for help'
   fi
fi
