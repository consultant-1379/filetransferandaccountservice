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

BASENAME=/bin/basename
SCRIPT_NAME="${BASENAME} ${0}"
LOG_TAG="SMRS_SFTP_CONFIGURATION"
CAT="/bin/cat"
ECHO="/bin/echo"
GREP="/bin/grep"
SHELLS="/etc/shells"

PASSWORD_AUTH_AC="/etc/pam.d/password-auth-ac"
PAM_SSS_USE_FIRST_PASS="pam_sss.so use_first_pass"
PAM_SSS_FORWARD_PASS="pam_sss.so forward_pass"
PAM_UNIX_SO="pam_unix.so"
PAM_UNIX_TRY_FIRST_PASS="$PAM_UNIX_SO nullok try_first_pass"
PAM_UNIX_BROKEN_SHADOW="$PAM_UNIX_SO broken_shadow"
PAM_SUCCEED_IF="pam_succeed_if.so uid >= 500 quiet"
PAM_MKHOMEDIR_SO="pam_mkhomedir.so"
REPLACE_COUNT=1
SUFFICIENT_CONTROL_FLAG="sufficient"
REQUIRED_CONTROL_FLAG="required"
AUTH_CONTROL_FLAG="auth"
ACCOUNT_CONTROL_FLAG="account"
PAM_DENY_SO="pam_deny.so"
AUTHSELECT="/usr/bin/authselect"
PASSWORD_AUTH_AC_RHEL8="/etc/authselect/custom/user-profile/password-auth"

#############################################################
#
# Logger Functions
#
#############################################################
info()
{
    logger -t "${LOG_TAG}" -p user.notice "INFORMATION (${SCRIPT_NAME} ): $1"
}

error()
{
    logger -t "${LOG_TAG}" -p user.err "ERROR (${SCRIPT_NAME} ): $1"
}

#############################################################
# This function overides the default configuration of pam to
# authenticate using pam_sss first instead of pam_unix.
# SubString is replaced only on the very first occurence.
# Refer TORF-259812, TORF-511377, TORF-513395 for more info.
# Arguments:
#        none
#############################################################
__update_password_auth_ac_rules()
{
    if [ ! -f "$PASSWORD_AUTH_AC" ]; then
        error "$PASSWORD_AUTH_AC file is unavailable. Skipping the password auth ac rules update."
    fi
    info "Updating and re-arranging the password auth ac rules for password authentication in $PASSWORD_AUTH_AC file."

    sed -i "/$SUFFICIENT_CONTROL_FLAG    $PAM_UNIX_TRY_FIRST_PASS/d" $PASSWORD_AUTH_AC
    if [ $? -ne 0 ]; then
        error "Failed to remove $SUFFICIENT_CONTROL_FLAG    $PAM_UNIX_TRY_FIRST_PASS in $PASSWORD_AUTH_AC"
    fi

    sed -i "/$SUFFICIENT_CONTROL_FLAG    $PAM_SSS_FORWARD_PASS/d" $PASSWORD_AUTH_AC

    sed -i "s/.*$AUTH_CONTROL_FLAG        $REQUIRED_CONTROL_FLAG      $PAM_DENY_SO.*/$AUTH_CONTROL_FLAG        $SUFFICIENT_CONTROL_FLAG    $PAM_UNIX_TRY_FIRST_PASS/" $PASSWORD_AUTH_AC

    sed -i "/$AUTH_CONTROL_FLAG        $SUFFICIENT_CONTROL_FLAG    $PAM_UNIX_TRY_FIRST_PASS/a\auth        $REQUIRED_CONTROL_FLAG      $PAM_DENY_SO" $PASSWORD_AUTH_AC

    sed -i "6 i $AUTH_CONTROL_FLAG        $SUFFICIENT_CONTROL_FLAG    $PAM_SSS_FORWARD_PASS" $PASSWORD_AUTH_AC
    if [ $? -ne 0 ]; then
        error "Failed to add $AUTH_CONTROL_FLAG        $SUFFICIENT_CONTROL_FLAG    $PAM_SSS_FORWARD_PASS as 6th line in $PASSWORD_AUTH_AC"
    fi

    sed -i "s/.*$ACCOUNT_CONTROL_FLAG     $REQUIRED_CONTROL_FLAG      $PAM_UNIX_SO.*/$ACCOUNT_CONTROL_FLAG     $REQUIRED_CONTROL_FLAG      $PAM_UNIX_BROKEN_SHADOW/" $PASSWORD_AUTH_AC

    sed -i "/$PAM_MKHOMEDIR_SO/d" $PASSWORD_AUTH_AC
    if [ $? -ne 0 ]; then
        error "Failed to remove $PAM_MKHOMEDIR_SOin $PASSWORD_AUTH_AC"
    fi
}

__update_password_authselect_ac_rules() {
    if [ ! -f "$PASSWORD_AUTH_AC_RHEL8" ]; then
        error "$PASSWORD_AUTH_AC_RHEL8 file is unavailable. Skipping the password auth select rules update."
    fi
    info "Updating and re-arranging the password auth select rules for password authentication in $PASSWORD_AUTH_AC_RHEL8 file."

    sed -i "/$SUFFICIENT_CONTROL_FLAG    $PAM_SSS_FORWARD_PASS/d" $PASSWORD_AUTH_AC_RHEL8

    sed -i "s/.*$AUTH_CONTROL_FLAG        $REQUIRED_CONTROL_FLAG      $PAM_DENY_SO.*/$AUTH_CONTROL_FLAG        $SUFFICIENT_CONTROL_FLAG    $PAM_UNIX_TRY_FIRST_PASS/" $PASSWORD_AUTH_AC_RHEL8

    sed -i "/$AUTH_CONTROL_FLAG        $SUFFICIENT_CONTROL_FLAG    $PAM_UNIX_TRY_FIRST_PASS/a\auth        $REQUIRED_CONTROL_FLAG      $PAM_DENY_SO" $PASSWORD_AUTH_AC_RHEL8

    sed -i "/$AUTH_CONTROL_FLAG        $SUFFICIENT_CONTROL_FLAG                                   $PAM_SSS_FORWARD_PASS/d" $PASSWORD_AUTH_AC_RHEL8

    sed -i "3 i $AUTH_CONTROL_FLAG        $SUFFICIENT_CONTROL_FLAG                                   $PAM_SSS_FORWARD_PASS" $PASSWORD_AUTH_AC_RHEL8

    if [ $? -ne 0 ]; then
        error "Failed to add $AUTH_CONTROL_FLAG        $SUFFICIENT_CONTROL_FLAG    $PAM_SSS_FORWARD_PASS as 3rd line in $PASSWORD_AUTH_AC_RHEL8"
    fi

    sed -i "/$AUTH_CONTROL_FLAG        \[default=1 ignore=ignore success=ok\]         pam_usertype.so isregular/d" $PASSWORD_AUTH_AC_RHEL8

    sed -i "/$AUTH_CONTROL_FLAG        \[default=1 ignore=ignore success=ok\]         pam_localuser.so/d" $PASSWORD_AUTH_AC_RHEL8

    sed -i "s/.*$ACCOUNT_CONTROL_FLAG     $REQUIRED_CONTROL_FLAG      $PAM_UNIX_SO.*/$ACCOUNT_CONTROL_FLAG     $REQUIRED_CONTROL_FLAG      $PAM_UNIX_BROKEN_SHADOW/" $PASSWORD_AUTH_AC_RHEL8

    sed -i "/$PAM_MKHOMEDIR_SO/d" $PASSWORD_AUTH_AC_RHEL8
    if [ $? -ne 0 ]; then
        error "Failed to remove $PAM_MKHOMEDIR_SOin $PASSWORD_AUTH_AC_RHEL8"
    fi
}

__update_shells_with_nologin()
{
    info "Checking if nologin shell is present in /etc/shells"
    $CAT ${SHELLS} | $GREP "nologin"
    if [ $? -ne 0 ]; then
        info "Updating /etc/shells with /sbin/nologin"
        $ECHO '/sbin/nologin' >> ${SHELLS}
    fi
}

#//////////////////////////////////////////////////////////////
# Main Part of Script
#/////////////////////////////////////////////////////////////

__update_shells_with_nologin

if [ -f "$AUTHSELECT" ] && [ -f "$PASSWORD_AUTH_AC_RHEL8" ]; then
    __update_password_authselect_ac_rules
    authselect select custom/user-profile
else
    __update_password_auth_ac_rules
fi

exit 0