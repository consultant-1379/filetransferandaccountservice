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
# ********************************************************************
# Purpose : To reset the persomissions of smrsroot FS to its default,
#           if they are modified to some other.
# ********************************************************************
###########################################################################

# UTILITIES
BASENAME=/bin/basename
SCRIPT_NAME="${BASENAME} ${0}"
AWK=/usr/bin/awk
CAT=/bin/cat
CHMOD=/bin/chmod
CHOWN=/bin/chown
CHOWNR="${CHOWN} -R"
CHGRP=/bin/chgrp
CHGRPR="${CHGRP} -R"
FIND=/bin/find
GREP=/bin/grep
GETENT=/usr/bin/getent
ID=/usr/bin/id
LS=/bin/ls
LD="${LS} -ld"
MOUNT=/bin/mount
RM=/bin/rm
SETFACL=/usr/bin/setfacl
SETFACLV4=/usr/bin/nfs4_setfacl
TOUCH=/bin/touch
WC=$(which wc)

# GLOBAL VARIABLES
GROUP_PERMISSIONS=7
GROUP_PERMISSIONS_V4=RWX
SU_GROUP_PERMISSIONS=5
SU_GROUP_PERMISSIONS_V4=RX
JBOSS_USER="jboss_user"
LOCK_EXPIRY_MIN="+15"
OPTION_BREAK_COUNT=100
LOG_TAG="SMRS_Configuration"
PERMISSIONS=755
SGID_PERMISSIONS=2775
SGID_PERMISSIONS_TEXT="drwxrwsr-x+"

#SMRS Constants
SMRSROOT_MAX_DEPTH_TO_SCAN=3
SMRS_GROUP="mm-smrsusers"
SMRS_GID=$(${GETENT} group ${SMRS_GROUP} | ${AWK} -F ":" '{print $3}')
SMRS_HOME_LOCATION="/home/smrs"
SMRS_ROOT="/ericsson/tor/smrs"
SMRS_ROOT_DIRECTORY="$SMRS_HOME_LOCATION/smrsroot"
SMRS_FS_PERMISSION_LOCK="$SMRS_ROOT_DIRECTORY/smrs_fs_permissions.lock"
ROOT="root"
SMRS_DIR_PERMISSIONS_TEXT="drwxr-xr-x"
V4=false

#SUPPORT_UNIT Account constants
SU_SGID_PERMISSIONS=2755
SU_SGID_PERMISSIONS_TEXT="drwxr-sr-x+"
SUPPORT_UNIT_LOCATION="$SMRS_HOME_LOCATION/3ppsoftware/support_unit"
SUPPORT_UNIT_MAX_DEPTH_TO_SCAN=2
SUPPORT_UNIT_GROUP="mm-su-read-only"
SUPPORT_UNIT_GID=5050

#ADP-DIR-FILE-CONSTANTS
SMRS_ADP_BACKUP_LOCATION="$SMRS_ROOT_DIRECTORY/backup"
STAT=/bin/stat
ADP_BACKUP_MIN_DEPTH_TO_SCAN=2
ADP_BACKUP_MAX_DEPTH_TO_SCAN=1
ADP_BACKUP_FILE_PERMISSION=640
ADP_NETYPE_DIRS=("/pcg/" "/pcc/" "/ccsm/" "/ccdm/" "/cces/" "/ccrc/" "/ccpc/" "/sc/" "/shared-cnf/")

if [ -z "$STARTUP_WAIT" ]; then
    STARTUP_WAIT=900
fi

if ${MOUNT} | ${GREP} "${SMRS_ROOT}" | ${GREP} -q vers=4; then
    V4=true
fi

#///////////////////////////////////////////////////////////////
# This function will print an error message to /var/log/messages
# Arguments:
#       $1 - Message
# Return: 0
#//////////////////////////////////////////////////////////////
error()
{
    logger  -t ${LOG_TAG} -p user.err "ERROR : ( ${SCRIPT_NAME} ) : $1"
}

#//////////////////////////////////////////////////////////////
# This function will print an info message to /var/log/messages
# Arguments:
#       $1 - Message
# Return: 0
#/////////////////////////////////////////////////////////////
info()
{
    logger  -t ${LOG_TAG} -p user.notice "INFO : ( ${SCRIPT_NAME} ) : $1"
}

####Function: check_smrs_lock ################
# Action :
#   Checks whether the smrs lock exists or not
# Globals :
#   None
# Arguments:
#   None
# Returns:
##############################################
check_smrs_lock()
{
    #info "Checking if any previous instance of SMRS Check config exists."
    if [ -e ${SMRS_FS_PERMISSION_LOCK} ]; then
        #Checking the age of SMRS lock file, shouldn't be more than 10min.
        count=$(${FIND} ${SMRS_FS_PERMISSION_LOCK} -mmin ${LOCK_EXPIRY_MIN} | ${WC} -l)
        if [ ${count} -ne 0 ]; then
            info "Lock file: ${SMRS_FS_PERMISSION_LOCK} expired, recreating it"
            ${TOUCH} ${SMRS_FS_PERMISSION_LOCK}
        else
            info "SMRS config check in progress by other instance, Exiting.."
            exit 0
        fi
    else
        info "Creating the lock file ${SMRS_FS_PERMISSION_LOCK}"
        ${TOUCH} ${SMRS_FS_PERMISSION_LOCK}
    fi
}

#/////////////////////////////////////////////////////////////
# Action : Resets default permissions to given directory
# Arguments:
#   chmodType : Chmod Type
#   Directory : Directory for which scan to be done.
#   groupName : Group name which to be set to the directory.
#   groupId : Group ID which to be set to the directory.
#   sgidPermissions : SGID permissions which to be set to the directory.
#   sgidPermissionsText : SGID permissions in Text.
#   groupPermissions : Group permissions which to be set to the directory.
#   groupPermissionsV4 : Group permissions which to be set to the directory for V4.
#/////////////////////////////////////////////////////////////
reset_permissions()
{
    local chgrpType=$1
    local dir=$2
    local groupName=$3
    local groupId=$4
    local sgidPermissions=$5
    local sgidPermissionsText=$6
    local groupPermissions=$7
    local groupPermissionsV4=$8

    #Changing Group ownership
    ${chgrpType} ${groupName} "${dir}" || error "Unable to update the group to ${groupName} for ${dir}"

    #Changing ownership JBOSS_USER
    if [ "$(${LD} ${dir} | ${AWK} '{print $3}')" != "$i{JBOSS_USER}" ]; then
        ${FIND} ${dir} -type d -print0 | xargs -0 ${CHOWN} ${JBOSS_USER} || error "Unable to set ownership to ${JBOSS_USER} for ${dir}"
    fi

    #Setting the SGID permissions so that directories under it are created with expected group
    if [ "$(${LD} ${dir} | ${AWK} '{print $1}')" != "$i{sgidPermissionsText}" ]; then
        ${FIND} ${dir} -type d -print0 | xargs -0 ${CHMOD} ${sgidPermissions} || error "Unable to set permissions to ${sgidPermissions} for ${dir}"
    fi

    #Setting the default permissions for provided group to corresponding directory so that directories under it are created with Group permissions
    if [ "${V4}" = "true" ]; then
        ${SETFACLV4} -a A:dg:${groupId}:${groupPermissionsV4} "${dir}" || error "Unable to set ACLs(V4) for ${dir}"
    else
        ${SETFACL} -dm g:${groupName}:${groupPermissions} "${dir}" || error "Unable to set ACLs for ${dir}"
    fi
}

####Function: check_configuration ###########
# Action :
#   Finds whether there are direcories with non default properties and Reset the default permissions
# Globals :
#   None
# Arguments:
#   None
# Returns:
#############################################
check_configuration_for_directory()
{
    local directory=$1
    local maxDepth=$2
    local groupName=$3
    local groupId=$4
    local sgidPermissions=$5
    local sgidPermissionsText=$6
    local groupPermissions=$7
    local groupPermissionsV4=$8

    smrs_ac_list=$($LS -d $directory/*)
    for smrs_ac in $smrs_ac_list
    do
        FAULTED_DIRS=$(${FIND}  ${smrs_ac} -maxdepth $maxDepth -type d  \( \( ! -user ${JBOSS_USER} \) -o \( ! -group ${groupName} \)  -o ! -perm ${sgidPermissions} \) )
        length=$(echo $FAULTED_DIRS | wc -w)

        if [[ $length -gt 0 ]]; then
            info "${smrs_ac} account has ${length} directories with non default properties, resetting to defaults"
            if [[ $length -gt ${OPTION_BREAK_COUNT} ]]; then
                reset_permissions "${CHGRPR}" ${smrs_ac} ${groupName} ${groupId} ${sgidPermissions} ${sgidPermissionsText} ${groupPermissions} ${groupPermissionsV4}
            else
                for fault_dir in $FAULTED_DIRS
                do
                    reset_permissions ${CHGRP} $fault_dir ${groupName} ${groupId} ${sgidPermissions} ${sgidPermissionsText} ${groupPermissions} ${groupPermissionsV4}
                done
            fi
        fi
    done
}

####Function: reset_smrs_directory_permissions ###########
# Action : Resets default permissions for /home/smrs directory
#########################
reset_smrs_directory_permissions()
{
    info "Checking file permissions for ${SMRS_HOME_LOCATION} directory"
    if [[ $(${LD} ${SMRS_HOME_LOCATION} | ${AWK} '{print $1}') != ${SMRS_DIR_PERMISSIONS_TEXT}* ]]; then
       error "${SMRS_HOME_LOCATION} does not have default permissions, resetting to defaults"
       ${FIND} ${SMRS_HOME_LOCATION} -type d -print0 | xargs -0 ${CHMOD} ${PERMISSIONS} || error "Unable to set permissions to ${PERMISSIONS} for ${SMRS_HOME_LOCATION}"
    fi
    if [ "$(${LD} ${SMRS_HOME_LOCATION} | ${AWK} '{print $3}')" != "${ROOT}" ] || [ "$(${LD} ${SMRS_HOME_LOCATION} | ${AWK} '{print $4}')" != "${ROOT}" ]; then
       error "${SMRS_HOME_LOCATION} does not have default User or Group permissions, resetting to defaults"
       ${CHOWNR} ${ROOT}:${ROOT} "${SMRS_HOME_LOCATION}" || error "Unable to update the ownership to ${ROOT} for ${SMRS_HOME_LOCATION}"
    fi
}


####Function: check_configuration ###########
# Action :
#   Finds whether there are direcories with non default properties and Reset the default permissions
# Globals :
#   None
# Arguments:
#   None
# Returns:
#############################################
check_configuration()
{
    info "SMRS File System validation started"
    check_smrs_lock

    check_configuration_for_directory $SMRS_ROOT_DIRECTORY $SMRSROOT_MAX_DEPTH_TO_SCAN $SMRS_GROUP $SMRS_GID $SGID_PERMISSIONS $SGID_PERMISSIONS_TEXT $GROUP_PERMISSIONS $GROUP_PERMISSIONS_V4
    check_configuration_for_directory $SUPPORT_UNIT_LOCATION $SUPPORT_UNIT_MAX_DEPTH_TO_SCAN $SUPPORT_UNIT_GROUP $SUPPORT_UNIT_GID $SU_SGID_PERMISSIONS $SU_SGID_PERMISSIONS_TEXT $SU_GROUP_PERMISSIONS $SU_GROUP_PERMISSIONS_V4

    check_configuration_for_adp_backup_directory $SMRS_ADP_BACKUP_LOCATION $ADP_BACKUP_MIN_DEPTH_TO_SCAN $ADP_BACKUP_MAX_DEPTH_TO_SCAN $ADP_BACKUP_FILE_PERMISSION

    reset_smrs_directory_permissions

    # Removing the SMRS lock file.
    info "Removing the lock file ${SMRS_FS_PERMISSION_LOCK}"
    ${RM} -f ${SMRS_FS_PERMISSION_LOCK}
    info "SMRS File System validation completed"
}

check_configuration_for_adp_backup_directory()
{
    local directory=$1
    local minDepth=$2
    local maxDepth=$3
    local filePermission=$4

    smrs_directory_list=$(${FIND} $directory/* -mindepth $minDepth -type d)
    info "Location of the backup manager directories: ${smrs_directory_list}"
    for dir_entry in $smrs_directory_list
    do
        for i in "${ADP_NETYPE_DIRS[@]}"
        do
            count=$(echo ${dir_entry,,} | grep -o "${i}" | wc -l)
            if [[ $count -gt 0 ]]; then
                backup_file_list=$(${FIND} ${dir_entry} -maxdepth $maxDepth -type f)
                info "List of backup files: ${backup_file_list} under backup manager directory: ${dir_entry}"
                for backup_file in $backup_file_list
                do
                    current_file_permission=$(${STAT} -c "%a" ${backup_file})
                    if [[ $filePermission != $current_file_permission ]]; then
                        ${CHMOD} ${filePermission} ${backup_file} || error "Error while permission change of file"
                    fi
                done
            fi
        done
    done
}

########
# Main #
########

#Run config
check_configuration && exit 0
