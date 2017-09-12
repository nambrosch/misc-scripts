#!/usr/bin/env bash

# install ubiquiti unifi controller software
# download url: https://dl.ubnt.com/unifi/5.4.11/UniFi.unix.zip

# redhat requires oracle-java mongodb-server

unifi_base=/opt/unifi

# script must be run as superuser
if [ $EUID -ne 0 ]; then
  echo "script must be run as root"
  exit 1
fi

# only one parameter please
if [[ $# == 1 ]];  then
  unifi_ver=$1
else
  echo "usage: $0 [version]"
  exit 1
fi

# make sure base directory is writable
mkdir -p $unifi_base

if [[ ! -w $unifi_base ]]; then
  echo "$unifi_base is not writable!"
  exit 1
fi

# install mongodb-server
dnf install mongodb-server -y

# stop if the requested version already exists on disk
if [[ -d $unifi_base/$unifi_ver ]]; then
  echo "version $unifi_ver already exists at $unifi_base/$unifi_ver"
  exit 1
fi

# just in case the install script failed last time
rm -Rf $unifi_base/UniFi
rm -f $unifi_base/UniFi.unix.zip*

# stop service
systemctl stop unifi

# download unifi controller archive
echo "downloading UniFi.unix.zip $unifi_ver..."
if [[ ! $(wget -q -P $unifi_base https://dl.ubnt.com/unifi/$unifi_ver/UniFi.unix.zip) ]]; then
  unzip -q $unifi_base/UniFi.unix.zip -d $unifi_base
  rm -f $unifi_base/UniFi.unix.zip
  mv $unifi_base/UniFi $unifi_base/$unifi_ver
else
  echo "download of https://dl.ubnt.com/unifi/$unifi_ver/UniFi.unix.zip failed!"
  exit 1
fi

# create unifi group if it doesn't exist
if [[ ! $(getent group unifi) ]]; then
  groupadd unifi
fi

# create unifi user if it doesn't exist
if [[ ! $(getent passwd unifi) ]]; then
  useradd -c "UniFi" -d $unifi_base -g unifi unifi
fi

# fix permissions
chown -R unifi:unifi $unifi_base
find $unifi_base -type d -exec chmod 750 {} \;

unifi_service="#
# Systemd unit file for UniFi Controller
#

[Unit]
Description=\"UniFi AP Web Controller\"
After=network.target

[Service]
Type=simple
User=unifi
WorkingDirectory=$unifi_base/$unifi_ver
ExecStart=/usr/bin/java -Xmx512M -server -jar $unifi_base/$unifi_ver/lib/ace.jar start
ExecStop=/usr/bin/java -jar $unifi_base/$unifi_ver/lib/ace.jar stop
SuccessExitStatus=143

[Install]
WantedBy=multi-user.target"

# enable but do not start service
echo "enabling unifi service, don't forget to start!"
echo "$unifi_service" > /etc/systemd/system/unifi.service
systemctl daemon-reload
systemctl enable unifi
