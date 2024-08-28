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

# UTILITIES
BASENAME=/bin/basename
SCRIPT_NAME=$(${BASENAME} "${0}")
CP="/bin/cp -r"
MV="/bin/mv -f"
CHOWNR="/bin/chown -R"
CHMODR="/bin/chmod -R"
MKDIRP="/bin/mkdir -p"
RMRF="/bin/rm -rf"
SOFT_LINK="ln -s"
CD="cd"
TIMESTAMP=$(date +%F:%T)

# GLOBAL VARIABLES
SMRS_LRAN_DIR="/home/smrs/lran"
SMRS_ROOT_DIR="/home/smrs/smrsroot"
SMRS_HOME_DIR="/home/smrs"
JBOSS_USER="jboss_user"
SMRS_GROUP="mm-smrsusers"
LOG="/var/log/messages"
SMRS_LRAN_DIR_TIMESTAMP="/home/smrs/lran_$TIMESTAMP"

#////////////////////////////////////////////////////////////////
# This function will print an error message to /var/log/messages
# Arguments:
#       $1 - Message
# Return: 0
#//////////////////////////////////////////////////////////////
error()
{
    logger  -t "${TIMESTAMP}" -p user.err "ERROR ( ${SCRIPT_NAME} ): $1"
}

#//////////////////////////////////////////////////////////////
# This function will print an info message to /var/log/messages
# Arguments:
#       $1 - Message
# Return: 0
#/////////////////////////////////////////////////////////////
info()
{
    logger  -t "${TIMESTAMP}" -p user.notice "INFORMATION ( ${SCRIPT_NAME} ): $1"
}

#////////////////////////////////////////////////////////////////
# This function will print an error message to /var/log/messages
# Arguments:
#       $1 - Message
# Return: 0
#//////////////////////////////////////////////////////////////
bailout()
{
    info "${1}"
    error "ERROR: Script Failed please check log file: $LOG"
    rollout
    exit 1
}

#/////////////////////////////////////////////////////////////////////////////////////////
##This function will rollout all the data from backup to the original
#///////////////////////////////////////////////////////////////////////////////////////
rollout()
{
    error "Rolling out the migration"
    [[ -d "$SMRS_LRAN_DIR_TIMESTAMP" ]] && {
      $MV "$SMRS_LRAN_DIR_TIMESTAMP"  "$SMRS_LRAN_DIR"
    }
}

#/////////////////////////////////////////////////////////////////////////////////////////
#
#This function will migrate all the data from /home/smrs/lran to /home/smrs/smrsroot/
#also creates the soft link between them
#///////////////////////////////////////////////////////////////////////////////////////
__migrate_smrs_fs ()
{
    info "Checking $SMRS_LRAN_DIR existence"
    if [ ! -L $SMRS_LRAN_DIR ]; then
        info "Backing up $SMRS_LRAN_DIR directory"
        $MKDIRP "$SMRS_LRAN_DIR_TIMESTAMP" || bailout "Failed to create $SMRS_LRAN_DIR_TIMESTAMP with exit code: $?"
        $MV $SMRS_LRAN_DIR/* "$SMRS_LRAN_DIR_TIMESTAMP/" || bailout "Failed to take backup $SMRS_LRAN_DIR with exit code: $?"
        info "Migrating $SMRS_LRAN_DIR to $SMRS_ROOT_DIR"
        $CP "$SMRS_LRAN_DIR_TIMESTAMP"/* "$SMRS_ROOT_DIR"/ || bailout "Failed to move $SMRS_LRAN_DIR to $SMRS_ROOT_DIR with exit code: $?"
        $CHOWNR $JBOSS_USER:$SMRS_GROUP $SMRS_ROOT_DIR || bailout "Failed to change ownership of $SMRS_ROOT_DIR with exit code: $?"
        $CHMODR 2775 $SMRS_ROOT_DIR || bailout "Failed to set guid to $SMRS_ROOT_DIR with exit code: $?"
        $RMRF $SMRS_LRAN_DIR || bailout "Failed to remove directory $SMRS_LRAN_DIR with exit code: $?"
        $CD $SMRS_HOME_DIR; $SOFT_LINK ./smrsroot lran || bailout "Unable to create soft link between $SMRS_ROOT_DIR and $SMRS_LRAN_DIR, exit code : $?"
    else
        info "Migration of SMRS FS is already done"
        exit 0
    fi
}

__migrate_smrs_fs

info "Migration of SMRS FS is Successful"
exit 0