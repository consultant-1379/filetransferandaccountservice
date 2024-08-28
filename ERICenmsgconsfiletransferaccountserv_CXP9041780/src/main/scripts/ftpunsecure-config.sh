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

# GLOBAL VARIABLES
SCRIPT_NAME="${BASENAME} ${0}"
FTP_BACKUP_LOCATION=/ericsson/tor/data/smrs_unsecured_ftp
LOG_TAG="FTPUNSECURE_POST_INSTALL"
ENABLE_SCRIPT_PATH=/opt/ericsson/ERICenmsgconsfiletransferaccountserv_CXP9041780

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

check_ftpconf_files_exists(){
    info "checking existence of unsecured ftp conf files...."

    if [ -f  ${FTP_BACKUP_LOCATION}/ftp.conf ] && [ -f  ${FTP_BACKUP_LOCATION}/ftp_ipv6.conf ]; then
        if [ -f ${ENABLE_SCRIPT_PATH}/enable_unsecured_ftp.sh ]; then
            ${ENABLE_SCRIPT_PATH}/enable_unsecured_ftp.sh
        else
            info "enable_unsecured_ftp.sh script file doesn't exists in path : ${ENABLE_SCRIPT_PATH}"
        fi
    else
        info "Backup files for unsecured ftp doesn't exists in path : ${FTP_BACKUP_LOCATION}, so not enabling the unsecured ftp"
    fi
}

#############
# MAIN PROGRAM
#############
check_ftpconf_files_exists
