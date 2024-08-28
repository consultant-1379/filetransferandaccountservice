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
# standard linux commands
###########################################################################
_ECHO="/bin/echo"
_MKDIR="/bin/mkdir -p"
_GREP="/bin/grep"

###########################################################################
# script properties
###########################################################################
# sftpps --> SFTP Process status

BASENAME=/bin/basename
SCRIPT_NAME="${BASENAME} ${0}"
HOSTNAME=$(hostname)
DATE=$(date +%d%m%y)
DATE_TIME=$(date +%y%m%d:%H:%M)
SMRS_DDC_PATH=/home/smrs/smrsroot/sftppslog/$DATE/"$HOSTNAME"
SMRS_DDC_FILE=sftpProcessStatus.log
SMRS_DDC_FILE_PATH=$SMRS_DDC_PATH/$SMRS_DDC_FILE
SSHD_PIDFILE=/var/run/sshd.pid
SECURE_DATE_FORMAT=$(date '+%b %e %H:%M' -d '1 min ago')
SECURE_LOG=/var/log/secure
SFTP_SESSION_OPEN="session opened for user"
ACTIVE_SFTP_COUNT_TAG="ACTIVE_SFTP_COUNT"
SFTP_SPAWN_COUNT_TAG="SFTP_SPAWN_COUNT"
SFTP_CONNECTIONS_TAG="SMRS.SFTP_CONNECTIONS"

SPACE=""
BORDER="------------------------------------------------------------------------------------------------------"

############################################################################
# This function will print an error message to /var/log/messages
# Arguments:
#       $1 - Message
# Return: None
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
# This function will allow DDC to collect the data to plot various
# graphs in DDP.
# Arguments:
#       $1 - Active SFTP count
#       $2 - SFTP spawned per minute count
# Return: None
###########################################################################
ddc_info_log()
{
    logger  -p local2.info -t DDCDATA[$($SCRIPT_NAME)] $SFTP_CONNECTIONS_TAG {\"$ACTIVE_SFTP_COUNT_TAG\":$1, \"$SFTP_SPAWN_COUNT_TAG\":$2}
}

###########################################################################
# Evaluate number of sshd processes
#
###########################################################################
_calculate_active_sshd_process_count () {

    read ppid < "$SSHD_PIDFILE"

    ACTIVE_SSHD_PROCESS_COUNT=$(/bin/ps -eo pid,ppid,time,pcpu,etime,pmem,rss,uid,user,cmd  | $_GREP ${ppid}  | $_GREP -v grep | $_GREP -v cloud-user | $_GREP -v "/usr/sbin/sshd" | wc -l )
    TOTAL_VALUE="Total = $ACTIVE_SSHD_PROCESS_COUNT"
}

###########################################################################
# Evaluate the number of ssh sessions opened by clients in the
# previous minute.
# Arguments: None
# Return: None
###########################################################################
_calculate_ssh_session_spawn_count()
{
    SFTP_COUNT=$($_GREP "$SECURE_DATE_FORMAT" $SECURE_LOG | $_GREP "$SFTP_SESSION_OPEN" | $_GREP -v "cloud-user\|jboss_user" -c)
    if [ $? == 2 ]; then
        error "Grep failed for the date format : $SECURE_DATE_FORMAT, log path : $SECURE_LOG and \"$SFTP_SESSION_OPEN\""
        SFTP_COUNT=""
    fi
    SFTP_SPAWN_COUNT="SFTP_SPAWN_COUNT = $SFTP_COUNT"
}

##########################################################################
#Update the log file
#
##########################################################################
_update_sftp_ps_ddc_data() {
     if [ ! -d "$1" ]; then
         info "Creating directory $1"
         $_MKDIR "$1"
     fi
     echo $SPACE >> $2
     echo $DATE_TIME >> $2
     echo $TOTAL_VALUE >> $2
     echo $SFTP_SPAWN_COUNT >> $2
     echo "PID    PPID  TIME    %CPU    ELAPSED  %MEM  RSS    UID USER     CMD" >> $2
     echo $BORDER >> $2
     /bin/ps -eo pid,ppid,time,pcpu,etime,pmem,rss,uid,user,cmd | $_GREP "sshd" | $_GREP -v grep >> $2
}

_calculate_active_sshd_process_count
_calculate_ssh_session_spawn_count
ddc_info_log $ACTIVE_SSHD_PROCESS_COUNT $SFTP_COUNT
_update_sftp_ps_ddc_data $SMRS_DDC_PATH $SMRS_DDC_FILE_PATH

exit 0
