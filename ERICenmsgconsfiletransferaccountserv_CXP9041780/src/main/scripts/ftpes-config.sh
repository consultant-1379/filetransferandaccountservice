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
CHMOD=/bin/chmod
CHOWN=/bin/chown
CP=/bin/cp
CAT=/bin/cat
SED=/bin/sed
SERVICE=/sbin/service
SYSTEMCTL=/bin/systemctl
SETSEBOOL=/usr/sbin/setsebool

# GLOBAL VARIABLES
SCRIPT_NAME="${BASENAME} ${0}"
LOG_TAG="FTPES_POST_INSTALL"
FTPES_CERT_DIR=/ericsson/cert/data/certs/vsftpd
FTPES_CA_DIR=/ericsson/cert/data/certs/CA
VSFTPD_CONF=/etc/vsftpd
VSFTPD_CERTS_DIR=${VSFTPD_CONF}/certs
VSFTPD_CERT=vsftpd.pem
VSFTPD_KEY=vsftpd.key
VSFTPD_CA=vsftpd.pem
FTPES_CERT=cert.pem
FTPES_KEY=cert.key
FTPES_CA=ca.pem
VSFTPD_SERVICE_FILE=/usr/lib/systemd/system/vsftpd@.service

#///////////////////////////////////////////////////////////////
# This function will print an error message to /var/log/messages
# Arguments:
#       $1 - Message
# Return: 0
#//////////////////////////////////////////////////////////////
error()
{
    logger -s -t ${LOG_TAG} -p user.err "ERROR ( ${SCRIPT_NAME} ): $1"
}

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

    info "Set SE Linux policy to allow access to FTP HOME DIR"
    ${SETSEBOOL} ftpd_full_access on
    ${SETSEBOOL} allow_ftpd_use_nfs on
    #TORF-507557 As part this TR, Redhat has suggested below change
    ${SETSEBOOL} ftpd_connect_all_unreserved on
}

modify_rights(){
    ${CHMOD} 640 ${VSFTPD_CERTS_DIR}/*
    ${CHOWN} jboss_user:mm-smrsusers ${VSFTPD_CERTS_DIR}/*
}

check_certs(){

if [ ! -e "$VSFTPD_CERTS_DIR" ]; then
    mkdir -p "$VSFTPD_CERTS_DIR"
fi

if [ -f "$FTPES_CERT_DIR/$VSFTPD_CERT" ]; then
    yes | cp "$FTPES_CERT_DIR/$VSFTPD_CERT" "$VSFTPD_CERTS_DIR/$FTPES_CERT"
else
    error "There is no file: $FTPES_CERT_DIR/$VSFTPD_CERT"
fi

if [ -f "$FTPES_CERT_DIR/$VSFTPD_KEY" ]; then
    yes | cp "$FTPES_CERT_DIR/$VSFTPD_KEY" "$VSFTPD_CERTS_DIR/$FTPES_KEY"
else
    error "There is no file: $FTPES_CERT_DIR/$VSFTPD_KEY"
fi

if [ -f "$FTPES_CA_DIR/$VSFTPD_CA" ]; then
    yes | cp "$FTPES_CA_DIR/$VSFTPD_CA" "$VSFTPD_CERTS_DIR/$FTPES_CA"
else
    error "There is no file: $FTPES_CA_DIR/$VSFTPD_CA"
fi
}

## Create vsftpd configuration files ##
create_vsftpd_conf_file(){
    info "Remove default vsftpd configuration file ..."

    if [ -f  ${VSFTPD_CONF}/vsftpd.conf ]; then
        rm -f ${VSFTPD_CONF}/vsftpd.conf
    fi

    info "Creating vsftpd configuration files ..."

    VSFTPD_CONFIG_FILE=${VSFTPD_CONF}/ftpes.conf
    VSFTPD_CONFIG_FILE_IPV6=${VSFTPD_CONF}/ftpes_ipv6.conf

    edit_vsftpd_config_file

    vsftpd_conf_template ${VSFTPD_CONFIG_FILE} "YES" "NO" "$tls13_opt"
    vsftpd_conf_template ${VSFTPD_CONFIG_FILE_IPV6} "NO" "YES" "$tls13_opt"

    $SYSTEMCTL stop vsftpd.service
    $SYSTEMCTL disable vsftpd.service
    $SYSTEMCTL daemon-reload
    $SYSTEMCTL restart vsftpd.target
    # TORF-647031 : to solve the problem sometime ftpes_ipv6.service not restart
    $SYSTEMCTL is-failed vsftpd@ftpes.service &>/dev/null
    if [ $? -eq 0 ]; then
        info "Restarting RHEL specific service vsftpd@ftpes.service ..."
        $SYSTEMCTL restart vsftpd@ftpes.service
    fi
    $SYSTEMCTL is-failed vsftpd@ftpes_ipv6.service &>/dev/null
    if [ $? -eq 0 ]; then
        info "Restarting RHEL specific service vsftpd@ftpes_ipv6.service ..."
        $SYSTEMCTL restart vsftpd@ftpes_ipv6.service
    fi
}

edit_vsftpd_config_file() {
    # option 'ssl_tlsv1_3' is not supported by vsftpd version 3.0.2 included in RHEL7
    # it is supported by all other versions used in ENM (version 3.0.3 included in RHEL8 and 3.0.5 included in SLES15)
    VSFTPD=vsftpd
    if [ -f "${VSFTPD_SERVICE_FILE}" ]; then
        # get the path to the vsftpd executable from the service configuration file
        VSFTPD=$($SED -nE '0,/^ExecStart=([^ ]*).*/s//\1/p' "${VSFTPD_SERVICE_FILE}")
    fi
    if [[ "$($VSFTPD -v)" == *"version 3.0.2" ]]; then
        info "TLS 1.3 configuration option is not supported"
        tls13_opt=""
    else
        info "TLS 1.3 configuration option is supported"
        tls13_opt=$(${CAT} << EOF
ssl_tlsv1_3=YES
EOF
)
    fi
}

# Function to bind only for ipv6 with net.ipv6.bindv6only sysctl parameter

bind_only_ipv6() {
 systemctl is-active vsftpd@ftpes.service &>/dev/null
 if [ $? -ne 0 ]; then
     info "vsftpd@ftpes.service is not active"
 else
     info "vsftpd@ftpes.service is active"
 fi

 systemctl is-failed vsftpd@ftpes.service &>/dev/null
 if [ $? -eq 0 ]; then
     info "vsftpd@ftpes.service is in failed state"
 fi

 systemctl is-enabled vsftpd@ftpes.service &>/dev/null
 if [ $? -ne 0 ]; then
     info "vsftpd@ftpes.service is not enabled"
 else
     info "vsftpd@ftpes.service is enabled"
 fi

 systemctl is-active vsftpd@ftpes_ipv6.service &>/dev/null
 if [ $? -ne 0 ]; then
     info "vsftpd@ftpes_ipv6.service is not active"
 else
     info "vsftpd@ftpes_ipv6.service is active"
 fi

 systemctl is-failed vsftpd@ftpes_ipv6.service &>/dev/null
 if [ $? -eq 0 ]; then
     info "vsftpd@ftpes_ipv6.service is in failed state"
 fi

 systemctl is-enabled vsftpd@ftpes_ipv6.service &>/dev/null
 if [ $? -ne 0 ]; then
     info "vsftpd@ftpes_ipv6.service is not enabled"
 else
     info "vsftpd@ftpes_ipv6.service is enabled"
 fi

 if [ -f "${FTPES_SERVICE_FILE}" ]; then
     isCENM=$(printenv CLOUD_NATIVE_DEPLOYMENT);
     if [[ "${isCENM,,}" == "true" ]]; then
       info "${FTPES_SERVICE_FILE} exists. Checking net.ipv6.bindv6only"
       if ! grep "net.ipv6.bindv6only" ${FTPES_SERVICE_FILE} &>/dev/null; then
          info "net.ipv6.bindv6only does not exist in ${FTPES_SERVICE_FILE}"
          $SED -i '/^ExecStart=.*/i ExecStartPre=/usr/sbin/sysctl -w "net.ipv6.bindv6only=1"' ${FTPES_SERVICE_FILE}
          $SED -i '/^ExecStart=.*/a ExecStartPost=/usr/sbin/sysctl -w "net.ipv6.bindv6only=0"' ${FTPES_SERVICE_FILE}
          info "net.ipv6.bindv6only change added in ${FTPES_SERVICE_FILE}"
       else
          info "net.ipv6.bindv6only exists in ${FTPES_SERVICE_FILE}"
       fi
     fi

     info "Checking vmmonitord service dependency in ${FTPES_SERVICE_FILE}"
     if ! grep "vmmonitord.service" ${FTPES_SERVICE_FILE} &>/dev/null; then
        info "vmmonitord service dependency does not exist in ${FTPES_SERVICE_FILE}"
        $SED -i 's/^After=.*/After=network.target vmmonitord.service/' ${FTPES_SERVICE_FILE}
        info "vmmonitord service dependency change added in ${FTPES_SERVICE_FILE}"
     else
        info "vmmonitord service dependency exist in ${FTPES_SERVICE_FILE}"
     fi
 else
     error "${FTPES_SERVICE_FILE} does not exist, 2 vsftpd instances may not be up !!!"
 fi
}

vsftpd_conf_template(){

${CAT} << EOF > ${1}
anonymous_enable=NO
local_enable=YES
write_enable=YES
#
local_root=/home/smrs
#
dirmessage_enable=YES
connect_from_port_20=YES
#
xferlog_enable=YES
xferlog_std_format=YES
dual_log_enable=YES
debug_ssl=YES
log_ftp_protocol=YES

pasv_address=`grep svc_CM_vip_ipaddress /ericsson/tor/data/global.properties | cut -d '=' -f 2-`
#
listen=${2}
listen_ipv6=${3}
pam_service_name=vsftpd
#
listen_port=9921
ftp_data_port=9920
#
pasv_enable=NO
pasv_max_port=9920
pasv_min_port=9920
#
ssl_tlsv1=NO
ssl_tlsv1_1=NO
ssl_tlsv1_2=YES
${4}
ssl_sslv2=NO
ssl_sslv3=NO
ssl_enable=YES
#
require_ssl_reuse=NO
ssl_ciphers=HIGH
rsa_cert_file=/etc/vsftpd/certs/cert.pem
rsa_private_key_file=/etc/vsftpd/certs/cert.key
ca_certs_file=/etc/vsftpd/certs/ca.pem
require_cert=YES
validate_cert=YES
#
chroot_local_user=YES
EOF
}

#############
# MAIN PROGRAM
#############
setsebool
bind_only_ipv6
check_certs
modify_rights
create_vsftpd_conf_file
