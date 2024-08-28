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

# Variables for certificates handling
_certs_data_dir="/ericsson/cert/data/certs"
_certs_source_dir="/ericsson/enm/jboss/conf"
_certs_dest_dir="/ericsson/credm/data/xmlfiles"
_certs_smrsweb_file="SmrsWeb_CertRequest.xml"

_ftpes_cert_dir_vsftpd="/ericsson/cert/data/certs/vsftpd"
_ftpes_cert_dir_CA="/ericsson/cert/data/certs/CA"
_ftpes_req_file="Vsftpd_CertRequest.xml"

_LOGGER=/bin/logger

# UTILITIES

BASENAME=/bin/basename
CHMOD=/bin/chmod
CHOWN=/bin/chown
CP=/bin/cp
SERVICE=/sbin/service
SETSEBOOL=/usr/sbin/setsebool

# GLOBAL VARIABLES
SCRIPT_NAME="${0}"
LOG_TAG='filetransferandaccountservice'
SYSTEMCTL="/bin/systemctl"
SMRS_RESOURCES_PATH="/ericsson/enm/jboss/resources"
SMRS_SSH_CONFIG_LOCATION="/ericsson/enm/jboss/etc"

error()
{
    $_LOGGER -t "${LOG_TAG}" -p user.err "ERROR ( ${SCRIPT_NAME} ): $1"
}

warning()
{
    $_LOGGER -t "${LOG_TAG}" -p user.warning "WARNING ( ${SCRIPT_NAME} ): $1"
}

info()
{
    $_LOGGER -t "${LOG_TAG}" -p user.info "INFO ( ${SCRIPT_NAME} ): $1"
}

info "Running SmrsService postinstall."

GLOBAL_PROPERTIES_FILE=/ericsson/tor/data/global.properties


# This function replaces the tag <ipaddress> for the SAN field of the certificate. There could be
# an <ipaddress> for IPv4 and one for IPv6. If the IP adress value does not exist (or is empty), the tag <ipaddress>
# is removed from the Cert request file to avoid leaving it emtpy
#
# Function usage:
#     replace_ip_for_smrsweb_cert_req_file [IP_PLACEHOLDER] [IP_VERSION] [IP_ADDRESS]
# Where:
#   IP_PLACEHOLDER: Represents the value in the tag '<ipaddress>cm_VIP</ipaddress>' that will be replaced with an
#                   IP address. I.e. 'cm_VIP' in the preceding example.
#   IP_VERSION: The string 'IPv4' or 'IPv6' identifies which IP version is being processed.
#   IP_ADDRESS: The IP address, if provided for the specified IP_VERSION, that will take the place of the
#               IP_PLACEHOLDER. If an IP_ADDRESS is not provided for the specified IP_VERSION, the
#               '<ipaddress>' tag will be removed from the cert request file.
function replace_ip_for_smrsweb_cert_req_file() {
    ip_placeholder="$1"
    ip_version="$2"
    ip_address="$3"
    if [ ! -z "$ip_address" ]; then
        sed -i -e "s/$ip_placeholder/$ip_address/g" "$_certs_source_dir/$_certs_smrsweb_file"
        info "Successfully replaced CM $ip_version VIP with value: '$ip_address' in cert request file: '$_certs_source_dir/$_certs_smrsweb_file'"
        return 0
    else
        warning "Failed to replace CM $ip_version VIP. Value seems to be blank. Tag '<ipaddress>' for SAN field will be removed from cert request file: '$_certs_source_dir/$_certs_smrsweb_file'"
        sed -i -e "s/<ipaddress>$ip_placeholder<\/ipaddress>//g" "$_certs_source_dir/$_certs_smrsweb_file"
        return 1
    fi
}

# Resolves the CM VIPs for IPv4 and IPv6 from /ericsson/tor/data/global.properties file and replaces them in
# the file SmrsWeb_CertRequest.xml to make subject alternative names available in the certificate request.
#
# The inputs from global.properties are formatted with cut to handle the following scenarios:
# 1) Multiple values in the properties 'svc_CM_vip_ipaddress' and 'svc_CM_vip_ipv6address'. In this case, only
# the first value will be considered significant (multiple values are assumed to be comma-separated and containing
# no blanks)
# 2) IP addresses in CIDR notation to specify the subnet mask
function resolve_cm_vip_and_copy_cert_for_smrsweb() {

    if [ -f $GLOBAL_PROPERTIES_FILE ]
    then
        info "global.properties found. Extracting CM VIP for IPv4 and IPv6 VIP"
            CM_VIP_IPV4=$(grep svc_CM_vip_ipaddress $GLOBAL_PROPERTIES_FILE | cut -d '=' -f2)
            CM_VIP_IPV6=$(grep svc_CM_vip_ipv6address $GLOBAL_PROPERTIES_FILE | cut -d '=' -f2)
            cm_VIP=$(echo ${CM_VIP_IPV4} | cut -d ',' -f1 | cut -d '/' -f1 | xargs echo -n)
            cm_ipv6_VIP=$(echo ${CM_VIP_IPV6} | cut -d ',' -f1 | cut -d '/' -f1 | xargs echo -n)

            replace_ip_for_smrsweb_cert_req_file "cm_VIP" "IPv4" "$cm_VIP"
            ipv4_replacement_result=$?

            replace_ip_for_smrsweb_cert_req_file "cm_ipv6_VIP" "IPv6" "$cm_ipv6_VIP"
            ipv6_replacement_result=$?

            if [ $ipv4_replacement_result == 0 ] || [ $ipv6_replacement_result == 0 ] ; then
                cp $_certs_source_dir/$_certs_smrsweb_file $_certs_dest_dir
                info "Cert request file '$_certs_source_dir/$_certs_smrsweb_file' was copied to destination directory '$_certs_dest_dir'"
            else
                error "Failed to replace at least one CM VIP for cert request. Cert request file '$_certs_source_dir/$_certs_smrsweb_file' will not be copied to destination directory '$_certs_dest_dir'"
            fi
    else
        error "global.properties file not found. Could not replace IPv4 or IPv6 in cert request file '$_certs_source_dir/$_certs_smrsweb_file'"
    fi
}

# This function will update the SELinux properties to allow SFTP upload
# Arguments:
#       None
# Return: 0
#/////////////////////////////////////////////////////////////
update_selinux_permissions()
{
    info "Configuring SELinux for SFTP chroot upload..."

    ${SETSEBOOL} -P ssh_chroot_rw_homedirs 1

    if [ $? -eq 0 ]; then
        info "Configuration of SELinux for SFTP ssh_chroot_rw_homedirs was successful"
    else
        error "Configuration of SELinux for SFTP ssh_chroot_rw_homedirs failed"
    fi
}

#//////////////////////////////////////////////////////////////
# This function will copy the sshd_config delivered with SMRS to /etc/ssh/sshd_config with correct owners, group owners and permissions.
#	It will also restart the sshd service.
#	This is allow jailing of users (nodes) that login over sftp to download certificates from SMRS filesystem
# Arguments:
#       None
# Return: 0
#/////////////////////////////////////////////////////////////
copy_sshd_config()
{
    info "Copying the sshd_config from ${SMRS_SSH_CONFIG_LOCATION} to /etc/ssh/sshd_config..."

    ${CP} -f ${SMRS_SSH_CONFIG_LOCATION}/sshd_config /etc/ssh/sshd_config

    ${CHOWN} root:root /etc/ssh/sshd_config

    ${CHMOD} 0600 /etc/ssh/sshd_config

        info "Copy of the sshd_config was successful"

    ${SERVICE} sshd restart

    if [ $? -eq 0 ]; then
        info "Restart of sshd service was successful"
    else
        error "Restart of sshd service failed"
    fi
}

#//////////////////////////////////////////////////////////////
# This function will copy the ssh_config delivered with SMRS to /etc/ssh/ssh_config with correct owners, group owners and permissions.
# No need to restart for the client file ssh_config
#
#/////////////////////////////////////////////////////////////
copy_ssh_config()
{
    info "Copying the ssh_config from ${SMRS_SSH_CONFIG_LOCATION} to /etc/ssh/ssh_config..."

    ${CP} -f ${SMRS_SSH_CONFIG_LOCATION}/ssh_config /etc/ssh/ssh_config

    ${CHOWN} root:root /etc/ssh/ssh_config

    ${CHMOD} 0600 /etc/ssh/ssh_config

    info "Copy of the ssh_config was successful"
}

function rsyslog_config_file_update() {

    info "Updating 20_rsys_server.conf file on filetransferandaccountservice Service Group"

    sed -i '/^:msg, regex, ".*DHCP.*" stop.*/a if ($msg contains "postauth" and ($msg contains "close " or $msg contains "written " or $msg contains "open " or $msg contains "mode")) then /var/log/secure\n:msg, regex, "postauth" stop' /etc/rsyslog.d/20_rsys_server.conf

    info "restarting rsyslog service"
    systemctl restart rsyslog
    info "Sleeping 5 secs to allow the rsyslog to restart"
    sleep 5
    rsyslog_status=$(systemctl status rsyslog | grep "Active: active (running)")
    rsyslog_error=$(systemctl status rsyslog | grep "rsyslogd: error" )

    if [[ "${rsyslog_status}" =~ "Active: active (running)" && "${rsyslog_error}" != *"rsyslogd: error"* ]]; then
        info "rsyslog has been started successfully"
    elif [[ "${rsyslog_status}" =~ "Active: active (running)" && "${rsyslog_error}" =~ "rsyslogd: error" ]]; then
        info "rsylogv service started but rsyslogd errors detected"
    elif [[ "${rsyslog_status}" != *"Active: active (running)"* ]]; then
        info "rsyslog has not started."
    fi
}

rsyslog_config_file_update
info "Create directory '$_certs_dest_dir' for storing xml files."
if [ ! -e "$_certs_dest_dir" ]; then
    mkdir -p "$_certs_dest_dir"
fi


info "Create directory '$_certs_data_dir' for storing certificates."
if [ ! -e "$_certs_data_dir" ]; then
    mkdir -p "$_certs_data_dir"
fi

info "Create directories for ftpes for storing certificates."
if [ ! -e "$_ftpes_cert_dir_vsftpd" ]; then
    mkdir -p "$_ftpes_cert_dir_vsftpd"
fi

if [ ! -e "$_ftpes_cert_dir_CA" ]; then
    mkdir -p "$_ftpes_cert_dir_CA"
fi

info "Copy xml files to created directory: $_certs_dest_dir"
cp $_certs_source_dir/$_ftpes_req_file $_certs_dest_dir

resolve_cm_vip_and_copy_cert_for_smrsweb
$SYSTEMCTL daemon-reload

update_selinux_permissions
copy_sshd_config
copy_ssh_config

info "Configuring cgroups"
${SMRS_RESOURCES_PATH}/cgroups/configure_cgroups.sh

info "filetransferandaccountservice postinstall completed."

exit 0