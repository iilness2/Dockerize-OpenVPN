FROM ubuntu:16.04
MAINTAINER Andre Aliaman

RUN apt-get update
RUN export DEBIAN_FRONTEND=noninteractive && apt-get -y --no-install-recommends install software-properties-common language-pack-en-base
RUN apt-get update && apt-get -y upgrade && apt-get -y autoremove
RUN { \
        echo mysql-community-server mysql-community-server/data-dir select ''; \
        echo mysql-community-server mysql-community-server/root-pass password 'root'; \
        echo mysql-community-server mysql-community-server/re-root-pass password 'root'; \
        echo mysql-community-server mysql-community-server/remove-test-db select false; \
    } | debconf-set-selections
RUN DEBIAN_FRONTEND=noninteractive apt-get -y install openvpn easy-rsa expect nginx php7.0-mysql mysql-server php7.0-fpm nodejs unzip git wget sed npm curl

# Load config
COPY nginx-www.conf /etc/nginx/sites-available/default
COPY bower.json /
ADD css /	
ADD include /
COPY index.php /
ADD installation /
ADD js /
COPY migration.php /
ADD sql /
COPY installovpn.sh /
RUN /installovpn.sh
