#!/usr/bin/env bash

# download and install datadog agent on platforms where no package is available
# redhat requires libcurl-devel postgresql-devel python python-devel redhat-rpm-config

DD_API_KEY="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
DD_HOME="/opt/datadog-agent"
DD_START_AGENT=0
export DD_API_KEY DD_HOME DD_START_AGENT

# script must be run as superuser
if [ $EUID -ne 0 ]; then
  echo "script must be run as root"
  exit 1
fi

# create dd-agent group if it doesn't exist
if [[ ! $(getent group dd-agent) ]]; then
  groupadd dd-agent
fi

# create dd-agent user if it doesn't exist
if [[ ! $(getent passwd dd-agent) ]]; then
  useradd -c "Datadog Agent" -d $DD_HOME -g dd-agent dd-agent 
fi

# backup the existing datadog-agent directory and stop the service
if [[ -d $DD_HOME ]]; then
  backup_dir=$DD_HOME.`date +%s`
  systemctl stop datadog-agent
  mv $DD_HOME $backup_dir
fi

# download and install agent
sh -c "$(curl -L https://raw.githubusercontent.com/DataDog/dd-agent/master/packaging/datadog-agent/source/setup_agent.sh)"
sleep 2

# copy old config files to new installation
if [[ -d $backup_dir ]] && [[ -d $DD_HOME ]]; then
  echo
  cp $backup_dir/agent/datadog.conf $DD_HOME/agent/
  cp $backup_dir/agent/conf.d/*yaml $DD_HOME/agent/conf.d/
fi

# fix permissions
chown -R dd-agent:dd-agent $DD_HOME
find $DD_HOME -type d -exec chmod 750 {} \;

# contents of our systemd service file
dd_service="#
# Systemd unit file for datadog agent
#

[Unit]
Description=\"Datadog Agent\"
After=network.target

[Service]
Type=simple
User=dd-agent
WorkingDirectory=$DD_HOME
ExecStart=$DD_HOME/bin/agent start
ExecStop=$DD_HOME/bin/agent stop

[Install]
WantedBy=multi-user.target"

# enable and start service
echo "$dd_service" > /etc/systemd/system/datadog-agent.service
systemctl daemon-reload
systemctl enable datadog-agent
systemctl start datadog-agent
