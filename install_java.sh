#!/usr/bin/env bash

java_base=/opt/java

# script must be run as superuser
if [ $EUID -ne 0 ]; then
  echo "script must be run as root"
  exit 1
fi

# are we installing an oracle-named tgz?
if [[ $# != 1 ]] || [[ ! -f $1 ]] ||  [[ -d $1 ]] || [[ $1 != *jdk-*-*.gz ]]; then
  echo "usage: $0 jdk-ver-os-arch.tar.gz"
  exit 1
fi

# make sure base directory is writable
mkdir -p $java_base
if [[ ! -w $java_base ]]; then
  echo "$java_base is not writable!"
  exit 1
fi

echo "installing $1..."

# extract and remember java version
for java_ver in $(tar xzfv $1 -C $java_base|awk -F '/' '{print $1}'); do
  java_home=$java_base/$java_ver
done

# fix permissions
chown -R root:wheel $java_home
find $java_home -type d -exec chmod 755 {} \;
find $java_home -exec chmod go-w {} \;

# update system alternatives
alternatives --install /usr/bin/java java $java_home/bin/java 1
update-alternatives --config java

echo
echo "java $java_ver installed!"
echo
java -version
