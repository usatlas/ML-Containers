FROM centos:centos7

# bzip2 is needed in micromamba installation
#
RUN yum -y install which file bzip2 \
    && yum -y clean all \
    && cd /tmp && rm -f tmp* yum.log

# path prefix for micromamba to install pkgs into
#
ARG prefix=/opt/conda_jupyter
ARG Micromamba_ver=1.3.0
ARG PyVer=3.8
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
#
RUN micromamba install -c conda-forge -y python=$PyVer \
    && cd $prefix && ln -s bin condabin \
    && micromamba clean -y -a -f

# install jupyterlab/jupyterhub individually
# because installing jupyterlab with other pkgs would be stuck forever
#
# Removed jupyterhub, because it conflicts the one at BNL
#
# And click, needed by jupyter-events
#
RUN micromamba install -c conda-forge -y \
               jupyterlab click\
    && cd $prefix/bin && sed -i "1,3 s%${PWD}/python.*%/usr/bin/env python3%" \
       $(file * | grep "script" | cut -d: -f1) \
    && cd $prefix \
    && sed -i 's#".*bin/python.*"#"python3"#' share/jupyter/kernels/python3/kernel.json \
    && cd $prefix/share/jupyter/kernels \
    && cp -pR python3 container-python3 \
    && rm -f container-python3/kernel.json \
    && micromamba clean -y -a -f

# install pipenv (python package/virtualenv manager)
# RUN micromamba install -c conda-forge -y pipenv \
#    && micromamba clean -y -a -f


# install htcondor and slurm
# moved them into the top site-specific containers
#
RUN micromamba install -c conda-forge -y htcondor slurm \
    && cd $prefix/bin && sed -i "1,3 s%${PWD}/python.*%/usr/bin/env python3%" \
       $(file * | grep "script" | cut -d: -f1) \
    && micromamba clean -y -a -f

# install singularity
#   to allow running another inner container
RUN micromamba install -c conda-forge -y singularity \
    && micromamba clean -y -a -f

# print out the package list into file /list-of-pkgs-inside.txt
#
RUN micromamba list |sed '1,2d' |tr -s ' ' |cut -d ' ' --fields=2,3 > /tmp/a.txt \
    && yum list installed | egrep "^(which|file|git|bzip2)\." | \
       tr -s ' ' |cut -d ' ' --fields=1,2 >> /tmp/a.txt \
    && awk 'NR<3{print $0;next}{print $0| "sort -u"}' /tmp/a.txt > /list-of-pkgs-inside.txt \
    && rm -rf /tmp/*

# set PATH and LD_LIBRARY_PATH for the container
#
ENV PATH=${prefix}/bin:${PATH} \
    LD_LIBRARY_PATH=/usr/lib64 \
    JUPYTERLAB_DIR=${prefix}/share/jupyter/lab \
    JUPYTER_PATH=${prefix}/share/jupyter \
    SHELL=/bin/bash

    PYTHONPATH=$prefix/lib/python${PyVer}/site-packages \


# copy the special Jupyter kernel
COPY ./container-kernel.json $prefix/share/jupyter/kernels/container-python3/kernel.json
COPY ./singularity-jupyter.sh $prefix/bin/
RUN chmod 755 $prefix/bin/singularity-jupyter.sh

# copy setup script and readme file
#
# COPY ./setup-on-host.sh ./create-newEnv-on-base.sh /
COPY ./printme-af.sh /etc/profile.d/printme.sh

# Singularity
RUN mkdir -p /.singularity.d/env \
    && cp /etc/profile.d/printme.sh /.singularity.d/env/99-printme.sh

COPY entrypoint.sh /entrypoint.sh
RUN chmod 755 /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/bash"]
