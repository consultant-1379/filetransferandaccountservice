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

###########################################################################
# standard linux commands and script properties
#
###########################################################################
BASENAME=/bin/basename
SCRIPT_NAME="${BASENAME} ${0}"

PERL="/usr/bin/perl"
MAX_CRON_SLEEP_INTERVAL=3
POST_INSTALL_SCRIPT_DIR="/ericsson/3pp/jboss/bin/post-start/"
SFTP_DDC_DATA_COLLECTOR_NAME="sftp_ddc_data_collector.sh"
SFTP_DDC_DATA_COLLECTOR_PATH=$POST_INSTALL_SCRIPT_DIR$SFTP_DDC_DATA_COLLECTOR_NAME


############################################################################
# This function will print an error message to /var/log/messages
# Arguments:
#       $1 - Message
# Return: 0
###########################################################################
error()
{
    logger  -t ${LOG_TAG} -p user.err "ERROR ( ${SCRIPT_NAME} ): $1"
}
info()
{
    logger  -t ${LOG_TAG} -p user.notice "INFORMATION ( ${SCRIPT_NAME} ): $1"
}

############################################################################
#Verify if cron service is already running.If not, attempt a manual restart of the service
############################################################################

__cron_health_check() {

service crond status
if [ $? -ne 0 ];then
    error "cron service is not running, trying to bring it up"
    service crond restart
fi
}

##############################################################################
#Verify if sftp ddc data collector script is already run as part of a cron task and the standard output and error are
#redirected to /dev/null
##############################################################################

__verify_sftp_ddc_data_collector_entry_in_cron() {

info "Waiting ${MAX_CRON_SLEEP_INTERVAL} seconds for cron to come up and Running(In case of an attempted restart)"
sleep ${MAX_CRON_SLEEP_INTERVAL}
check=`crontab -l | $PERL -nle 'print if m{sftp_ddc_data_collector.sh >/dev/null}'`
if [ -z "${check}" ]
then
    crontab -l | grep -v "${SFTP_DDC_DATA_COLLECTOR_PATH}"  | crontab -
fi

}

###################################################################
#Add a new cron task, if no entries are found, which collect the sftp process data for ddc [scheduled for every 2 minute]
###################################################################

__insert_sftp_ddc_data_collector_entry_to_cron() {

check=`crontab -l | $PERL -nle 'print if m{sftp_ddc_data_collector.sh >/dev/null}'`
if [ -z "${check}" ]
then
    chmod +x ${SFTP_DDC_DATA_COLLECTOR_PATH}
    (crontab -l 2>/dev/null; echo "*/1 * * * * ${SFTP_DDC_DATA_COLLECTOR_PATH} >/dev/null 2>&1") | crontab - >/dev/null 2>&1
    info "sftp ddc data collector is added in cron"
else
    info "sftp ddc data collector is already being monitored in cron"
fi
}

#########################
# Main script starts here
#########################

__cron_health_check
__verify_sftp_ddc_data_collector_entry_in_cron
__insert_sftp_ddc_data_collector_entry_to_cron

exit 0