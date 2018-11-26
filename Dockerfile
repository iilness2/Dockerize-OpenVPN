FROM ubuntu:16.04
MAINTAINER Andre Aliaman

RUN apt-get update
RUN export DEBIAN_FRONTEND=noninteractive && apt-get -y --no-install-recommends install software-properties-common language-pack-en-base
RUN apt-get update && apt-get -y upgrade && apt-get -y autoremove
RUN DEBIAN_FRONTEND=noninteractive apt-get -y install openvpn easy-rsa expect

# Load config
COPY openvpn.sh /
RUN /openvpn.sh
