ARG BASE_IMAGE=alpine:latest
ARG BASE=centos7

FROM $BASE_IMAGE

LABEL maintainer Ilija Vukotic <ivukotic@cern.ch>

# add shim
COPY uc_shim.sh /user/local/sbin/

# add condor libs
RUN RUN LD_LIBRARY_PATH= && if [ "$BASE" = "centos7" ]; then \
       yum -y install https://research.cs.wisc.edu/htcondor/repo/current/htcondor-release-current.el7.noarch.rpm \
       && yum -y install htcondor; \
    else \
       apt-add-repository deb [arch=amd64] http://research.cs.wisc.edu/htcondor/repo/ubuntu/current focal main; \
    fi 

RUN echo "$BASE_IMAGE > UC"