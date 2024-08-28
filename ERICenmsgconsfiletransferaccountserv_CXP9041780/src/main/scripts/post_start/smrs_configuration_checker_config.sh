#!/bin/bash

###########################################################################
# COPYRIGHT Ericsson 2022
#
# The copyright to the computer program(s) herein is the property of
# Ericsson Inc. The programs may be used and/or copied only with written
# permission from Ericsson Inc. or in accordance with the terms and
# conditions stipulated in the agreement/contract under which the
# program(s) have been supplied.
###########################################################################

# standard linux commands and script properties
BASENAME=/bin/basename
SCRIPT_NAME="${BASENAME} ${0}"

PERL="/usr/bin/perl"
MAX_CRON_SLEEP_INTERVAL=3
POST_INSTALL_SCRIPT_DIR="/ericsson/3pp/jboss/bin/post-start/"
SMRS_CONFIGURATION_CHECK_NAME="smrs_configuration_checker.sh"
SMRS_CONFIGURATION_CHECK_PATH=$POST_INSTALL_SCRIPT_DIR$SMRS_CONFIGURATION_CHECK_NAME
SFTP_INSTRUMENTATION_DATA_COLLECTOR_PATH="/ericsson/3pp/jboss/bin/sftp_instrumentation_data_collector.sh"
INSTRUMENTATION_HOUSEKEEPING_CHECK_PATH="/ericsson/3pp/jboss/bin/instrumentation_housekeeping.sh"

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
#//////////////////////////////////////////////////////////////
# This function will print an info message to /var/log/messages
# Arguments:
#       $1 - Message
# Return: 0
#//////////////////////////////////////////////////////////////
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
#Verify if smrs configuration checker script is already run as part of a cron task and the standard output and error are
#redirected to /dev/null
##############################################################################

__verify_smrs_configuration_checker_entry_in_cron() {

    info "Waiting ${MAX_CRON_SLEEP_INTERVAL} seconds for cron to come up and Running(In case of an attempted restart)"
    sleep ${MAX_CRON_SLEEP_INTERVAL}
    check=`crontab -l | $PERL -nle 'print if m{smrs_configuration_checker.sh >/dev/null}'`
    if [ -z "${check}" ]
    then
        crontab -l | grep -v "${SMRS_CONFIGURATION_CHECK_PATH}"  | crontab -
    fi
}

###################################################################
#Add a new cron task, to check smrs fs configuration [scheduled for every 5 minutes, change this cron expression in case schedule differs]
###################################################################

__insert_smrs_configuration_checker_entry_to_cron() {

    check=`crontab -l | $PERL -nle 'print if m{smrs_configuration_checker.sh >/dev/null}'`
    if [ -z "${check}" ]
    then
        chmod +x ${SMRS_CONFIGURATION_CHECK_PATH}
        (crontab -l 2>/dev/null; echo "*/5 * * * * ${SMRS_CONFIGURATION_CHECK_PATH} >/dev/null 2>&1") | crontab - >/dev/null 2>&1
        info "sftp configuration checker is added in cron"
    else
        info "sftp configuration checker is already being monitored in cron"
    fi
}

###################################################################
#Add a new cron task, to check sftp instrumentation data collector [scheduled for every 1 minute, change this cron expression in case schedule differs]
###################################################################


__insert_sftp_instrumentation_data_collector_entry_in_cron() {

check=`crontab -l | $PERL -nle 'print if m{sftp_instrumentation_data_collector.sh >/dev/null}'`
if [ -z "${check}" ]
then
     chmod +x ${SFTP_INSTRUMENTATION_DATA_COLLECTOR_PATH}
     (crontab -l 2>/dev/null; echo "*/1 * * * * ${SFTP_INSTRUMENTATION_DATA_COLLECTOR_PATH} >/dev/null 2>&1") | crontab - >/dev/null 2>&1
     info "sftp instrumentation data collector is added in cron"
else
     info "sftp instrumentation data collector is already being monitored in cron"
fi

}

##############################################################################
#This function is used to restart rsyslog service
##############################################################################
__rsyslog_restart() {

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

##############################################################################
#This function is used to for Housekeeping Instrumentation Logs
##############################################################################
__insert_instrumentation_housekeeping_checker_entry_to_cron() {

check=`crontab -l | $PERL -nle 'print if m{instrumentation_housekeeping.sh >/dev/null}'`
if [ -z "${check}" ]
then
     chmod +x ${INSTRUMENTATION_HOUSEKEEPING_CHECK_PATH}
     (crontab -l 2>/dev/null; echo "0 13 * * * ${INSTRUMENTATION_HOUSEKEEPING_CHECK_PATH} >/dev/null 2>&1") | crontab - >/dev/null 2>&1
     info "instrumentation housekeeping is added in cron"
else
     info "instrumentation housekeeping is already being monitored in cron"
fi

}

###################################################################
#Main Program
#Adding new cron task, to check SMRS directories configuration post jboss is started
###################################################################

__rsyslog_restart
__cron_health_check
__verify_smrs_configuration_checker_entry_in_cron
__insert_smrs_configuration_checker_entry_to_cron
__insert_instrumentation_housekeeping_checker_entry_to_cron
__insert_sftp_instrumentation_data_collector_entry_in_cron

exit 0