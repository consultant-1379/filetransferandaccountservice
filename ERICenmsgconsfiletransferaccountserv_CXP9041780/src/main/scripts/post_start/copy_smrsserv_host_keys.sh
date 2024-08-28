#!/bin/bash

###########################################################################
# COPYRIGHT Ericsson 2022
#
# The copyright to the computer program(s) herein is the property of
# Ericsson Inc. The programs may be used and/or copied only with written
# permission from Ericsson Inc. or in accordance with the terms and
# conditions stipulated in the agreement/contract under which the
# program(s) have been supplied.
#
# This script requires bash 4 or above
#
##########################################################################

info()
{
    logger -s -t ${LOG_TAG} -p user.notice "INFORMATION ( ${SCRIPT_NAME} ): $1"
}

smrs_host_key_folder="$(ls /ericsson/tor/data/vm-host-keys/ | grep smrs | head -n 1)"

if [ -z "$smrs_host_key_folder" ]
then
    info "Smrsserv host keys folder does not exist."
else
    info "Smrsserv host keys folder exists. Copying keys"
    scp -p /ericsson/tor/data/vm-host-keys/"$smrs_host_key_folder"/ssh_host_* /ericsson/tor/data/vm-host-keys/"$(hostname)"/
    scp -p /ericsson/tor/data/vm-host-keys/"$smrs_host_key_folder"/ssh_host_* /etc/ssh/
fi
