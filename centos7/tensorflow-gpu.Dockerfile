FROM centos:centos7

# bzip2 is needed in micromamba installation
#
RUN yum -y install which file git bzip2 \
    && yum -y clean all

# path prefix for micromamba to install pkgs into
#
ARG TF_ver=2.10 Conda_ver=11.2 
ARG Prefix=/opt/conda Micromamba_ver=1.1.0 Mamba_Exefile=bin/micromamba
ENV MAMBA_EXE=/$Mamba_Exefile MAMBA_ROOT_PREFIX=$Prefix

# Install micromamba
#
COPY _activate_current_env.sh /usr/local/bin/
RUN curl -L https://micromamba.snakepit.net/api/micromamba/linux-64/$Micromamba_ver | \
    tar -xj -C / $Mamba_Exefile \
    && mkdir -p $Prefix && chmod a+rx $Prefix \
    && echo "source /usr/local/bin/_activate_current_env.sh" >> ~/.bashrc

# ensure the ~/.bashrc is sourced in the remaining Dockerfile lines
#
SHELL ["/bin/bash", "--login", "-c"]

# install python38
#
# install jupyterlab, uproot, pandas, scikit-learn,
#         seaborn, plotly_express
#
#  (numpy, scipy, akward, matplotlib and plotly will 
#   be installed as dependencies)
#
RUN micromamba install -c conda-forge -y python=3.8 \
    jupyterlab uproot pandas scikit-learn seaborn plotly_express \
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
# cleanup
#
RUN yum -y install tcsh \
    && yum -y clean all \
    && cd /tmp && rm -f tmp* yum.log

# print out the package list into file /list-of-pkgs-inside.txt
#
RUN micromamba list |sed '1,2d' |tr -s ' ' |cut -d ' ' --fields=2,3 > /list-of-pkgs-inside.txt \
    && yum list installed | egrep "^(which|file|git|bzip2)\." | tr -s ' ' |cut -d ' ' --fields=1,2 >> /list-of-pkgs-inside.txt

# Demonstrate the environment is set up
#
RUN echo "Make sure tensorflow is installed:" \
    && python --version \
    && python -c "import tensorflow as tf; print(tf.__version__)"

SHELL ["/bin/bash", "-c"]

# set PATH and LD_LIBRARY_PATH for the container
#
# ENV PATH=${Prefix}/bin:/usr/local/bin:/usr/bin:/usr/local/nvidia/bin \
#    LD_LIBRARY_PATH=${Prefix}/lib:/usr/local/nvidia/lib64:/usr/lib64
ENV LD_LIBRARY_PATH=/usr/local/nvidia/lib64:/usr/local/cuda/lib64:/usr/lib64

# copy setup script and readme file
#
COPY ./setup-on-host.sh check-gpu-in-tensorflow.py /
COPY ./printme-gpu.sh /etc/profile.d/printme.sh

COPY entrypoint.sh /entrypoint.sh
RUN chmod 755 /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/bash"]
