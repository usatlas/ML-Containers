FROM centos:centos7

# bzip2 is needed in micromamba installation
#
RUN yum -y install which file git bzip2 \
    && yum -y clean all

# path prefix for micromamba to install pkgs into
#
ARG TF_ver=2.10
ARG Prefix=/opt/conda Micromamba_ver=1.1.0 Mamba_exefile=bin/micromamba
ENV MAMBA_EXE=/$Mamba_exefile MAMBA_ROOT_PREFIX=$Prefix

# Install micromamba
#
COPY _activate_current_env.sh /usr/local/bin/
RUN curl -L https://micromamba.snakepit.net/api/micromamba/linux-64/$Micromamba_ver | \
    tar -xj -C / $Mamba_exefile \
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

# install tensorflow without GPU support
# 
RUN micromamba install -c conda-forge -y tensorflow=$TF_ver \
    && micromamba clean -y -a

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
ENV LD_LIBRARY_PATH=/usr/lib64

# copy setup script and readme file
#
COPY ./setup-on-host.sh test-tensorflow-with-cpu.py /
COPY ./printme.sh /etc/profile.d/

COPY entrypoint.sh /entrypoint.sh
RUN chmod 755 /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/bash"]
