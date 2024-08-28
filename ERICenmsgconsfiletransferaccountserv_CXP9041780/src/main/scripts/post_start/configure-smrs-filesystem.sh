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
GETENT=/usr/bin/getent
GREP=/bin/grep
MOUNT=/bin/mount
CAT=/bin/cat
AWK=/usr/bin/awk

# GLOBAL VARIABLES
SCRIPT_NAME="${BASENAME} ${0}"
LOG_TAG="Filetransferservice_Configuration"
SMRS_ROOT="/ericsson/tor/smrs"
NUMBER_OF_PM_PUSH_FILE_SYSTEMS=$(find /ericsson/ -maxdepth 1 -name "pmic*" -type d | wc -l)
SGID_PERMISSIONS=2775
PERMISSIONS=755
PERMISSIONS_SYMBOL="drwxr-xr-x+"
GROUP_PERMISSIONS=7
V4=false
GROUP_PERMISSIONS_V4=RWX
ROOT_USER="root"
SMRS_GROUP="mm-smrsusers"
SMRS_GID=$(${GETENT} group ${SMRS_GROUP} | ${AWK} -F ":" '{print $3}')
AMOS_GROUP="amos_users"
JBOSS_USER="jboss_user"
SETFACL="/usr/bin/setfacl"
SETFACLV4="/usr/bin/nfs4_setfacl"
GETFACL="/usr/bin/getfacl"
FILE_PERMISSIONS=664
SGID_PERMISSIONS_TEXT="drwxrwsr-x+"

# SMRS DIRS
SMRS_HOME_LOCATION="/home/smrs"
SMRS_ROOT_DIRECTORY="$SMRS_HOME_LOCATION/smrsroot"
SMRS_ROOT_DIRECTORY_ML="$SMRS_HOME_LOCATION/MINI-LINK"
SMRS_ROOT_DIRECTORY_WITH_NL="$SMRS_ROOT_DIRECTORY/nl"
SMRS_ROOT_DIRECTORY_WITH_NL_SUB="$SMRS_ROOT_DIRECTORY/nl/*"

#MINI-LINK-Indoor DIRS
MINI_LINK_INDOOR_HOME_LOCATION="$SMRS_HOME_LOCATION/MINI-LINK/MINI-LINK-Indoor"
MINI_LINK_INDOOR_SOFTWARE="$MINI_LINK_INDOOR_HOME_LOCATION/tn_system_release"
MINI_LINK_INDOOR_LICENSE="$MINI_LINK_INDOOR_HOME_LOCATION/tn_licenses"
MINI_LINK_INDOOR_BACKUP="$MINI_LINK_INDOOR_HOME_LOCATION/tn_backup_configuration"

#ORADIO Account DIRS
SOFTWARE_3PP="$SMRS_HOME_LOCATION/3ppsoftware"
ORADIO_SOFTWARE_LOCATION="$SOFTWARE_3PP/oradio"
#SUPPORT_UNIT Account constants
SUPPORT_UNIT_GROUP="mm-su-read-only"
SUPPORT_UNIT_LOCATION="$SOFTWARE_3PP/support_unit"
SUPPORT_UNIT_SOFTWARE_LOCATION="$SUPPORT_UNIT_LOCATION/software"
SUPPORT_UNIT_GID=5050
SU_GROUP_PERMISSIONS=5
SU_GROUP_PERMISSIONS_V4=RX

#UPGRADE_INDEPENDENCE DIR
UPGRADE_INDEPENDENCE_DIRECTORY="$SMRS_ROOT_DIRECTORY/upgrade_independence"

#PM_PUSHDIR
PM_PUSH_TMP="tmp_push"
PM_PUSH_ML_TMP="tmp_push_ml"
PM_DATA="tn_pm_data"
BULK_PM="PM"

#ULSA DIR
ULSA_HOME_LOCATION="$SMRS_ROOT_DIRECTORY/ul_spectrum_files"
ULSA_NBI="/ericsson/ul_spectrum_files"
ULSA_TMP_DIRECTORY="$ULSA_NBI/tmp"

if [ -z "$STARTUP_WAIT" ]; then
    STARTUP_WAIT=600
fi

if ${MOUNT} | ${GREP} "${SMRS_ROOT}" | ${GREP} -q vers=4; then
    V4=true
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
    $MKDIR "$SMRS_HOME_LOCATION" "$MINI_LINK_INDOOR_HOME_LOCATION" "$SOFTWARE_3PP"

    info "Creating home dir share"

    __configure_smrs_subdirectory_fs $SMRS_ROOT_DIRECTORY
    __configure_mini_link_indoor_fs
    __configure_smrs_subdirectory_fs $ORADIO_SOFTWARE_LOCATION
    __configure_support_unit_smrs_subdirectory_fs $SUPPORT_UNIT_LOCATION
    __configure_support_unit_smrs_subdirectory_fs $SUPPORT_UNIT_SOFTWARE_LOCATION
    __configure_pm_push_fs $NUMBER_OF_PM_PUSH_FILE_SYSTEMS $SMRS_ROOT_DIRECTORY
    __configure_pm_push_fs $NUMBER_OF_PM_PUSH_FILE_SYSTEMS $SMRS_ROOT_DIRECTORY_ML $PM_DATA
    __configure_smrs_subdirectory_fs_nl_sub $SMRS_ROOT_DIRECTORY_WITH_NL
    __configure_pm_push_fs $NUMBER_OF_PM_PUSH_FILE_SYSTEMS $SMRS_ROOT_DIRECTORY_ML $BULK_PM

    $MKDIR "$ULSA_HOME_LOCATION"
    __configure_smrs_subdirectory_ulsa_fs
    __configure_upgrade_independence_fs

    info "SMRS File Share configuration completed"
}

###########################################################################
# Action :
#   Apply permissions to directories
# Arguments:
#   -
# Returns:
###########################################################################
function __configure_smrs_subdirectory_ulsa_fs()
{
    info "Applying permissions to ulsa directory $ULSA_HOME_LOCATION"

    if [ ! -d "$ULSA_HOME_LOCATION" ]; then
        info "Creating directory $ULSA_HOME_LOCATION"
        $MKDIR "$ULSA_HOME_LOCATION" || error "Unable to create directory $ULSA_HOME_LOCATION"
    fi

    # Changing User JBOSS_USER and Group ULSA_HOME_LOCATION ownership
    if [[ "$($LS $ULSA_HOME_LOCATION | awk '{print $4}')" != "$SMRS_GROUP" && "$($LS $ULSA_HOME_LOCATION | awk '{print $3}')" != "$JBOSS_USER" ]]; then
        info "Changing User and Group ownership of $ULSA_HOME_LOCATION"
        $CHOWNR $JBOSS_USER:$SMRS_GROUP $ULSA_HOME_LOCATION || error "Unable to change ownership to $JBOSS_USER for $ULSA_HOME_LOCATION"
    fi

    #Setting the SGID permissions for ULSA_HOME_LOCATION
    if [ "$($LS $ULSA_HOME_LOCATION | awk '{print $1}')" != "$SGID_PERMISSIONS_TEXT" ]; then
        info "Setting the SGID permission for $ULSA_HOME_LOCATION"
        $CHMOD $SGID_PERMISSIONS $ULSA_HOME_LOCATION || error "Unable to set permissions to $SGID_PERMISSIONS for $ULSA_HOME_LOCATION"
    fi

    info "Change ${ULSA_TMP_DIRECTORY} permissions "
    $CHMOD $FILE_PERMISSIONS $ULSA_TMP_DIRECTORY/* || error "Unable to change permissions to $FILE_PERMISSIONS for the $ULSA_TMP_DIRECTORY files"
    $CHOWN $JBOSS_USER:$SMRS_GROUP $ULSA_TMP_DIRECTORY/* || error "Unable to change ownership to $JBOSS_USER for $ULSA_TMP_DIRECTORY"

    #Check if /ericsson/ul_spectrum_files is mounted v4
    if [ "$V4" = "true" ]; then
        ${SETFACLV4} -a A:dg:${SMRS_GID}:${GROUP_PERMISSIONS_V4} $ULSA_HOME_LOCATION || error "Unable to set mask using ACL command for $ULSA_HOME_LOCATION"
    else
        #Setting the default permissions for smrsgroup to smrsroot dir so that directories under it are created with 775
        $SETFACL -dm g:$SMRS_GROUP:$GROUP_PERMISSIONS $ULSA_HOME_LOCATION || error "Unable to set mask using ACL command for $ULSA_HOME_LOCATION"
    fi
    info "Applying permissions to ulsa directory $ULSA_HOME_LOCATION completed"
}

######################################
# Action :
#    Configures the mini link indoor fileshare.
# Globals :
#   None
# Arguments:
#   None
# Returns:
######################################
__configure_mini_link_indoor_fs()
{
    info "MINI-LINK-Indoor SMRS File Share configuration started"

    __configure_smrs_subdirectory_fs $MINI_LINK_INDOOR_SOFTWARE
    __configure_smrs_subdirectory_fs $MINI_LINK_INDOOR_LICENSE
    __configure_smrs_subdirectory_fs $MINI_LINK_INDOOR_BACKUP

    info "MINI-LINK-Indoor SMRS File Share configuration completed"
}

######################################
# Action :
#   __configure_pm_push_fs
# Arguments:
#   $1 - Total number of PM_PUSH file systems
#   $2 - Root directory
#   $3 - sub directory
# Returns:
######################################
__configure_pm_push_fs()
{
    info "PM Push SMRS File Share configuration started"

    for pm_push_fs_index in `eval echo {1..$1}`
    do
        PM_PUSH_HOME_LOCATION="$2/pm_push_$pm_push_fs_index"
        if [ "$2" == "$SMRS_ROOT_DIRECTORY" ]; then
             __configure_smrs_subdirectory_fs "$PM_PUSH_HOME_LOCATION"
        fi

        if [ "$#" -gt 2 ]; then
            PM_PUSH_SUBDIR="$PM_PUSH_HOME_LOCATION/$3"
            $MKDIR "$PM_PUSH_SUBDIR"
            __configure_smrs_subdirectory_fs "$PM_PUSH_SUBDIR"
        fi
    done

    info "PM Push SMRS File Share configuration completed"
}

###########################################################################
# Action :
#   Apply permissions to upgrade_independence directory
# Arguments:
#   -
# Returns:
###########################################################################
__configure_upgrade_independence_fs()
{
    __configure_smrs_subdirectory_fs $UPGRADE_INDEPENDENCE_DIRECTORY
}

###########################################################################
# Action :
#   Removing amos_user ACL from smrsroot dir if present.
#   This method is placed temporarly to remove the amos_user ACL from SMRS FS
#   and can be removed once all the cutomer environments are moved to 20.2
#   release or later.
# Arguments:
#   -
# Returns:
###########################################################################
__cleanup_amos_users_ACL()
{
    if [ "$($GETFACL -d -p -t "$1" | $GREP $AMOS_GROUP | awk '{print $2}')" == $AMOS_GROUP ]; then
        info "Removing $AMOS_GROUP ACL from $1"
        $SETFACL -x d:g:$AMOS_GROUP $1
    fi
}
__configure_smrs_subdirectory_fs_nl_sub()
{
   __configure_smrs_subdirectory_fs $SMRS_ROOT_DIRECTORY_WITH_NL
   nl_ac_list=$(ls -d $SMRS_ROOT_DIRECTORY_WITH_NL_SUB)
      for nl_ac in $nl_ac_list
      do
        __configure_smrs_subdirectory_fs $nl_ac
      done
}

####################################
# Action :
#    Configures the SMRS subdirectory fileshare.
# Globals :
#   None
# Arguments:
#    $1 - the directories.
# Returns:
####################################
__configure_smrs_subdirectory_fs()
{
    info "Applying permissions to directories $1"

    if [ ! -d "$1" ]; then
        info "Creating directory $1"
        $MKDIR "$1" || error "Unable to create directory $1"
    fi

    # Changing User JBOSS_USER and Group mm-smrsusers ownership
    if [[ "$($LS "$1" | awk '{print $4}')" != "$SMRS_GROUP" || "$($LS "$1" | awk '{print $3}')" != "$JBOSS_USER" ]]; then
        info "Changing User and Group ownership of $1"
        $CHOWNR $JBOSS_USER:$SMRS_GROUP "$1" || error "Unable to change ownership to $JBOSS_USER for $1"
    fi

    #Setting the SGID permissions for smrsroot dir so that directories under it are created with smrsgroup
    if [ "$($LS "$1" | awk '{print $1}')" != "$SGID_PERMISSIONS_TEXT" ]; then
        info "Setting the SGID permission for smrsroot"
        find $1 -type d -print0 | xargs -0 $CHMOD $SGID_PERMISSIONS || error "Unable to set permissions to $SGID_PERMISSIONS for $1"
    fi

    if [ "$V4" = "true" ]; then
        ${SETFACLV4} -a A:dg:${SMRS_GID}:${GROUP_PERMISSIONS_V4} "$1" || error "Unable to set mask using ACL command for $1"
    else
        #Setting the default permissions for smrsgroup to smrsroot dir so that directories under it are created with 775
        $SETFACL -dm g:$SMRS_GROUP:$GROUP_PERMISSIONS "$1" || error "Unable to set mask using ACL command for $1"
    fi
    info "Applying permissions to directories $1 completed"
}

####################################
__configure_support_unit_smrs_subdirectory_fs()
{
    info "Applying permissions to directories $1"

    if [ ! -d "$1" ]; then
        info "Creating directory $1"
        $MKDIR "$1" || error "Unable to create directory $1"
    fi

    # Changing User ROOT/JBOSS_USER and Group mm-su-read-only ownership.
    if [[ "$1" == "$SUPPORT_UNIT_SOFTWARE_LOCATION" ]]; then
        if [[ "$($LS "$1" | awk '{print $4}')" != "$SUPPORT_UNIT_GROUP" || "$($LS "$1" | awk '{print $3}')" != "$JBOSS_USER" ]]; then
            info "Setting $JBOSS_USER User and $SUPPORT_UNIT_GROUP Group ownership of $1"
            $CHOWNR $JBOSS_USER:$SUPPORT_UNIT_GROUP "$1" || error "Unable to change ownership to $JBOSS_USER for $1/"
        fi
    elif [[ "$1" == "$SUPPORT_UNIT_LOCATION" ]]; then
        if [[ "$($LS "$1" | awk '{print $4}')" != "$SUPPORT_UNIT_GROUP" || "$($LS "$1" | awk '{print $3}')" != "$ROOT_USER" ]]; then
            info "Setting $ROOT_USER User and $SUPPORT_UNIT_GROUP Group ownership of $1"
            $CHOWNR $ROOT_USER:$SUPPORT_UNIT_GROUP "$1" || error "Unable to change ownership to $ROOT_USER for $1/"
        fi
    fi

    #Setting the 755 permissions for smrsroot dir so that directories under it are created with smrsgroup
    if [ "$($LS "$1" | awk '{print $1}')" != "$PERMISSIONS_SYMBOL" ]; then
        info "Setting the SGID permission for smrsroot"
        find $1 -type d -print0 | xargs -0 $CHMOD $PERMISSIONS || error "Unable to set permissions to $PERMISSIONS for $1"
    fi

    if [ "$V4" = "true" ]; then
        ${SETFACLV4} -a A:dg:${SUPPORT_UNIT_GID}:${SU_GROUP_PERMISSIONS_V4} "$1" || error "Unable to set mask using ACL command for $1"
    else
        #Setting the Read & Execute permissions for support unit group to support unit directories so that directories under it are created with 755
        $SETFACL -dm g:$SUPPORT_UNIT_GROUP:$SU_GROUP_PERMISSIONS "$1" || error "Unable to set mask using ACL command for $1"
    fi
    info "Applying permissions to directories $1 completed"
}

######################################
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
__cleanup_amos_users_ACL $SMRS_ROOT_DIRECTORY

exit 0
