FROM ubuntu:16.04
MAINTAINER Andre Aliaman

RUN apt-get update
RUN export DEBIAN_FRONTEND=noninteractive && apt-get -y --no-install-recommends install software-properties-common language-pack-en-base
RUN apt-get update
RUN apt-get -y upgrade
RUN apt-get -y autoremove

RUN sd=`dirname $0`
RUN cd $sd
RUN sd=`pwd`

# Load config
RUN source config.sh
RUN source interfaces.sh

# Install OpenVPN and expect
RUN apt-get -y install openvpn easy-rsa expect

# Set up the CA directory
RUN make-cadir ~/openvpn-ca
RUN cd ~/openvpn-ca

# Update vars
RUN sed -i "s/export KEY_COUNTRY=\"[^\"]*\"/export KEY_COUNTRY=\"${KEY_COUNTRY}\"/" vars
RUN sed -i "s/export KEY_PROVINCE=\"[^\"]*\"/export KEY_PROVINCE=\"${KEY_PROVINCE}\"/" vars
RUN sed -i "s/export KEY_CITY=\"[^\"]*\"/export KEY_CITY=\"${KEY_CITY}\"/" vars
RUN sed -i "s/export KEY_ORG=\"[^\"]*\"/export KEY_ORG=\"${KEY_ORG}\"/" vars
RUN sed -i "s/export KEY_EMAIL=\"[^\"]*\"/export KEY_EMAIL=\"${KEY_EMAIL}\"/" vars
RUN sed -i "s/export KEY_OU=\"[^\"]*\"/export KEY_OU=\"${KEY_OU}\"/" vars
RUN sed -i "s/export KEY_NAME=\"[^\"]*\"/export KEY_NAME=\"server\"/" vars

# Build the Certificate Authority
RUN source vars
RUN ./clean-all
RUN yes "" | ./build-ca

# Create the server certificate, key, and encryption files
RUN $sd/build-key-server.sh
RUN ./build-dh
RUN openvpn --genkey --secret keys/ta.key

# Copy the files to the OpenVPN directory
RUN cd ~/openvpn-ca/keys
RUN cp ca.crt ca.key server.crt server.key ta.key dh2048.pem /etc/openvpn
RUN gunzip -c /usr/share/doc/openvpn/examples/sample-config-files/server.conf.gz | sudo tee /etc/openvpn/server.conf

# Adjust the OpenVPN configuration
RUN sed -i "s/;tls-auth ta.key 0/tls-auth ta.key 0\nkey-direction 0/" /etc/openvpn/server.conf
RUN sed -i "s/;cipher AES-128-CBC/cipher AES-128-CBC\nauth SHA256/" /etc/openvpn/server.conf
RUN sed -i "s/;user nobody/user nobody/" /etc/openvpn/server.conf
RUN sed -i "s/;group nogroup/group nogroup/" /etc/openvpn/server.conf

# Allow IP forwarding
RUN sed -i "s/#net.ipv4.ip_forward/net.ipv4.ip_forward/" /etc/sysctl.conf
RUN sysctl -p

# Install iptables-persistent so that rules can persist across reboots
RUN echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
RUN echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
RUN apt-get install -y iptables-persistent

# Edit iptables rules to allow for forwarding
RUN iptables -t nat -A POSTROUTING -o tun+ -j MASQUERADE
RUN iptables -t nat -A POSTROUTING -o $VPNDEVICE -j MASQUERADE

# Make iptables rules persistent across reboots
RUN iptables-save > /etc/iptables/rules.v4
