ARG BASE_IMAGE=alpine:latest
FROM $BASE_IMAGE

LABEL maintainer Ilija Vukotic <ivukotic@cern.ch>

RUN echo "$BASE_IMAGE > TF"
