PROGNAME=$BASH_SOURCE
myName="${BASH_SOURCE:-$0}"
myDir=$(dirname $myName)
myDir=$(readlink -f $myDir)

usage()
{
  cat << EO
        Create a new env on top of the existing base env

        Usage: source $PROGNAME -h|--help
               source $PROGNAME -p|--prefix prefixDir
EO
}

if [ "$BASH_SOURCE" = "$0" ]; then
   echo "DO NOT run this script, please _source_  $PROGNAME instead"
   usage
   return 1
fi

while [ $# -gt 0 ]
do
  case "$1" in
    -h|--help)
      usage
      return 0
      ;;
    -p|--prefix)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        prefixDir=$2
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


CondaRoot=$MAMBA_ROOT_PREFIX
[ "X$CondaRoot" = "X" ] && CondaRoot=$CONDA_PREFIX
if [ "X$CondaRoot" = "X" ]; then
   echo "Neither envvar MAMBA_ROOT_PREFIX nor CONDA_PREFIX is found, exit now"
   return 1
fi

if [ "$prefixDir" = "" ]; then
   echo "missing prefixDir"
   usage
   return 1
fi

if [[ "$prefixDir" != */* ]]; then
   prefixDir="./$prefixDir"
fi


shellName=$(readlink /proc/$$/exe | awk -F "[/-]" '{print $NF}')
typeset -f micromamba >/dev/null || eval "$($MAMBA_EXE shell hook --shell=$shellName)"

envDir=$prefixDir
micromamba env create -p $prefixDir
if [ $? -ne 0 ]; then
   echo "Failure in creating a new env under $envDir/"
fi
envDir=$(readlink -f $envDir)


curDir=$PWD
cd $envDir
ln -s $CONDA_PREFIX baseEnv_dir
gtar xfz $CondaRoot/newEnv-base.tgz


cat > pyvenv.cfg <<EOF
home = $CONDA_PREFIX/bin
include-system-site-packages = true
version = $(python3 --version | cut -d' ' -f2)
EOF

prepare_UserEnv_setup()
{
   if [ "$myDir" = "/" ]; then
      cp -p /setup-UserEnv-in-container.sh .
      BindPaths='$myDir'
      if [ "X$SINGULARITY_BIND" != "X" ]; then
         BindPaths="$SINGULARITY_BIND"',$myDir'
      fi
      Image=$SINGULARITY_CONTAINER
      sed -i -e "s#BindPaths=.*#BindPaths=$BindPaths#" -e "s#Image=.*#Image=$Image#" setup-UserEnv-in-container.sh
   else
      cp -p $myDir/setupMe-on-host.sh .
      # add the default channel: conda-forge
      micromamba config get channels 2>&1 | grep conda-forge >/dev/null || micromamba config append channels conda-forge
   fi
}

prepare_UserEnv_setup

cd $curDir

# activate the new new
micromamba activate $envDir
echo "Next time, you can just run the following to activate your extended env"
if [ "$myDir" = "/" ]; then
   echo -e "\tsource $envDir/setup-UserEnv-in-container.sh"
else
   echo -e "\tsource $envDir/setupMe-on-host.sh"
fi
