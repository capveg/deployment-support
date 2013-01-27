#!/bin/sh
#
# vim: tabstop=4 shiftwidth=4 softtabstop=4
#
# Copyright 2011, Big Switch Networks, Inc.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.
#
# @author: Mandeep Dhami, Big Switch Networks, Inc.
#

# USAGE:
# Set up quantum configuration for network controller. Use as:
#   ./install-plugin.sh <network-ctrls> [<auth-params> [<use-ssl>]]
#
# e.g.:
#   ./install-plugin.sh 192.168.2.100:80,192.168.2.101:80 user:pass true
#
USAGE="$0 <network-ctrls> [<auth-params> [<use-ssl>]]"


# Globals
set -e
NETWORK_CTRL_SERVERS="$1"
NETWORK_CTRL_AUTH="$2"
NETWORK_CTRL_SSL=`echo $3 | tr A-Z a-z`
MYSQL_USER=root
MYSQL_PASSWORD=nova
QUANTUM_ROOT=/opt/stack/quantum
QUANTUM_INI_FILE=/etc/quantum/quantum.conf
RESTPROXY_INI_FILE=/etc/quantum/plugins/bigswitch/restproxy.ini

# Download the restproxy plugin
PLUGIN_ROOT="/opt/stack/quantum/quantum/plugins"
PLUGIN_CODE="https://raw.github.com/bigswitch/deployment-support/master/openstack/bigswitch-plugin-folsom.tar"
( 
  cd "${PLUGIN_ROOT}"
  curl -s -X GET "${PLUGIN_CODE}" | tar xvf -
)

# validate parameters
if [ "${NETWORK_CTRL_SERVERS}"x = ""x ] ; then
    echo "USAGE: $USAGE" 2>&1    
    echo "  >  No Network Controller specified." 1>&2
    exit 1
fi
if [ "${NETWORK_CTRL_SSL}"x != ""x -a \
     "${NETWORK_CTRL_SSL}"x != "true"x -a \
     "${NETWORK_CTRL_SSL}"x != "false"x ] ; then
    echo "USAGE: $USAGE" 2>&1
    echo "  >  parameter 'use-ssl' must be 'true' or 'false'," \
         " not '${NETWORK_CTRL_SSL}'" 1>&2
    exit 2
fi


# setup quantum to use restproxy
if [ -f "${QUANTUM_INI_FILE}" ] ; then
    PLUGIN=quantum.plugins.bigswitch.plugin.QuantumRestProxyV2
    sudo sed -i -e "s/^\s*core_plugin\s*=.*$/core_plugin = $PLUGIN/g" \
        ${QUANTUM_INI_FILE}
else
    echo "ERROR: Did not find the Quantum INI file: ${QUANTUM_INI_FILE}" 1>&2
    exit 3
fi


# setup mysql for restproxy
mysql_cmd() {
    if [ "${MYSQL_PASSWORD}"x = ""x ]
    then
        mysql -u ${MYSQL_USER} -e "$1"
    else
        mysql -u ${MYSQL_USER} -p${MYSQL_PASSWORD} -e "$1"
    fi
}
mysql_cmd 'DROP DATABASE IF EXISTS restproxy_quantum;'
mysql_cmd 'CREATE DATABASE IF NOT EXISTS restproxy_quantum;'


# setup proxy configuration
MYSQL_AUTH="${MYSQL_USER}"
[ "${MYSQL_PASSWORD}"x = ""x ] || MYSQL_AUTH="${MYSQL_USER}:${MYSQL_PASSWORD}"
cat <<EOF > /tmp/restproxy.ini
[DATABASE]
#
# For database connectivity
#
sql_connection = mysql://${MYSQL_AUTH}@localhost/restproxy_quantum?charset=utf8
reconnect_interval = 2

[RESTPROXY]
#
# For restproxy, the following parameters are supported:
#   servers     :   <host:port>[,<host:port>]*  (Error if not set)
#   serverauth  :   <username:password>         (default: no auth)
#   serverssl   :   True | False                (default: False)
#   syncdata    :   True | False                (default: False)
#   servertimeout   :  10                       (default: 10 seconds)
#   quantumid   :   Quantum-ID                  (change if multiple
#                                                quantum instances
#                                                use same controller,
#                                                make unique per
#                                                instance in that
#                                                case)
servers = ${NETWORK_CTRL_SERVERS}
serverauth = ${NETWORK_CTRL_AUTH}
serverssl = ${NETWORK_CTRL_SSL}
#syncdata=True
#servertimeout=10
#quantumid=Quantum
EOF
sudo mkdir -p `dirname ${RESTPROXY_INI_FILE}`
sudo cp /tmp/restproxy.ini ${RESTPROXY_INI_FILE}

# Done
echo "$0 Done."
echo
