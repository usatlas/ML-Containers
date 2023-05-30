FROM centos:centos7

# bzip2 is needed in micromamba installation
#
RUN yum -y install which file git bzip2 \
    && yum -y clean all \
    && cd /tmp && rm -f tmp* yum.log

# path prefix for micromamba to install pkgs into
#
ARG prefix=/opt/conda
ARG Micromamba_ver=1.3.0
ARG Mamba_exefile=bin/micromamba
ENV MAMBA_EXE=/$Mamba_exefile MAMBA_ROOT_PREFIX=$prefix CONDA_PREFIX=$prefix

# Install micromamba
#
COPY _activate_current_env.sh /usr/local/bin/
RUN curl -L https://micromamba.snakepit.net/api/micromamba/linux-64/$Micromamba_ver | \
    tar -xj -C / $Mamba_exefile \
    && mkdir -p $prefix && chmod a+rx $prefix \
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

# install the latest ROOT (PyROOT is included)
#
RUN micromamba install -c conda-forge -y ROOT \
    && micromamba clean -y -a -f

# install libGL (needed un PyROOT) via system package manager
# which is a known issue witn conda: https://github.com/conda-forge/pygridgen-feedstock/issues/10
#
RUN yum install -y libGL \
    && yum -y clean all \
    && cd /tmp && rm -f tmp* yum.log

# some users may use tcsh in jupyter terminal
#
RUN micromamba install -c conda-forge -y tcsh \
    && ln -s $prefix/bin/tcsh /bin/tcsh \
    && micromamba clean -y -a -f

# print out the package list into file /list-of-pkgs-inside.txt
#
RUN micromamba list |sed '1,2d' |tr -s ' ' |cut -d ' ' --fields=2,3 > /list-of-pkgs-inside.txt \
    && yum list installed | egrep "^(which|file|git|bzip2)\." | \
       tr -s ' ' |cut -d ' ' --fields=1,2 >> /list-of-pkgs-inside.txt

# Remove *all* writable package caches
# RUN micromamba clean -y -a -f

# set PATH and LD_LIBRARY_PATH for the container
#
ENV PATH=${prefix}/bin:${PATH} \
    LD_LIBRARY_PATH=/usr/lib64

# Demonstrate the environment is set up
#
RUN echo "Make sure PyROOT is installed:" \
    && python --version \
    && python -c "import ROOT; print(ROOT.gROOT.GetVersion())"

# creat/gtar a temporary new env
COPY ./gtar-newEnv-on-base.sh /tmp/
RUN  chmod +x /tmp/gtar-newEnv-on-base.sh \
     && /tmp/gtar-newEnv-on-base.sh \
     && rm -f /tmp/gtar-newEnv-on-base.sh

# copy setup script and readme file
#
COPY ./setup-on-host.sh ./create-newEnv-on-base.sh /
COPY ./printme.sh /etc/profile.d/

# Singularity
RUN mkdir -p /.singularity.d/env \
    && cp /etc/profile.d/printme.sh /.singularity.d/env/99-printme.sh

COPY entrypoint.sh /entrypoint.sh
RUN chmod 755 /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/bash"]
