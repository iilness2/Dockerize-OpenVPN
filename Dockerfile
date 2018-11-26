FROM ubuntu:16.04
MAINTAINER Andre Aliaman

RUN export DEBIAN_FRONTEND=noninteractive && apt-get -y --no-install-recommends install software-properties-common
RUN apt-get update && apt-get -y upgrade && apt-get install openvpn easy-rsa expect && apt-get -y autoremove
ENV LC_ALL en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8 

# Load config
COPY interfaces.sh /
RUN /interfaces.sh
COPY config.sh /
RUN /config.sh
COPY openvpn.sh /
RUN /openvpn.sh
