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
SCRIPT_NAME="${BASENAME} ${0}"
MKDIR="/bin/mkdir -p"
CHMOD="/bin/chmod"
LS="/bin/ls -ld"
CHMODR="/bin/chmod -R"
CHOWNR="/bin/chown -R"
CHOWN=/bin/chown
ECHO="echo -e"
EGREP=/bin/egrep
GREP=/bin/grep
MOUNT=/bin/mount

# GLOBAL VARIABLES
SCRIPT_NAME="${BASENAME} ${0}"
LOG_TAG="SMRS_Bind_Mount"
SMRS_ROOT="/ericsson/tor/smrs"
NUMBER_OF_PM_PUSH_FILE_SYSTEMS=$(find /ericsson/ -maxdepth 1 -name "pmic*" -type d | wc -l)
SGID_PERMISSIONS=2775
PERMISSIONS=755
GROUP_PERMISSIONS=7
ROOT_USER="root"
SMRS_GROUP="mm-smrsusers"
JBOSS_USER="jboss_user"
SGID_PERMISSIONS_TEXT="drwxrwsr-x+"

# SMRS DIRS
SMRS_HOME_LOCATION="/home/smrs"
SMRS_ROOT_DIRECTORY="$SMRS_HOME_LOCATION/smrsroot"
SMRS_ROOT_DIRECTORY_ML="$SMRS_HOME_LOCATION/MINI-LINK"
SMRS_ROOT_DIRECTORY_ML_PM_PUSH_="$SMRS_ROOT_DIRECTORY_ML/pm_push_"

#MINI-LINK-Indoor DIRS
MINI_LINK_INDOOR_HOME_LOCATION="$SMRS_HOME_LOCATION/MINI-LINK/MINI-LINK-Indoor"

#PM_PUSHDIR
PM_PUSH_TMP="tmp_push"
PM_PUSH_ML_TMP="tmp_push_ml"

#ULSA DIR
ULSA_HOME_LOCATION="$SMRS_ROOT_DIRECTORY/ul_spectrum_files"
ULSA_NBI="/ericsson/ul_spectrum_files"
ULSA_TMP_DIRECTORY="$ULSA_NBI/tmp"

if [ -z "$STARTUP_WAIT" ]; then
    STARTUP_WAIT=600
fi


#////////////////////////////////////////////////////////////////
# This function will print an error message to /var/log/messages
# Arguments:
#       $1 - Message
# Return: 0
#//////////////////////////////////////////////////////////////
error()
{
    logger  -t ${LOG_TAG} -p user.err "ERROR ( ${SCRIPT_NAME} ): $1"
}

#//////////////////////////////////////////////////////////////
# This function will print an info message to /var/log/messages
# Arguments:
#       $1 - Message
# Return: 0
#/////////////////////////////////////////////////////////////
info()
{
    logger  -t ${LOG_TAG} -p user.notice "INFORMATION ( ${SCRIPT_NAME} ): $1"
}


#######################################
# Action :
#   __create_bind_mount
#  This function will create the bind mount and update the /etc/fstab
# Globals :
#   None
# Arguments:
#   None
# Returns:
#
#######################################
__create_bind_mount()
{
    if ${MOUNT} | ${GREP} -q "${SMRS_HOME_LOCATION}"; then
        info "${SMRS_HOME_LOCATION} already mounted"
    else
        info "Creating the bind mount between ${SMRS_ROOT} and ${SMRS_HOME_LOCATION}..."

        ${EGREP} -q '^/ericsson/tor/smrs.*/home/smrs.*bind,_netdev,x-systemd.requires=/ericsson/tor/smrs' /etc/fstab

        if [ $? -ne 0 ]; then
            [ -d ${SMRS_ROOT} ] && [ -d ${SMRS_HOME_LOCATION} ] && ${ECHO} '/ericsson/tor/smrs\t/home/smrs\tnone\tbind,_netdev,x-systemd.requires=/ericsson/tor/smrs' >> /etc/fstab
        fi

        ${MOUNT} | ${GREP} -q '^on /home/smrs '

        if [ $? -ne 0 ]; then
            ${MOUNT} ${SMRS_HOME_LOCATION}
        fi

        if [ $? -eq 0 ]; then
            info "Creation of bind mount ${SMRS_HOME_LOCATION} was successful"
        else
            error "Creation of bind mount ${SMRS_HOME_LOCATION} failed"
        fi
    fi
}

#######################################
# Action :
#   __create_ulsa_bind_mount
#  This function will create the bind mount and update the /etc/fstab
# Globals :
#   None
# Arguments:
#   None
# Returns:
#
#######################################
__create_ulsa_bind_mount()
{
    if [ ! -d "$ULSA_TMP_DIRECTORY" ]; then
        info "Creating directory $ULSA_TMP_DIRECTORY"
        $MKDIR "$ULSA_TMP_DIRECTORY"
    fi

    #Changing ownership to JBOSS_USER for ULSA_TMP_DIRECTORY
    if [[ "$($LS $ULSA_TMP_DIRECTORY | awk '{print $4}')" != "$SMRS_GROUP" || "$($LS $ULSA_TMP_DIRECTORY | awk '{print $3}')" != "$JBOSS_USER" ]]; then
        info "Changing User and Group ownership of $ULSA_TMP_DIRECTORY"
        $CHOWNR $JBOSS_USER:$SMRS_GROUP $ULSA_TMP_DIRECTORY || error "Unable to change ownership to $JBOSS_USER for $ULSA_TMP_DIRECTORY"
    fi

    #Setting permissions for ULSA_TMP_DIRECTORY
    if [ "$($LS $ULSA_TMP_DIRECTORY | awk '{print $1}')" != "$SGID_PERMISSIONS_TEXT" ]; then
        info "Setting the SGID permission for $ULSA_TMP_DIRECTORY"
        $CHMODR $SGID_PERMISSIONS $ULSA_TMP_DIRECTORY || error "Unable to set permissions to $SGID_PERMISSIONS for $ULSA_TMP_DIRECTORY"
    fi

    if ${MOUNT} | ${GREP} -q "${ULSA_HOME_LOCATION}"; then
        info "${ULSA_HOME_LOCATION} already mounted"
    else
        info "Creating the bind mount between ${ULSA_TMP_DIRECTORY} and ${ULSA_HOME_LOCATION}..."

        ${EGREP} -q '^/ericsson/ul_spectrum_files/tmp.*/home/smrs/smrsroot/ul_spectrum_files.*bind,_netdev,x-systemd.requires=/ericsson/ul_spectrum_files' /etc/fstab

        if [ $? -ne 0 ]; then
            [ -d ${ULSA_TMP_DIRECTORY} ] && [ -d ${ULSA_HOME_LOCATION} ] && ${ECHO} '/ericsson/ul_spectrum_files/tmp\t/home/smrs/smrsroot/ul_spectrum_files\tnone\tbind,_netdev,x-systemd.requires=/ericsson/ul_spectrum_files' >> /etc/fstab
        fi

        ${MOUNT} | ${GREP} -q '^on /home/smrs/smrsroot/ul_spectrum_files'

        if [ $? -ne 0 ]; then
            ${MOUNT} ${ULSA_HOME_LOCATION}
        fi

        if [ $? -eq 0 ]; then
            info "Creation of bind mount ${ULSA_HOME_LOCATION} was successful"
        else
            error "Creation of bind mount ${ULSA_HOME_LOCATION} failed"
        fi
    fi
}

######################################
# Action :
#   __create_pm_push_bind_mount
#  This function will create the bind mount and update the /etc/fstab
# Globals :
#   None
# Arguments:
#   $1 - Total number of PM_PUSH file systems
#   $2 - tmp directory under mount point
#   $3 - Root Directory, SMRS Root and MINI-LINK-Indoor root directory
# Returns:
#
#####################################

__create_pm_push_bind_mount()
{
    for pm_push_fs_index in `eval echo {1..$1}`
    do
        PMIC_ROOT="/ericsson/pmic$pm_push_fs_index"
        PM_PUSH_ROOT="/ericsson/pmic$pm_push_fs_index/$2"
        PM_PUSH_HOME_LOCATION="$3/pm_push_$pm_push_fs_index"

        $MKDIR "$PM_PUSH_ROOT"
        $MKDIR "$PM_PUSH_HOME_LOCATION"

        if ${MOUNT} | ${GREP} -q "${PM_PUSH_HOME_LOCATION}"; then
            info "${PM_PUSH_HOME_LOCATION} already mounted"
        else
            ${EGREP} -q '^$PM_PUSH_ROOT.*$PM_PUSH_HOME_LOCATION.*bind,_netdev,x-systemd.requires=$PMIC_ROOT' /etc/fstab

            if [ $? -ne 0 ]; then
                [ -d ${PM_PUSH_ROOT} ] && [ -d ${PM_PUSH_HOME_LOCATION} ] && ${ECHO} "$PM_PUSH_ROOT\t$PM_PUSH_HOME_LOCATION\tnone\tbind,_netdev,x-systemd.requires=$PMIC_ROOT" >> /etc/fstab
            fi

            ${MOUNT} | ${GREP} -q '^on $PM_PUSH_HOME_LOCATION'

            if [ $? -ne 0 ]; then
                ${MOUNT} ${PM_PUSH_HOME_LOCATION}
            fi

            if [ $? -eq 0 ]; then
                info "Creation of bind mount ${PM_PUSH_HOME_LOCATION} to ${PM_PUSH_ROOT} was successful"
            else
                error "Creation of bind mount ${PM_PUSH_HOME_LOCATION} to ${PM_PUSH_ROOT} failed"
            fi
        fi
    done
}


#######################################
# Action :
#   Configure the SMRS file shares
# Globals :
#   None
# Arguments:
#   None
# Returns:
#
#######################################
__configure_smrs_fs()
{
    $MKDIR "$SMRS_HOME_LOCATION" "$MINI_LINK_INDOOR_HOME_LOCATION"

    info "Creating home dir share"

    __create_bind_mount
    __create_pm_push_bind_mount $NUMBER_OF_PM_PUSH_FILE_SYSTEMS "$PM_PUSH_TMP" "$SMRS_ROOT_DIRECTORY"
    __create_pm_push_bind_mount $NUMBER_OF_PM_PUSH_FILE_SYSTEMS "$PM_PUSH_ML_TMP" "$SMRS_ROOT_DIRECTORY_ML"
    __configure_home_fs $SMRS_HOME_LOCATION
    __configure_home_fs $SMRS_ROOT_DIRECTORY_ML

    __configure_mini_link_pm_push_fs
    __configure_mini_link_indoor_fs


    $MKDIR "$ULSA_HOME_LOCATION"
    __create_ulsa_bind_mount

    info "SMRS File Share configuration completed"
}

######################################
__configure_mini_link_pm_push_fs()
{
    info "MINI-LINK PM_PUSH SMRS File Share configuration started"

    for pm_push_index in `eval echo {1..$NUMBER_OF_PM_PUSH_FILE_SYSTEMS}`
    do
       PM_PUSH_DIRECTORY="$SMRS_ROOT_DIRECTORY_ML_PM_PUSH_$pm_push_index"

       info " Applying permissons and changing ownership for $PM_PUSH_DIRECTORY directory"

       __configure_home_fs $PM_PUSH_DIRECTORY
    done

    info "MINI-LINK PM_PUSH SMRS File Share configuration completed"
}

######################################
__configure_mini_link_indoor_fs()
{
    info "MINI-LINK-Indoor SMRS File Share configuration started"

    __configure_home_fs $MINI_LINK_INDOOR_HOME_LOCATION

    info "MINI-LINK-Indoor SMRS File Share configuration completed"
}

######################################
__configure_home_fs()
{
    info "Applying permissions to $1 directories"

    $CHOWN $ROOT_USER:$ROOT_USER "$1" || error "Unable to change the ownership of $1"
    $CHMOD $PERMISSIONS "$1" || error "Unable to change permissions to $PERMISSIONS for $1"
}

# Action :
#   main program
# Globals :
#   None
# Arguments:
#   None
# Returns:
#
#######################################

__configure_smrs_fs

exit 0
