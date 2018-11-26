FROM ubuntu:16.04
MAINTAINER Andre Aliaman

RUN apt-get update
RUN export DEBIAN_FRONTEND=noninteractive && apt-get -y --no-install-recommends install software-properties-common language-pack-en-base
RUN apt-get update && apt-get -y upgrade && DEBIAN_FRONTEND=noninteractive apt-get install openvpn easy-rsa expect && apt-get -y autoremove

# Load config
COPY interfaces.sh /
RUN /interfaces.sh
COPY config.sh /
RUN /config.sh
COPY openvpn.sh /
RUN /openvpn.sh
