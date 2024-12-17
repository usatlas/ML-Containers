CondaRoot=/opt/conda

redCol="\e[1;31;47m"
PROGNAME=$BASH_SOURCE
usage()
{
  cat << EO
        Create a new python env on top of the existing base env

        Usage: source $PROGNAME -h|--help
               source $PROGNAME [-w|--workdir workDir]

	If no workDir is specified, the current directory will be used.
EO
}

if [ $BASH_SOURCE == $0 ]; then
   echo -e "DO NOT run this script, please ${redCol} source $PROGNAME \e[0m instead\n"
   usage
   exit 1
fi

workDir=""
while (( "$#" )); do
  case "$1" in
    -h|--help)
      usage
      return 0
      ;;
    -w|--workdir)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        workDir=$2
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

isPWD=no
if [ "$workDir" == "" ]; then
   workDir=$PWD
   isPWD=yes
fi

if [ "$isPWD" == "no" -a ! -d $workDir ]; then
   mkdir -p $workDir
   if [ $? -ne 0 ]; then
      echo "$workDir does not exist, cannot create it either; exit now"
      return 1
   fi
fi

export PIPENV_VENV_IN_PROJECT=1

# [[ $(type -t micromamba) != "function" ]] && source /usr/local/bin/_activate_current_env.sh

if [ "$isPWD" == "no" ]; then
   cd $workDir
fi

pipenv --site-packages install
# sed -i  '/^VIRTUAL_ENV=/s#=.*#=$(realpath ${BASH_SOURCE%/*/*})#' .venv/bin/activate
sed -i  '/^VIRTUAL_ENV=/s#=.*#=$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" \&>/dev/null \&\& pwd)#' .venv/bin/activate

ln -s $CONDA_PREFIX/lib/*.so* .venv/lib/

echo ""
echo -e "To add a package, run ${redCol}pipenv install\e[0m"
echo -e "To activate this project's virtualenv, run ${redCol}pipenv shell\e[0m"
echo -e "Alternatively, run a command inside the virtualenv with ${redCol}pipenv run\e[0m"
