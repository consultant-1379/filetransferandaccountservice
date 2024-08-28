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
SERVICE=/sbin/service
SYSTEMCTL=/bin/systemctl

# GLOBAL VARIABLES
VSFTPD_CONF_LOCATION=/etc/vsftpd
SCRIPT_NAME="${BASENAME} ${0}"
LOG_TAG="UNSECURED_FTP_DISABLE"
FTP_BACKUP_LOCATION=/ericsson/tor/data/smrs_unsecured_ftp

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

remove_ftpconf_files(){
    info "Removing unsecure ftp conf files...."

    rm -f ${VSFTPD_CONF_LOCATION}/ftp.conf
    rm -f ${VSFTPD_CONF_LOCATION}/ftp_ipv6.conf
    rm -f ${FTP_BACKUP_LOCATION}/ftp.conf
    rm -f ${FTP_BACKUP_LOCATION}/ftp_ipv6.conf

    ${SYSTEMCTL} stop vsftpd.service
    ${SYSTEMCTL} disable vsftpd.service
    ${SYSTEMCTL} stop vsftpd.target
    ${SYSTEMCTL} disable vsftpd@ftp.service
    ${SYSTEMCTL} disable vsftpd@ftp_ipv6.service
    ${SYSTEMCTL} disable vsftpd.target
    ${SYSTEMCTL} enable vsftpd.target
    ${SYSTEMCTL} start vsftpd.target
}

#############
# MAIN PROGRAM
#############
remove_ftpconf_files

