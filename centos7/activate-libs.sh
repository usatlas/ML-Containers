# add new element into LD_LIBRARY_PATH
if [ -z "${LD_LIBRARY_PATH+x}" ] ; then
   export LD_LIBRARY_PATH=$CONDA_PREFIX/lib
else
   export CONDA_BACKUP_LD_LIBRARY_PATH="$LD_LIBRARY_PATH"
   export LD_LIBRARY_PATH=$CONDA_PREFIX/lib:${LD_LIBRARY_PATH}
fi
