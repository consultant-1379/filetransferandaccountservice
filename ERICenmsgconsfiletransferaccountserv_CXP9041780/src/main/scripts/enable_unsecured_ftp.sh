#!/usr/bin/env bash

###########################################################################
# COPYRIGHT Ericsson 2021
#
# The copyright to the computer program(s) herein is the property of
# Ericsson Inc. The programs may be used and/or copied only with written
# permission from Ericsson Inc. or in accordance with the terms and
# conditions stipulated in the agreement/contract under which the
# program(s) have been supplied.
# This script requires bash 4 or above
#
###########################################################################

# UTILITIES
CAT=/bin/cat
SERVICE=/sbin/service
SETSEBOOL=/usr/sbin/setsebool
SYSTEMCTL=/bin/systemctl
SED=/bin/sed
CP=/bin/cp

# GLOBAL VARIABLES
SMRS_HOME=/home/smrs/
MINI_LINK_HOME=/home/smrs/MINI-LINK
JAILDIRECTORY=${MINI_LINK_HOME}/MINI-LINK-Indoor/
USER_CONFIG_FILEPATH=/etc/vsftpd_user_conf
VSFTPD_CONF_LOCATION=/etc/vsftpd
SCRIPT_NAME="${BASENAME} ${0}"
LOG_TAG="UNSECURED_FTP_ENABLE"
FTP_BACKUP_LOCATION=/ericsson/tor/data/smrs_unsecured_ftp
FTP_SERVICE_FILE=/usr/lib/systemd/system/vsftpd@.service

#//////////////////////////////////////////////////////////////
# This function will print an info message to /var/log/messages
# Arguments:
#       $1 - Message
# Return: 0
#/////////////////////////////////////////////////////////////
info()
{
    logger -s -t ${LOG_TAG} -p user.notice "INFORMATION ( ${SCRIPT_NAME} ): $1"
}

setsebool(){

    info "Set SE Linux policy to allow access to FTP DIR"
    ${SETSEBOOL} ftpd_full_access on	# Remove this in EAP 7.3+ if no longer needed (https://bugzilla.redhat.com/show_bug.cgi?id=1406542)
    info "Set SE Linux policy to allow ftpd use nfs"
    ${SETSEBOOL} allow_ftpd_use_nfs on
}


create_vsftpd_conf_file(){

    info "Remove default configuration files ..."

    rm -f ${VSFTPD_CONF_LOCATION}/vsftpd.conf

    info "Creating configuration files for unsecured ftp ..."
    VSFTPD_UNSECURE_CONFIG_FILE=${VSFTPD_CONF_LOCATION}/ftp.conf
    VSFTPD_UNSECURE_CONFIG_FILE_IPV6=${VSFTPD_CONF_LOCATION}/ftp_ipv6.conf

    vsftpd_unsecure_conf_template ${VSFTPD_UNSECURE_CONFIG_FILE} "YES" "NO"
    vsftpd_unsecure_conf_template ${VSFTPD_UNSECURE_CONFIG_FILE_IPV6} "NO" "YES"

}

# Function to bind only for ipv6 with net.ipv6.bindv6only sysctl parameter
bind_only_ipv6_in_vsftpd_service_file() {
    if [ -f "${FTP_SERVICE_FILE}" ]; then
        info "${FTP_SERVICE_FILE} exists. Checking net.ipv6.bindv6only"
        if ! grep "net.ipv6.bindv6only" ${FTP_SERVICE_FILE} &>/dev/null; then
            info "net.ipv6.bindv6only does not exist in ${FTP_SERVICE_FILE}"
            $SED -i '/^ExecStart=.*/i ExecStartPre=/sbin/sysctl -w "net.ipv6.bindv6only=1"' ${FTP_SERVICE_FILE}
            $SED -i '/^ExecStart=.*/a ExecStartPost=/sbin/sysctl -w "net.ipv6.bindv6only=0"' ${FTP_SERVICE_FILE}
            info "net.ipv6.bindv6only change added in ${FTP_SERVICE_FILE}"
        else
            info "net.ipv6.bindv6only exists in ${FTP_SERVICE_FILE}"
        fi

        info "Checking vmmonitord service dependency in ${FTP_SERVICE_FILE}"
        if ! grep "vmmonitord.service" ${FTP_SERVICE_FILE} &>/dev/null; then
            info "vmmonitord service dependency does not exist in ${FTP_SERVICE_FILE}"
            $SED -i 's/^After=.*/After=network.target vmmonitord.service/' ${FTP_SERVICE_FILE}
            info "vmmonitord service dependency change added in ${FTP_SERVICE_FILE}"
        else
            info "vmmonitord service dependency exist in ${FTP_SERVICE_FILE}"
        fi
    else
        error "${FTP_SERVICE_FILE} does not exist, vsftpd instances may not be up !!!"
    fi
}

# Function to restart vsftpd service
restart_vsftpd(){
    $SYSTEMCTL stop vsftpd.service
    $SYSTEMCTL disable vsftpd.service
    $SYSTEMCTL daemon-reload
    $SYSTEMCTL restart vsftpd.target
}

vsftpd_unsecure_conf_template(){

${CAT} << EOF > ${1}
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022
#
user_config_dir=${USER_CONFIG_FILEPATH}
#
dirmessage_enable=YES
dual_log_enable=YES
xferlog_enable=YES
connect_from_port_20=YES
xferlog_std_format=YES
log_ftp_protocol=NO

pasv_address=`grep svc_CM_vip_ipaddress /ericsson/tor/data/global.properties | cut -d '=' -f 2-`
#
listen=${2}
listen_ipv6=${3}
pam_service_name=vsftpd
#
pasv_enable=YES
pasv_max_port=11863
pasv_min_port=10164
#
userlist_enable=YES
tcp_wrappers=YES
listen_port=21
ftp_data_port=20
EOF
}

vsftpd_mli_ftp_users_configuration(){
    info "Configuring chroot for MINI-LINK-Indoor ftp Users"

    mkdir -p /etc/vsftpd_user_conf

    config_chroot_pmpush pm_push_1
    config_chroot_pmpush pm_push_2
    config_chroot_shm backup
    config_chroot_shm software
    config_chroot_shm licence
}

config_chroot_pmpush(){

${CAT} << EOF > ${USER_CONFIG_FILEPATH}/mm-mli-${1}
local_root=${MINI_LINK_HOME}/${1}/
EOF
}

config_chroot_shm(){

${CAT} << EOF > ${USER_CONFIG_FILEPATH}/mm-mli-${1}
local_root=${JAILDIRECTORY}
EOF
}

create_ftpconf_backup(){
    info "Creating backup of unsecured ftp conf files"

    mkdir -p ${FTP_BACKUP_LOCATION}

    if [ -f  ${VSFTPD_CONF_LOCATION}/ftp.conf ]; then
        yes |  ${CP} "${VSFTPD_CONF_LOCATION}/ftp.conf" "${FTP_BACKUP_LOCATION}"
    fi

    if [ -f  ${VSFTPD_CONF_LOCATION}/ftp_ipv6.conf ]; then
        yes |  ${CP} "${VSFTPD_CONF_LOCATION}/ftp_ipv6.conf" "${FTP_BACKUP_LOCATION}"
    fi
}

check_and_log_service_status() {
    status=$(systemctl $2 $1)
    info "Status for service $1 with state $2 is $status"
}

#############
# MAIN PROGRAM
#############
setsebool
bind_only_ipv6_in_vsftpd_service_file
vsftpd_mli_ftp_users_configuration
create_vsftpd_conf_file
create_ftpconf_backup
restart_vsftpd
check_and_log_service_status vsftpd@ftp.service is-active
check_and_log_service_status vsftpd@ftp.service is-failed
check_and_log_service_status vsftpd@ftp.service is-enabled
check_and_log_service_status vsftpd@ftp_ipv6.service is-active
check_and_log_service_status vsftpd@ftp_ipv6.service is-failed
check_and_log_service_status vsftpd@ftp_ipv6.service is-enabled
