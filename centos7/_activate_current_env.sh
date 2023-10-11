# This script should never be called directly, only sourced:

#     source _activate_current_env.sh

# shellcheck shell=bash

# Initialize Micromamba for the current shell

# if [[ "X$X_MAMBA" == "X" ]]; then
   eval "$("${MAMBA_EXE}" shell hook --shell=bash)"
   micromamba activate "${ENV_NAME:-base}"
#   export X_MAMBA=$CONDA_DEFAULT_ENV
   # export CONDA_PROMPT_MODIFIER="(${ENV_NAME:-base})"
# fi
