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
GROUPADD=/usr/sbin/groupadd
USERMOD=/usr/sbin/usermod


# GLOBAL VARIABLES

SCRIPT_NAME=`${BASENAME} ${0}`
LOG_TAG="SMRS_PRE_INSTALL"
SMRS_GROUP="mm-smrsusers"
SU_GROUP="mm-su-read-only"


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

#//////////////////////////////////////////////////////////////
# This function will create the mm-smrsusers group
# Arguments:
#       None
# Return: 0
#/////////////////////////////////////////////////////////////
create_smrs_group()
{
    info "Creating the ${SMRS_GROUP} group..."

    ${GROUPADD} -g 5000 ${SMRS_GROUP} > /dev/null 2>&1
    local _was_groupadd_success_=$?

    if [ ${_was_groupadd_success_} -eq 0 ]; then
          info "Creation of ${SMRS_GROUP} group was successful"
    elif [ ${_was_groupadd_success_} -eq 9 ]; then
        info "${SMRS_GROUP} already exists"
    else
        error "Creation of ${SMRS_GROUP} group failed"
    fi
}

#//////////////////////////////////////////////////////////////
# This function will create the mm-su-read-only group
# Arguments:
#       None
# Return: 0
#/////////////////////////////////////////////////////////////
create_support_unit__group()
{
    info "Creating the ${SU_GROUP} group..."

    ${GROUPADD} -g 5050 ${SU_GROUP} > /dev/null 2>&1
    local _was_groupadd_success_=$?

    if [ ${_was_groupadd_success_} -eq 0 ]; then
            info "Creation of ${SU_GROUP} group was successful"
    elif [ ${_was_groupadd_success_} -eq 9 ]; then
            info "${SU_GROUP} already exists"
    else
            error "Creation of ${SU_GROUP} group failed"
    fi
}

#//////////////////////////////////////////////////////////////
# This function will add the jboss_user to the mm-su-read-only group so SupportUnit can read from the SMRS filesystem
# Arguments:
#       None
# Return: 0
#/////////////////////////////////////////////////////////////
add_jboss_user_to_support_unit_group()
{
    info "Adding jboss_user to the ${SU_GROUP} group..."

    ${USERMOD} -a -G ${SU_GROUP} jboss_user > /dev/null 2>&1

    if [ $? -eq 0 ]; then
            info "Addition of jboss_user to the ${SU_GROUP} group was successful"
    else
            error "Addition of jboss_user to the ${SU_GROUP} group failed"
    fi
}

#//////////////////////////////////////////////////////////////
# This function will add the jboss_user to the mm-smrsusers group so DE's can write to the SMRS filesystem
# Arguments:
#       None
# Return: 0
#/////////////////////////////////////////////////////////////
add_jboss_user_to_smrs_group()
{
    info "Adding jboss_user to the ${SMRS_GROUP} group..."

    ${USERMOD} -a -G ${SMRS_GROUP} jboss_user > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        info "Addition of jboss_user to the ${SMRS_GROUP} group was successful"
    else
        error "Addition of jboss_user to the ${SMRS_GROUP} group failed"
    fi
}

#############
# MAIN PROGRAM
#############
create_smrs_group
add_jboss_user_to_smrs_group
create_support_unit__group
add_jboss_user_to_support_unit_group

exit 0