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

GLOBAL_PROPERTIES_FILE="/ericsson/tor/data/global.properties"
SSHD_CONFIG=/etc/ssh/sshd_config
LOG_TAG="apply_sftp_match_rules"
SFTP_PROHIBITION_PORT_RULE_START_TAG="# prohibition of port 22 rule start"
SFTP_PROHIBITION_PORT_RULE_END_TAG="# prohibition of port 22 rule end"
MATCH_STRING_MM_SMRS_USER="Match Group mm-smrsusers"
CONSUL="/usr/bin/consul"

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

#This function modifies the SSHD_config if the smrs_sftp_parttion_enable sed parameter set to true ,then :
# All the incoming requests on port 22 are blocked for all the users except mm-ul_spectrum_files.
# The other users are allowed only on configurable port.
# All the ssh/sftp requests from the external subnets are blocked.
function append_sftp_match_rules(){
    var_is_cloud="$1"
    var_smrs_sftp_secure_port="$2"
    var_smrs_sftp_port_partition_enable="${3,,}"

    if [[ "$var_smrs_sftp_port_partition_enable" != "true" ]]; then
        info "Skip configuring sftp prohibited port match rules as smrs_sftp_port_partition_enable parameter is not true and the value is : '$var_smrs_sftp_port_partition_enable'"
        var_smrs_sftp_port_partition_enable="false"
    fi

    remove_existing_prohibited_port_match_rules
    if [[ "$var_smrs_sftp_port_partition_enable" == "true" ]]; then
        info "Configuring sftp prohibited port match rules to sshd_config"
        read_enm_internal_subnet_info
        verify_and_add_mm_smrs_default_match_rule
        append_prohibited_port_match_rules
    fi
}

# Remove existing prohibited port match rules from sshd_config (if exists)
remove_existing_prohibited_port_match_rules(){
    info "Removing prohibited port match rules from sshd_config if there are any such."
    cat ${SSHD_CONFIG} | grep "$SFTP_PROHIBITION_PORT_RULE_START_TAG"

    isRuleExists="$?"
    if [[ "$isRuleExists" == "0" ]]; then
      sed -i "/$SFTP_PROHIBITION_PORT_RULE_START_TAG/,/$SFTP_PROHIBITION_PORT_RULE_END_TAG/d" ${SSHD_CONFIG}
    fi
}

# Read enm internal subnet info from global.properties or consul command
read_enm_internal_subnet_info(){
    tmpFile="/tmp/$$_tmpFile"

    if [[ "$var_is_cloud" == "true" ]]; then
        "$CONSUL" kv get -recurse | grep -i "subnet" > "$tmpFile"
        sed -i "s|:|=|;s|\"\"||" "$tmpFile"
        read_enm_internal_subnet_info_from_file "$tmpFile"
    else
        cat "$GLOBAL_PROPERTIES_FILE" | grep -i 'subnet' > "$tmpFile"
        read_enm_internal_subnet_info_from_file "$tmpFile"
    fi

    if [ -f "$tmpFile" ] ; then
        rm -rf "$tmpFile"
    fi
}

#Read enm internal subnet info from the given file
read_enm_internal_subnet_info_from_file(){
    index=0
    var=subnet_ip_address
    while IFS='=' read -r key value
    do
        if [ "$value" != "" ]; then
            if [[ "$value" == *":"* ]]; then
                value=`echo "[$value" | sed "s|\/|]\/|g"`
            fi
            read "$var[$index]" <<< "$value"
            (( index ++ ))
        fi
    done < "$1"
}

# verify and add mm-smrs_users default match rule to sshd_config
verify_and_add_mm_smrs_default_match_rule(){
    cat "$SSHD_CONFIG" | grep "$MATCH_STRING_MM_SMRS_USER"
    if [[ "$?" != "0" ]]; then
        add_mm_smrs_default_match_rule
        if [[ "$?" != "0" ]]; then
            error "Error while finding mm-smrs_users match rule."
            exit 1
        fi
    fi
}

# Add default match rule for mm-smrsusers to given file
add_mm_smrs_default_match_rule(){
(
cat <<'END_RM'

Match Group mm-smrsusers
ChrootDirectory /home/smrs
ForceCommand internal-sftp
AllowTcpForwarding no
END_RM
) >> "$SSHD_CONFIG"
}

# Append prohibited port match rules into sshd_config for prohibition of port 22
append_prohibited_port_match_rules(){
    info "Configuring smrs sftp prohibited port match rules"
    tempFile="/tmp/$$_tempFile"

    construct_match_address_rule_with_enm_subnet_info

    write_prohibited_port_match_rules_to_tempFile "$tempFile"
    sed -i "s|SFTP_PROHIBITION_PORT_RULE_START_TAG|$SFTP_PROHIBITION_PORT_RULE_START_TAG|g"  "$tempFile"
    sed -i "s|SFTP_PROHIBITION_PORT_RULE_END_TAG|$SFTP_PROHIBITION_PORT_RULE_END_TAG|g"  "$tempFile"
    sed -i "s|CONFIGURABLE_SFTP_SECURED_PORT|$var_smrs_sftp_secure_port|g"  "$tempFile"
    sed -i "s|CONFIGURABLE_MATCH_ADDRESS_RULE|$matchAddrRule|g" "$tempFile"

    # To insert prohibited port match rules just above mm-smrs_users match rule
    sed -n -i -e "/$MATCH_STRING_MM_SMRS_USER/r "$tempFile"" -e 1x -e '2,${x;p}' -e '${x;p}' "$SSHD_CONFIG"

    if [ -f "$tempFile" ] ; then
        rm -rf "$tempFile"
    fi
}

# Populate sftp match address rule to match subnet ip addresses
construct_match_address_rule_with_enm_subnet_info() {
    if [ ${#subnet_ip_address[@]} -eq 0 ]; then
        error "Subnet IP addresses are not defined hence exiting."
        exit 1
    else
        matchAddrRule="Match "

        for subnetIpAddress in "${subnet_ip_address[@]}"
        do
            matchAddrRule="${matchAddrRule} Address *,!$subnetIpAddress"
        done

        info "Match address rule prepared with subnet info : $matchAddrRule"
    fi
}

# Write prohibited port match rules into a temporary file
write_prohibited_port_match_rules_to_tempFile(){
    local -r temp_file="$1"
(
cat <<'END_ADD'
SFTP_PROHIBITION_PORT_RULE_START_TAG
# following rule capture users different from ul_spectrum_users and sftp port other than 22
Match User *,!mm-ul_spectrum* Group mm-smrsusers LocalPort CONFIGURABLE_SFTP_SECURED_PORT
ChrootDirectory /home/smrs/
ForceCommand internal-sftp
AllowTcpForwarding no

# following rule capture users of ul_spectrum_users on port 22
Match User mm-ul_spectrum* Group mm-smrsusers LocalPort 22
ChrootDirectory /home/smrs/
ForceCommand internal-sftp
AllowTcpForwarding no

# following rule capture ssh/sftp sessions from IPsubnet different from internal subnets
# defined in /ericsson/tor/data/global.properties
# these are: storage_subnet/jgroups_subnet ENMservices_subnet internal_subnet internal_IPv6subnet.
# action is forbid everything (ForceCommand null)
CONFIGURABLE_MATCH_ADDRESS_RULE
ForceCommand null
AllowTcpForwarding no

SFTP_PROHIBITION_PORT_RULE_END_TAG
END_ADD
) > "$temp_file"
}