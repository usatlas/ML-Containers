FROM centos:centos7

# bzip2 is needed in micromamba installation
#
RUN yum -y install which file git bzip2 \
    && yum -y clean all \
    && cd /tmp && rm -f tmp* yum.log

# path prefix for micromamba to install pkgs into
#
ARG prefix=/opt/conda
ARG Micromamba_ver=1.4.3
ARG PyVer=3.9
ARG Mamba_exefile=bin/micromamba
ENV MAMBA_EXE=/$Mamba_exefile MAMBA_ROOT_PREFIX=$prefix CONDA_PREFIX=$prefix

# Install micromamba
#
COPY _activate_current_env.sh /usr/local/bin/
RUN curl -L https://micromamba.snakepit.net/api/micromamba/linux-64/$Micromamba_ver | \
    tar -xj -C / $Mamba_exefile \
    && mkdir -p $prefix && chmod a+rx $prefix \
    && micromamba config append --system channels conda-forge \
    && echo "source /usr/local/bin/_activate_current_env.sh" >> ~/.bashrc

# install python38, pipenv
#
# install uproot, pandas, scikit-learn,
#         seaborn, plotly_express
#
#  (numpy, scipy, akward, matplotlib and plotly will 
#   be installed as dependencies)
#
RUN micromamba install -y python=$PyVer pipenv \
    uproot pandas scikit-learn seaborn plotly_express \
    && cd $prefix/bin && sed -i "1,3 s%${PWD}/python%/usr/bin/env python%" \
       $(file * | grep "script" | cut -d: -f1) \
    && micromamba clean -y -a -f

# install jupyterlab individually
# because installing jupyterlab with other pkgs would be stuck forever
#
# And click, needed by jupyter-events
#
RUN micromamba install -y jupyterlab click \
    && cd $prefix \
    && sed -i "1,3 s%${PWD}/python%/usr/bin/env python%" \
       $(file bin/* | grep "script" | cut -d: -f1) \
    && cd $prefix/share/jupyter/kernels \
    && sed -i -e 's%: ".*(ipykernel)"%: "ML-Python3"%' \
              -e 's#".*bin/python.*"#"/usr/bin/env", "python'${PyVer}'", "-I"#' python3/kernel.json \
    && micromamba clean -y -a -f

# install Gradient Boosting pkgs: lightgbm xgboost catboost
RUN micromamba install -y lightgbm xgboost catboost \
    && cd $prefix/bin && sed -i "1,3 s%${PWD}/python%/usr/bin/env python%" \
       $(file * | grep "script" | cut -d: -f1) \
    && micromamba clean -y -a -f

# install two other common shells: zsh and tcsh, to allow Jupyter terminal work
RUN micromamba install -y zsh tcsh \
    && ln -s $prefix/bin/zsh /bin/zsh \
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
    LD_LIBRARY_PATH=/usr/lib64 \
    JUPYTER_PATH=$prefix/share/jupyter

#    SHELL=/bin/bash


# Demonstrate the environment is set up
#
RUN echo "Make sure numpy is installed:" \
    && python --version \
    && python -c "import numpy as np; print(np.__version__)"

# creat/gtar a temporary new env
COPY ./gtar-newEnv-on-base.sh /tmp/
RUN  chmod +x /tmp/gtar-newEnv-on-base.sh \
     && /tmp/gtar-newEnv-on-base.sh \
     && rm -f /tmp/gtar-newEnv-on-base.sh

# copy setup script and readme file
#
COPY ./setupMe-on-host.sh ./create-newEnv-on-base.sh ./create-py_newEnv-on-base.sh /
COPY ./printme.sh /etc/profile.d/

# Singularity
RUN mkdir -p /.singularity.d/env \
    && cp /etc/profile.d/printme.sh /.singularity.d/env/99-printme.sh

COPY entrypoint.sh /
RUN chmod 755 /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/bash"]
