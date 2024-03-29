#!/bin/sh

CondaRoot=/opt/conda
listFilename=./list-of-dirs-$$.txt
name_newEnv=newEnv
root_newEnv=/tmp/conda
prefix_envEnv=$root_newEnv/envs/$name_newEnv

mkdir -p $root_newEnv
micromamba env create -n $name_newEnv -r $root_newEnv
cd $prefix_envEnv
ln -s $CondaRoot baseEnv_dir

echo -e "conda-meta\nbin\nsbin" > $listFilename
find $CondaRoot/etc -type d | sed "s#$CondaRoot/##" >> $listFilename
find $CondaRoot/ssl -type d | sed "s#$CondaRoot/##" >> $listFilename
find $CondaRoot/share/jupyter -type d | sed "s#$CondaRoot/##" >> $listFilename
find $CondaRoot/x86_64-conda-linux-gnu | sed "s#$CondaRoot/##" >> $listFilename
find $CondaRoot/lib -type d | grep -v "site-packages" | sed "s#$CondaRoot/##" >> $listFilename

mkdir -p `cat $listFilename`
while read subdir; do
  cd $subdir
  parentDots=$(echo $subdir | sed 's%[^/]*%..%g')
  ln -s $parentDots/baseEnv_dir/$subdir/* ./ 2>/dev/null
  cd $prefix_envEnv
done <$listFilename
rm -f $listFilename

# special activate and deactivate scrpt to handle envvar PYTHONPATH
cat > etc/conda/activate.d/activate-python.sh <<EOF
# save the original PYTHONPATH if set
if ! [ -z "\${PYTHONPATH+_}" ] ; then
    CONDA_BACKUP_PYTHONPATH="\$PYTHONPATH"
    PYTHONPATH=\$CONDA_PREFIX/lib:\$CONDA_PREFIX/lib/python$(python3 --version | cut -d' ' -f2 | cut -d'.' -f1-2)/site-packages:\${PYTHONPATH}
else
    export PYTHONPATH=\$CONDA_PREFIX/lib:\$CONDA_PREFIX/lib/python$(python3 --version | cut -d' ' -f2 | cut -d'.' -f1-2)/site-packages
fi
EOF

cat > etc/conda/deactivate.d/deactivate-python.sh <<EOF
# restore the original PYTHONPATH if available
if ! [ -z "\${CONDA_BACKUP_PYTHONPATH+_}" ] ; then
    export PYTHONPATH=\$CONDA_BACKUP_PYTHONPATH
    unset CONDA_BACKUP_PYTHONPATH
else
    unset PYTHONPATH
fi
EOF

# special file and subdir
rm -f conda-meta/history
rm -f baseEnv_dir
rm -f lib/python*/site-packages

gtar cfz $CondaRoot/newEnv-base.tgz *
rm -rf $root_newEnv
