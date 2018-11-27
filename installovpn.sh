#!/bin/bash

www=${WWW_DIR}

openvpn_admin="$www/openvpn-admin"

base_path=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

ip_server=${PUBLIC_IP}

openvpn_proto=${PROTOCOL_OPENVPN}
if [[ -z $openvpn_proto ]]; then
  openvpn_proto="tcp"
fi

server_port=${VPN_PORT}
if [[ -z $server_port ]]; then
  server_port="1194"
fi

mysql_root_pass=${MYSQL_ROOT_PASS}
if [[ -z $mysql_root_pass ]]; then
  mysql_root_pass="root"
fi

mysql_user=${MYSQL_USER}
if [[ -z $mysql_user ]]; then
  mysql_user="openvpnmysql"
fi

mysql_pass=${MYSQL_PASS}
if [[ -z $mysql_pass ]]; then
  mysql_pass="openvpnmysql"
fi

key_size=${KEY_SIZE}
if [[ -z $key_size]]; then
  key_size="2048"
fi

ca_expire=${CA_EXPIRE}
if [[ -z $ca_expire ]]; then
  ca_expire="3650"
fi

cert_expire=${CERT_EXPIRE}
if [[ -z $cert_expire ]]; then
  cert_expire="3650"
fi

cert_country=${CERT_COUNTRY}
if [[ -z $cert_country ]]; then
  cert_country="ID"
fi

cert_province=${CERT_PROVINCE}
if [[ -z $cert_province ]]; then
  cert_province="DKI"
fi

cert_city=${CERT_CITY}
if [[ -z $cert_city ]]; then
  cert_city="DKI"
fi

cert_org=${CERT_ORG}
if [[ -z $cert_org ]]; then
  cert_org="andre"
fi

cert_ou=${CERT_OU}
if [[ -z $cert_ou ]]; then
  cert_ou="aliaman"
fi

cert_email=${CERT_EMAIL}
if [[ -z $cert_email ]]; then
  cert_email="andre.aliaman90@gmail.com"
fi

key_cn=${KEY_CN}
if [[ -z $key_cn ]]; then
  key_cn="server"
fi

printf "\n################## Creating the certificates ##################\n"

EASYRSA_RELEASES=( $(
  curl -s https://api.github.com/repos/OpenVPN/easy-rsa/releases | \
  grep 'tag_name' | \
  grep -E '3(\.[0-9]+)+' | \
  awk '{ print $2 }' | \
  sed 's/[,|"|v]//g'
) )
EASYRSA_LATEST=${EASYRSA_RELEASES[0]}

# Get the rsa keys
wget -q https://github.com/OpenVPN/easy-rsa/releases/download/v${EASYRSA_LATEST}/EasyRSA-nix-${EASYRSA_LATEST}.tgz
tar -xaf EasyRSA-nix-${EASYRSA_LATEST}.tgz
mv EasyRSA-${EASYRSA_LATEST} /etc/openvpn/easy-rsa
rm -r EasyRSA-nix-${EASYRSA_LATEST}.tgz
cd /etc/openvpn/easy-rsa

if [[ ! -z $key_size ]]; then
  export EASYRSA_KEY_SIZE=$key_size
fi
if [[ ! -z $ca_expire ]]; then
  export EASYRSA_CA_EXPIRE=$ca_expire
fi
if [[ ! -z $cert_expire ]]; then
  export EASYRSA_CERT_EXPIRE=$cert_expire
fi
if [[ ! -z $cert_country ]]; then
  export EASYRSA_REQ_COUNTRY=$cert_country
fi
if [[ ! -z $cert_province ]]; then
  export EASYRSA_REQ_PROVINCE=$cert_province
fi
if [[ ! -z $cert_city ]]; then
  export EASYRSA_REQ_CITY=$cert_city
fi
if [[ ! -z $cert_org ]]; then
  export EASYRSA_REQ_ORG=$cert_org
fi
if [[ ! -z $cert_ou ]]; then
  export EASYRSA_REQ_OU=$cert_ou
fi
if [[ ! -z $cert_email ]]; then
  export EASYRSA_REQ_EMAIL=$cert_email
fi
if [[ ! -z $key_cn ]]; then
  export EASYRSA_REQ_CN=$key_cn
fi

# Init PKI dirs and build CA certs
./easyrsa init-pki
./easyrsa build-ca nopass
# Generate Diffie-Hellman parameters
./easyrsa gen-dh
# Genrate server keypair
./easyrsa build-server-full server nopass

# Generate shared-secret for TLS Authentication
openvpn --genkey --secret pki/ta.key


printf "\n################## Setup OpenVPN ##################\n"

# Copy certificates and the server configuration in the openvpn directory
cp /etc/openvpn/easy-rsa/pki/{ca.crt,ta.key,issued/server.crt,private/server.key,dh.pem} "/etc/openvpn/"
cp "$base_path/installation/server.conf" "/etc/openvpn/"
mkdir "/etc/openvpn/ccd"

# Adjust the OpenVPN configuration
sed -i "s/port 443/port $server_port/" "/etc/openvpn/server.conf"
sed -i "s/;tls-auth ta.key 0/tls-auth ta.key 0\nkey-direction 0/" /etc/openvpn/server.conf
sed -i "s/;cipher AES-128-CBC/cipher AES-128-CBC\nauth SHA256/" /etc/openvpn/server.conf
sed -i "s/;user nobody/user nobody/" /etc/openvpn/server.conf
sed -i "s/;group nogroup/group nogroup/" /etc/openvpn/server.conf

if [ $openvpn_proto = "udp" ]; then
  sed -i "s/proto tcp/proto $openvpn_proto/" "/etc/openvpn/server.conf"
fi

printf "\n################## Setup firewall ##################\n"
# Allow IP forwarding
sed -i "s/#net.ipv4.ip_forward/net.ipv4.ip_forward/" /etc/sysctl.conf
sysctl -p

#Initial setup iptables-persistent so that rules can persist across reboots
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
apt-get install -y iptables-persistent

VPNDEVICE=`ls /sys/class/net/ | grep -v "ip6tnl0\|lo\|tunl0"`
# Edit iptables rules to allow for forwarding
iptables -t nat -A POSTROUTING -o tun+ -j MASQUERADE
iptables -t nat -A POSTROUTING -o $VPNDEVICE -j MASQUERADE

# Make iptables rules persistent across reboots
iptables-save > /etc/iptables/rules.v4

printf "\n################## Setup MySQL database ##################\n"

echo "CREATE DATABASE \`openvpn-admin\`" | mysql -u root --password="$mysql_root_pass"
echo "CREATE USER $mysql_user@localhost IDENTIFIED BY '$mysql_pass'" | mysql -u root --password="$mysql_root_pass"
echo "GRANT ALL PRIVILEGES ON \`openvpn-admin\`.*  TO $mysql_user@localhost" | mysql -u root --password="$mysql_root_pass"
echo "FLUSH PRIVILEGES" | mysql -u root --password="$mysql_root_pass"


printf "\n################## Setup web application ##################\n"

# Copy bash scripts (which will insert row in MySQL)
cp -r "$base_path/installation/scripts" "/etc/openvpn/"
chmod +x "/etc/openvpn/scripts/"*

# Configure MySQL in openvpn scripts
sed -i "s/USER=''/USER='$mysql_user'/" "/etc/openvpn/scripts/config.sh"
sed -i "s/PASS=''/PASS='$mysql_pass'/" "/etc/openvpn/scripts/config.sh"

# Create the directory of the web application
mkdir "$openvpn_admin"
cp -r "$base_path/"{index.php,sql,bower.json,.bowerrc,js,include,css,installation/client-conf} "$openvpn_admin"

# New workspace
cd "$openvpn_admin"

# Replace config.php variables
sed -i "s/\$user = '';/\$user = '$mysql_user';/" "./include/config.php"
sed -i "s/\$pass = '';/\$pass = '$mysql_pass';/" "./include/config.php"

# Replace in the client configurations with the ip of the server and openvpn protocol
for file in "./client-conf/gnu-linux/client.conf" "./client-conf/osx-viscosity/client.conf" "./client-conf/windows/client.ovpn"; do
  sed -i "s/remote xxx\.xxx\.xxx\.xxx 1194/remote $ip_server $server_port/" $file
  sed -i "s/;user nobody/user nobody/" $file
  sed -i "s/;group nogroup/group nogroup/" $file
  echo "cipher AES-128-CBC" >> $file
  echo "auth SHA256" >> $file
  echo "key-direction 1" >> $file
  echo "#script-security 2" >> $file
  echo "#up /etc/openvpn/update-resolv-conf" >> $file
  echo "#down /etc/openvpn/update-resolv-conf" >> $file

  if [ $openvpn_proto = "udp" ]; then
    sed -i "s/proto tcp-client/proto udp/" $file
  fi
done

# Copy ta.key inside the client-conf directory
for directory in "./client-conf/gnu-linux/" "./client-conf/osx-viscosity/" "./client-conf/windows/"; do
  cp "/etc/openvpn/"{ca.crt,ta.key} $directory
done

# Install third parties
bower --allow-root install
chown -R "$user:$group" "$openvpn_admin"
