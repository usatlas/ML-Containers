FROM centos:centos7 as centos7
# FROM mambaorg/micromamba:latest as micromamba

FROM almalinux:9

# bzip2 is needed in micromamba installation
#
RUN yum -y install which file git bzip2 \
    && yum -y clean all \
    && cd /tmp && rm -f tmp* yum.log

# path prefix for micromamba to install pkgs into
#
ARG prefix=/opt/conda
ARG Micromamba_ver=1.5.7
ARG PyVer=3.9
ARG Mamba_exefile=bin/micromamba
ENV MAMBA_EXE=/$Mamba_exefile MAMBA_ROOT_PREFIX=$prefix CONDA_PREFIX=$prefix

# Install micromamba
#
COPY _activate_current_env.sh /usr/local/bin/
RUN curl -L https://micromamba.snakepit.net/api/micromamba/linux-64/$Micromamba_ver | \
    tar -xj -C / $Mamba_exefile \
    && mkdir -p $prefix/bin && chmod a+rx $prefix \
    && ln $MAMBA_EXE $prefix/bin/ \
    && micromamba config append --system channels conda-forge \
    && echo "source /usr/local/bin/_activate_current_env.sh" >> ~/.bashrc

# install python3, pipenv
#
# install uproot, pandas, scikit-learn,
#         seaborn, plotly_express
#
#  (numpy, scipy, akward, matplotlib and plotly will 
#   be installed as dependencies)
#
COPY python3-nohome $prefix/bin/
RUN micromamba install -y python=$PyVer pipenv \
    uproot pandas scikit-learn seaborn plotly_express scikit-hep=5.1.1 \
    && cd $prefix/bin && chmod +x python3-nohome \
    && sed -i "1,3 s%${PWD}/python%/usr/bin/env python%" \
       $(file * | grep "script" | cut -d: -f1) \
    && micromamba clean -y -a -f

# install jupyterlab individually
# because installing jupyterlab with other pkgs would be stuck forever
#
# click, pyrsistent and rich, needed by jupyter-events
#
COPY shellWrapper-for-python3-I.sh shellWrapper-for-python3-nohome.sh /tmp/
RUN micromamba install -y jupyterlab jupyterhub click pyrsistent rich \
    && cd $prefix/bin \
    && sed -i -e '1r/tmp/shellWrapper-for-python3-I.sh' -e '0,/coding:/d' jupyter* \
    && sed -i -e '1r/tmp/shellWrapper-for-python3-nohome.sh' -e '0,/coding:/d' ipython \
    && ln -s ipython ipython-nohome \
    && rm -f /tmp/shellWrapper-for-python3-I.sh /tmp/shellWrapper-for-python3-nohome.sh \
    && sed -i "1,3 s%${PWD}/python%/usr/bin/env python%" \
       $(file * | grep "script" | cut -d: -f1) \
    && cd $prefix/share/jupyter/kernels \
    && cp -pR python3 python3-usersite \
    && sed -i -e 's%: ".*(ipykernel)"%: "ML-Python3"%' \
              -e 's#".*bin/python.*"#"python3-nohome", "-s"#' python3/kernel.json \
    && sed -i -e 's%: ".*(ipykernel)"%: "ML-Python3-usersite"%' \
              -e 's#".*bin/python.*"#"python3-nohome"#' python3-usersite/kernel.json \
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

# copy libssl.so.10 to make jupter-labhub from centos7-based host work
COPY --from=centos7  /lib64/libfreebl3.so /lib64/libcrypt.so.1 /lib64/libcrypto.so.10 \
     /lib64/libssl.so.10 /lib64/libtinfo.so.5 /lib64/libncursesw.so.5 /lib64/libffi.so.6 /lib64

# print out the package list into file /list-of-pkgs-inside.txt
#
RUN outfile=list-of-pkgs-inside.txt \
    && micromamba list |sed '1,4d' |tr -s ' ' |cut -d ' ' --fields=2,3 > /tmp/$outfile \
    && $prefix/bin/python3 -m pip list |sed '1,2d' |tr -s ' ' |cut -d ' ' --fields=1,2 >> /tmp/$outfile \
    && yum list installed | egrep "^(which|file|git|bzip2)\." | \
       tr -s ' ' |cut -d ' ' --fields=1,2 >> /tmp/$outfile \
    && echo "micromamba $(micromamba --version)" >> /tmp/$outfile \
    && sort -f -u -k1 /tmp/$outfile >/$outfile \
    && rm -f /tmp/$outfile

# set PATH and LD_LIBRARY_PATH for the container
#
ENV PATH=${prefix}/bin:${PATH} \
    LD_LIBRARY_PATH=/usr/lib64 \
    JUPYTER_PATH=$prefix/share/jupyter \
    LC_ALL=C.UTF-8 \
    LANG=C.UTF-8

# Demonstrate the environment is set up
#
RUN echo "Make sure numpy is installed:" \
    && python --version \
    && python -c "import numpy as np; print(np.__version__)"

# creat/gtar a temporary new env
COPY gtar-newEnv-on-base.sh /tmp/
RUN  chmod +x /tmp/gtar-newEnv-on-base.sh \
     && /tmp/gtar-newEnv-on-base.sh \
     && rm -f /tmp/gtar-newEnv-on-base.sh

# copy setup script and readme file
#
COPY setupMe-on-host.sh create-newEnv-on-base.sh setup-UserEnv-in-container.sh create-py_newEnv-on-base.sh /
COPY printme.sh /printme.sh
RUN cp printme.sh /etc/profile.d/
# RUN echo "source /printme.sh" >> ~/.bashrc

# Singularity
RUN mkdir -p /.singularity.d/env \
    && cp /printme.sh /.singularity.d/env/99-printme.sh

COPY entrypoint.sh /
RUN chmod 755 /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/bash"]

# Labels for the image version/rawSize
ARG imageVersion=""
ARG imageRawSize=""
LABEL imageVersion=$imageVersion
LABEL imageRawSize=$imageRawSize
