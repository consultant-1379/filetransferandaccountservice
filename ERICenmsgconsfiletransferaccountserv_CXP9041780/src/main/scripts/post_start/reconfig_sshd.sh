#!/bin/bash

###########################################################################
# COPYRIGHT Ericsson 2021
#
# The copyright to the computer program(s) herein is the property of
# Ericsson Inc. The programs may be used and/or copied only with written
# permission from Ericsson Inc. or in accordance with the terms and
# conditions stipulated in the agreement/contract under which the
# program(s) have been supplied.
###########################################################################
working_dir="$(dirname "$0")"
source "$working_dir/apply_sftp_match_rules.sh"

GLOBAL_PROPERTIES_FILE="/ericsson/tor/data/global.properties"
CLOUD_GLOBAL_PROPERTIES_FILE_PATH="enm/deprecated/global_properties"
SSHD_CONFIG=/etc/ssh/sshd_config
MAX_STARTUP_CONFIG_TAG=MaxStartups
MAX_STARTUP_NEW_VALUE=1000
LOG_LEVEL="LogLevel"
LOG_LEVEL_INFO="INFO"
PASSWORD_AUTH="PasswordAuthentication"
YES="yes"
SCRIPT_NAME="${BASENAME} ${0}"
LOG_TAG="reconfig_sshd"
SMRS_SFTP_PORT_PARTITION_ENABLE="smrs_sftp_port_partition_enable"
SMRS_SFTP_SECUREPORT="smrs_sftp_securePort"
SMRS_SFTP_PORT_PARTITION_ENABLE_KEY="$SMRS_SFTP_PORT_PARTITION_ENABLE="
SMRS_SFTP_SECUREPORT_KEY="$SMRS_SFTP_SECUREPORT="
DDC_ON_CLOUD_KEY="DDC_ON_CLOUD="
CONSUL="/usr/bin/consul"
SYSTEMCTL="/bin/systemctl"

#########################################################
# These functions will log a message to /var/log/messages
# Arguments:
#       $1 - Message
# Return: 0
#########################################################
error()
{
    logger  -t ${LOG_TAG} -p user.err "ERROR ( ${SCRIPT_NAME} ): $1"
}

info()
{
    logger  -t ${LOG_TAG} -p user.notice "INFORMATION ( ${SCRIPT_NAME} ): $1"
}

#Read required properties from global.properties
read_sshd_config_params(){
    if [ -f ${GLOBAL_PROPERTIES_FILE} ] ; then
        isCloud=$(grep -Po "(?<=^${DDC_ON_CLOUD_KEY}).*" ${GLOBAL_PROPERTIES_FILE})
        isCloud="${isCloud,,}"

        if [[ "$isCloud" == "true" ]]; then
            read_sshd_config_params_from_consul
        else
            read_sshd_config_params_from_global_properies
        fi

        info "smrs_sftp_securePort=$smrs_sftp_securePort, smrs_sftp_port_partition_enable=$smrs_sftp_port_partition_enable"
    else
        error "The ${GLOBAL_PROPERTIES_FILE} file doesn't exist"
        return 3
    fi
}

# Read the required properties: smrs_sftp_securePort, smrs_sftp_port_partition_enable, subnet ip addresses from global.properties file
read_sshd_config_params_from_global_properies(){
    info "Reading values from global properties"

    smrs_sftp_securePort=$(grep -Po "(?<=^${SMRS_SFTP_SECUREPORT_KEY}).*" ${GLOBAL_PROPERTIES_FILE})
    smrs_sftp_port_partition_enable=$(grep -Po "(?<=^${SMRS_SFTP_PORT_PARTITION_ENABLE_KEY}).*" ${GLOBAL_PROPERTIES_FILE})
}

# Read the required properties: smrs_sftp_securePort, smrs_sftp_port_partition_enable, subnet ip addresses from consul
read_sshd_config_params_from_consul(){
    info "Reading values from consul"

    smrs_sftp_securePort=`"$CONSUL" kv get "$CLOUD_GLOBAL_PROPERTIES_FILE_PATH/$SMRS_SFTP_SECUREPORT"`
    smrs_sftp_port_partition_enable=`"$CONSUL" kv get "$CLOUD_GLOBAL_PROPERTIES_FILE_PATH/$SMRS_SFTP_PORT_PARTITION_ENABLE"`
}

# Stop the sshd service
stop_sshd() {
    #dump current sshd status
    info "execute reconfig_sshd: sshd current status"
    $SYSTEMCTL status sshd

    #stop sshd service
    info "execute reconfig_sshd: stop sshd"
    $SYSTEMCTL stop sshd
}

# Start the sshd service
start_sshd() {
    info "execute reconfig_sshd: start sshd"
    $SYSTEMCTL start sshd
    if [ $? -eq 0 ]; then
        info "Restart of sshd service was successful"
    else
        error "Restart of sshd service failed"
    fi
}

###########################################################################
# Update the default Port 22 and dynamic port from global.properties
# to /etc/ssh/sshd_config
# Arguments:
#       $1 - Dynamic Port
###########################################################################
configure_sshd_config() {

    if [ `grep -c "^Port " $SSHD_CONFIG` == 0 ]
    then
        info "Port not found. Updating default port:22 and dynamic port:$1"
        sed -i "1iPort 22\nPort $1" $SSHD_CONFIG
    else
        if [ `grep -c "^Port *" $SSHD_CONFIG` -gt 1 ]
        then
            portline=`grep -n "^Port" $SSHD_CONFIG | awk -F: '{print $1}' | tail -1`
            sed -i -e "$portline"d $SSHD_CONFIG
            configure_sshd_config $smrs_sftp_securePort
        else
            info "Port found. Updating default port:22 and dynamic port:$1"
            sed -i "s/^Port .*/Port 22\\nPort $1/g" $SSHD_CONFIG
        fi
    fi
}

# Configure sftp port
configure_sftp_port() {
    info "smrs sftp port value :$smrs_sftp_securePort"
    if [[ ! -z "$smrs_sftp_securePort" && "$smrs_sftp_securePort" != 22 ]]
    then
        info "Configuring SFTP Port"
        configure_sshd_config $smrs_sftp_securePort
        append_sftp_match_rules "$isCloud" "$smrs_sftp_securePort" "$smrs_sftp_port_partition_enable"
    else
        info "Skip smrs sftp port configuration as GLOBAL Port value:$smrs_sftp_securePort"
    fi
}

###########################################################################
# Update sshd configuration parameters with new value in /etc/ssh/sshd_config file.
# Arguments:
#       $1 - Target sshd configuration parameter
#       $2 - Parameter value
###########################################################################
update_sshd_config_parameters() {
    if [ `grep -c "^$1 " $SSHD_CONFIG` == 0 ]
    then
        info "$1 NOT FOUND"
        if [ `grep -c "^#$1 " $SSHD_CONFIG` == 0 ]
        then
            info "#$1 NOT FOUND"
        else
            info "#$1 FOUND"
            sed -i "s/^#$1 .*/$1 $2/g" $SSHD_CONFIG
            info "enable $1 to $2"
        fi
    else
        info "$1 FOUND"
        sed -i "s/^$1 .*/$1 $2/g" $SSHD_CONFIG
        info "update $1 to $2"
    fi
}

# Update sshd_config
update_sshd_config() {
    info "execute reconfig_sshd"
    stop_sshd
    update_sshd_config_parameters $MAX_STARTUP_CONFIG_TAG $MAX_STARTUP_NEW_VALUE
    update_sshd_config_parameters $LOG_LEVEL $LOG_LEVEL_INFO
    update_sshd_config_parameters $PASSWORD_AUTH $YES
    configure_sftp_port
    start_sshd
    info "reconfig_sshd done!"
}

# Execution Start here
read_sshd_config_params
update_sshd_config
exit 0