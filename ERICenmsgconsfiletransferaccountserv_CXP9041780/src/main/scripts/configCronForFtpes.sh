#!/bin/bash

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

readonly SCRIPT_PATH="/etc/vsftpd/scripts/configTlsPropForFtpes.sh"
readonly PERL="/usr/bin/perl"

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

__insert_config_ftpes_entry_to_cron() {

check=`crontab -l | $PERL -nle 'print if m{configTlsPropForFtpes.sh >/dev/null}'`
if [ -z "${check}" ]
then
     chmod +x ${SCRIPT_PATH}
     (crontab -l 2>/dev/null; echo "* * * * * ${SCRIPT_PATH} >/dev/null 2>&1") | crontab - >/dev/null 2>&1
     logger "[${SCRIPT_PATH}] service has been added in cron"
else
     logger "[${SCRIPT_PATH}] service is already being monitored in cron"
fi

}

__insert_config_ftpes_entry_to_cron
exit 0;
