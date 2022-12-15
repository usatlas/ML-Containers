FROM centos:centos7

# bzip2 is needed in micromamba installation
#
RUN yum -y install which file git bzip2

# Install micromamba
#
RUN curl micro.mamba.pm/install.sh | bash \
    && source ~/.bashrc

# ensure the ~/.bashrc is sourced in the remaining Dockerfile lines
#
SHELL ["/bin/bash", "--login", "-c"]

# path prefix for micromamba to install pkgs into
#
ARG prefix=/root/micromamba

# install python38
#
# make /root accessible in Singularity
#
RUN chmod og+rx /root \
    && micromamba install -c conda-forge -y -p $prefix python=3.8 \
    && micromamba clean -y -a

# install jupyterlab, uproot, pandas, scikit-learn,
#         seaborn, plotly_express
#
#  (numpy, scipy, akward, matplotlib and plotly will 
#   be installed as dependencies)
#
RUN micromamba install -c conda-forge -y -p $prefix \
    jupyterlab uproot pandas scikit-learn seaborn plotly_express \
    && micromamba clean -y -a

# install the latest ROOT (PyROOT is included)
#
RUN micromamba install -c conda-forge -y -p $prefix ROOT \
    && micromamba clean -y -a

# some users may use tcsh in jupyter terminal
#
RUN yum -y install tcsh

# print out the package list into file /00Readme.txt
#
RUN micromamba activate \
    && micromamba list |sed '1,2d' |tr -s ' ' |cut -d ' ' --fields=2,3 > /00Readme.txt \
    && yum list installed | egrep "^(which|file|git|bzip2)\." | tr -s ' ' |cut -d ' ' --fields=1,2 >> /00Readme.txt

SHELL ["/bin/bash", "-c"]

# cleanup
RUN yum -y clean all \
    && cd /tmp && rm -f tmp* yum.log

# set PATH and LD_LIBRARY_PATH for the container
#
ENV PATH=${prefix}/bin:/usr/local/bin:/usr/bin \
    LD_LIBRARY_PATH=${prefix}/lib:/usr/lib64

# Demonstrate the environment is set up
#
RUN echo "Make sure PyROOT is installed:" \
    && python --version \
    && python -c "import ROOT; print(ROOT.gROOT.GetVersion())"

# copy setup script and readme file
#
COPY ./setup-on-host.sh /
COPY ./printme.sh ./printme.csh /etc/profile.d/

CMD ["/bin/bash"]