# FROM opensciencegrid/osg-wn:3.6-release-el7 as osg-wn36
FROM centos:centos7

# bzip2 is needed in micromamba installation
#
RUN yum -y install which file git bzip2 \
    && yum -y clean all \
    && rm -rf /tmp/tmp* /tmp/yum.log /var/cache/yum/*

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

# make visible all executables in conda base env
ENV PATH=${prefix}/bin:${PATH}

# install python39
#
#
RUN micromamba install -c conda-forge -y python=3.9.14 \
    && micromamba clean -y -a -f

# install osg-wn-client
#
ARG OSG_REL=3.6
RUN yum -y install https://repo.opensciencegrid.org/osg/${OSG_REL}/osg-${OSG_REL}-el7-release-latest.rpm \
    epel-release \
    && yum -y install osg-wn-client \
    && yum -y remove "python3*" "xrootd*" "gfal2*" \
       wget stashcp epel-release \
    && yum -y clean all \
    && rm -rf /tmp/tmp* /tmp/yum.log /var/cache/yum/*

# install the latest ROOT (PyROOT is included)
#
RUN micromamba install -c conda-forge -y ROOT \
    && micromamba clean -y -a -f

# install libGL (needed un PyROOT) via system package manager
# which is a known issue witn conda: https://github.com/conda-forge/pygridgen-feedstock/issues/10
#
RUN yum install -y libGL \
    && yum -y clean all \
    && rm -rf /tmp/tmp* /tmp/yum.log /var/cache/yum/*

# install pipenv (python package/virtualenv manager)
#         and resample==1.5.3 (needed in scikit-hep
RUN micromamba install -c conda-forge -y pipenv resample==1.5.3 \
    && micromamba clean -y -a -f

# install scikit-hep, pyAMI, and Rucio
RUN pip install scikit-hep panda-client rucio-clients-atlas pyAMI_atlas \
    && rm -rf /root/.cache

# print out the package list into file /list-of-pkgs-inside.txt
#
RUN micromamba list |sed '1,2d' \
                    |tr -s ' ' |cut -d ' ' --fields=2,3 > /tmp/a.txt \
    && yum list installed |sed '1,2d' \
                    |tr -s ' ' |cut -d ' ' --fields=1,2 >> /tmp/a.txt \
    && pip list |sed '1,2d' \
                    |tr -s ' ' |cut -d ' ' --fields=1,2 >> /tmp/a.txt \
    && awk 'NR<3{print $0;next}{print $0| "sort -u"}' /tmp/a.txt \
                    > /list-of-pkgs-inside.txt \
    && rm -f /tmp/a.txt

# Remove *all* writable package caches
# RUN micromamba clean -y -a -f

# set PATH and LD_LIBRARY_PATH for the container
#
# ENV PATH=${prefix}/bin:${PATH} \
ENV LD_LIBRARY_PATH=/usr/lib64 \
    PANDA_SYS=$prefix \
    RUCIO_HOME=$prefix

# Demonstrate the environment is set up
#
RUN echo "Make sure PyROOT/Panda/Rucio are installed:" \
    && python --version \
    && python -c "import ROOT; import rucio.client; import pandaclient"

# creat/gtar a temporary new env
COPY ./gtar-newEnv-on-base.sh /tmp/
RUN  chmod +x /tmp/gtar-newEnv-on-base.sh \
     && /tmp/gtar-newEnv-on-base.sh \
     && rm -rf /tmp/*

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
