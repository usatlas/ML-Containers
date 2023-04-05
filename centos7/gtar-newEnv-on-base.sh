#!/bin/sh

CondaRoot=/opt/conda
listFilename=./list-of-dirs-$$.txt
name_newEnv=newEnv
root_newEnv=/tmp/conda
prefix_envEnv=$root_newEnv/envs/$name_newEnv

mkdir -p $root_newEnv
micromamba env create -n $name_newEnv -r $root_newEnv
cd $prefix_envEnv

find $CondaRoot -mindepth 1 -type d | sed "s#$CondaRoot/##" > $listFilename
mkdir -p `cat $listFilename`
while read subdir; do
  ln -s $CondaRoot/$subdir/* $subdir/ 2>/dev/null
done <$listFilename
rm -f $listFilename

# special cases
rm -f conda-meta/history
rm -f bin/python*
# cp -p $(echo /opt/conda/bin/python*.[0-9] | tail -1) bin/
# cd bin/
# ln -s python*.[0-9] python3
# ln -s python3 python
# cd -

gtar cfz $CondaRoot/newEnv-base.tgz *
rm -rf $root_newEnv
