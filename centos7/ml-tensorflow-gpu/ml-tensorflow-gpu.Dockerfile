FROM centos:centos7

# bzip2 is needed in micromamba installation
#
RUN yum -y install which file git bzip2 \
    && yum -y clean all \
    && cd /tmp && rm -f tmp* yum.log

# path prefix for micromamba to install pkgs into
#
ARG TF_ver=2.10
ARG Conda_ver=11.2
ARG Prefix=/opt/conda
ARG Micromamba_ver=1.3.0
ARG Mamba_exefile=bin/micromamba
ENV MAMBA_EXE=/$Mamba_exefile MAMBA_ROOT_PREFIX=$Prefix CONDA_PREFIX=$Prefix

# Install micromamba
#
COPY _activate_current_env.sh /usr/local/bin/
RUN curl -L https://micromamba.snakepit.net/api/micromamba/linux-64/$Micromamba_ver | \
    tar -xj -C / $Mamba_exefile \
    && mkdir -p $Prefix && chmod a+rx $Prefix \
    && echo "source /usr/local/bin/_activate_current_env.sh" >> ~/.bashrc

# install python38
#
# install uproot, pandas, scikit-learn,
#         seaborn, plotly_express
#
#  (numpy, scipy, akward, matplotlib and plotly will 
#   be installed as dependencies)
#
RUN micromamba install -c conda-forge -y python=3.8 \
    uproot pandas scikit-learn seaborn plotly_express \
    && micromamba clean -y -a -f

# install jupyterlab individually
# because installing jupyterlab with other pkgs would be stuck forever
#
RUN micromamba install -c conda-forge -y jupyterlab \
    && micromamba clean -y -a -f

# install Gradient Boosting pkgs: lightgbm xgboost catboost
RUN micromamba install -c conda-forge -y lightgbm xgboost catboost \
    && micromamba clean -y -a -f

# install tensorflow and cuda dependency cudatoolkit
# (The installation without CONDA_OVERRIDE_CUDA would fail with error msg
#      nothing provides __cuda needed by ...)
# 
RUN export CONDA_OVERRIDE_CUDA=$Conda_ver \
    && micromamba install -c conda-forge -y tensorflow-gpu=$TF_ver \
    && micromamba clean -y -a -f

# get the command lspci to enable gpu checking in shell
#
RUN yum -y install pciutils \
    && yum -y clean all

# some users may use tcsh in jupyter terminal
#
RUN micromamba install -c conda-forge -y tcsh \
    && ln -s $Prefix/bin/tcsh /bin/tcsh \
    && micromamba clean -y -a -f

# print out the package list into file /list-of-pkgs-inside.txt
#
RUN micromamba list |sed '1,2d' |tr -s ' ' |cut -d ' ' --fields=2,3 > /list-of-pkgs-inside.txt \
    && yum list installed | egrep "^(which|file|git|bzip2)\." | tr -s ' ' |cut -d ' ' --fields=1,2 >> /list-of-pkgs-inside.txt

# set PATH and LD_LIBRARY_PATH for the container
#
ENV PATH=${Prefix}/bin:${PATH} \
    LD_LIBRARY_PATH=/usr/lib64

# Demonstrate the environment is set up
#
RUN echo "Make sure tensorflow is installed:" \
    && python --version \
    && python -c "import tensorflow as tf; print(tf.__version__)"

# creat/gtar a temporary new env
COPY ./gtar-newEnv-on-base.sh /tmp/
RUN  chmod +x /tmp/gtar-newEnv-on-base.sh \
     && /tmp/gtar-newEnv-on-base.sh \
     && rm -f /tmp/gtar-newEnv-on-base.sh

# copy setup script and readme file
#
COPY ./setup-on-host.sh ./check-gpu-in-tensorflow.py ./create-newEnv-on-base.sh /
COPY ./printme-gpu.sh /etc/profile.d/printme.sh

# Singularity
RUN mkdir -p /.singularity.d/env \
    && cp /etc/profile.d/printme.sh /.singularity.d/env/99-printme.sh

COPY entrypoint.sh /entrypoint.sh
RUN chmod 755 /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/bash"]
