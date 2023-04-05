CondaRoot=/opt/conda

PROGNAME=$0
usage()
{
  cat << EO
        Create a new env on top of the existing base env

        Usage: $PROGNAME -h|--help
               $PROGNAME -n|--name newEnvName -r|--root-prefix prefixRoot
EO
}

if [ $BASH_SOURCE == $0 ]; then
   echo "DO NOT run this script, please _source_  $PROGNAME instead"
   usage
   exit 1
fi

while (( "$#" )); do
  case "$1" in
    -h|--help)
      usage
      return 0
      ;;
    -n|--name)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        newEnvName=$2
        shift 2
      else
        echo "Error: Argument for $1 is missing" >&2
        return 1
      fi
      ;;
    -r|--root-prefix)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        prefixRoot=$2
        shift 2
      else
        echo "Error: Argument for $1 is missing" >&2
        return 1
      fi
      ;;
    *) # unsupported flags
      echo "Error: Unsupported flag or arg $1" >&2
      return 1
      ;;
  esac
done

if [ "$newEnvName" == "" -o "$prefixRoot" == "" ]; then
   echo "missing newEnvName or prefixRoot"
   usage
   return 1
fi

# echo "newEnvName=$newEnvName; prefixRoot=$prefixRoot"

if [ ! -d $prefixRoot ]; then
   mkdir -p $prefixRoot
   if [ $? -ne 0 ]; then
      echo "$prefixRoot does not exist, cannot create it either; exit now"
      return 1
   fi
fi

[[ $(type -t micromamba) != "function" ]] && source /usr/local/bin/_activate_current_env.sh

envDir=$prefixRoot/envs/$newEnvName
micromamba env create -n $newEnvName -r $prefixRoot
if [ $? -ne 0 ]; then
   echo "Failure in creating a new env under $envDir/"
fi

curDir=$PWD
cd $envDir
gtar xfz $CondaRoot/newEnv-base.tgz

cd bin/
cp -p $(echo /opt/conda/bin/python*.[0-9] | tail -1) ./
ln -s python*.[0-9] python3
ln -s python3 python

cd $curDir

micromamba activate $envDir
