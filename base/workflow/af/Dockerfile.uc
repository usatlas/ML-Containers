ARG BASE_IMAGE=alpine:latest
ARG BASE=centos7

FROM $BASE_IMAGE

LABEL maintainer Ilija Vukotic <ivukotic@cern.ch>

# add shim
COPY uc_shim.sh /user/local/sbin/

# add condor libs
RUN if [ "$BASE" = "centos7" ]; then \
       yum install https://research.cs.wisc.edu/htcondor/repo/current/htcondor-release-current.el7.noarch.rpm -y \
       && yum install htcondor; \
    else \
       apt-add-repository deb [arch=amd64] http://research.cs.wisc.edu/htcondor/repo/ubuntu/current focal main; \
    fi 

RUN echo "$BASE_IMAGE > UC"