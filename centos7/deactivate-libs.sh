# restore the original LD_LIBRARY_PATH if available
if [ -z "${CONDA_BACKUP_LD_LIBRARY_PATH+x}" ] ; then
   unset LD_LIBRARY_PATH
else
   export LD_LIBRARY_PATH=$CONDA_BACKUP_LD_LIBRARY_PATH
   unset CONDA_BACKUP_LD_LIBRARY_PATH
fi
