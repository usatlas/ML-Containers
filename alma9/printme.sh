if [ -z "$CONTAINER_USERENV" ] && [ -z "$PRINTME_SOURCED" ]; then
   echo -e "\nFor the content in this container,\n  please read the file /list-of-pkgs-inside.txt"
   if [ -w $CONDA_PREFIX/conda-meta/history ]; then
      echo -e '\nTo install new pkg(s), run "micromamba install pkg1 [pkg2 ...]"'
   else
      if [ -e /singularity ]; then
         echo -e '\nTo create your own new env, run "source /create-newEnv-on-base.sh -h" for help'
      fi
   fi
   export PRINTME_SOURCED=1
fi
