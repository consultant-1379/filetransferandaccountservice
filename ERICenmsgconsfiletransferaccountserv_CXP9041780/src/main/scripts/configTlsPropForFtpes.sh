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

readonly _SED=/bin/sed
readonly _BASH=/bin/bash
readonly _SERVICE=/sbin/service
readonly _AWK=/bin/awk
readonly SCRIPT_NAME="${0}"
readonly LOG_TAG="Config_TLS_version_in_FTPES_file"
readonly _TLS1_0_TAG="ssl_tlsv1="
readonly _TLS1_1_TAG="ssl_tlsv1_1="
readonly _TLS1_2_TAG="ssl_tlsv1_2="
readonly _TLS1_3_TAG="ssl_tlsv1_3="
readonly _TLS_VERSION_1="TLSv1";
readonly TLS_VERSION_1_0="TLSv1.0";
readonly TLS_VERSION_1_1="TLSv1.1";
readonly TLS_VERSION_1_2="TLSv1.2";
readonly TLS_VERSION_1_3="TLSv1.3";
readonly _DEFAULT_TLS_VERSION_ARRAY=("$_TLS_VERSION_1" "$TLS_VERSION_1_0" "$TLS_VERSION_1_1" "$TLS_VERSION_1_2" "$TLS_VERSION_1_3")
readonly _FTPESCONFIG_SCRIPT="/ericsson/3pp/jboss/bin/post-start/ftpes-config.sh"
readonly OLD_PIB_PROP_FILE="/etc/vsftpd/scripts/ecim_tls_version_old_pib_values.properties"
readonly PIB_NAME="enabledTLSProtocolsECIM"
readonly _PIB_CONFIG_SCRIPT="/opt/ericsson/PlatformIntegrationBridge/etc/config.py";
readonly GLOBAL_PROPERTIES_FILE="/ericsson/tor/data/global.properties"
readonly DDC_ON_CLOUD_KEY="DDC_ON_CLOUD="

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


#########################################################
# This method is used to read the smrs instance from physical or cloud
#########################################################
get_service_instance() {
    if [ -f ${GLOBAL_PROPERTIES_FILE} ] ; then
        isCloud=$(grep -Po "(?<=^${DDC_ON_CLOUD_KEY}).*" ${GLOBAL_PROPERTIES_FILE});

        if [[ "${isCloud,,}" == "true" ]]; then
            service_instance_name="$(consul members | grep -i "\-consfiletransferaccount" |awk '{print $2}'|cut -d: -f1 |head -n 1)";
            ping -c 3 "$service_instance_name" >/dev/null 2>&1
            if [[ "$?" != 0 ]] ; then
                service_instance_name="$(consul members | grep -i "\-sps" |awk '{print $2}'|cut -d: -f1 |head -n 1)";
            fi
        else
            service_instance_name="$(cat /etc/hosts |grep -i "\-consfiletransferaccount" |awk '{print $2}'|head -n 1)";
            ping -c 3 "$service_instance_name" >/dev/null 2>&1
            if [[ "$?" != 0 ]] ; then
                service_instance_name="$(cat /etc/hosts |grep -i "\-sps" |awk '{print $2}'|head -n 1)";
            fi
    fi

    else
        error "The ${GLOBAL_PROPERTIES_FILE} file does not exist"
        exit 1;
    fi
}

#########################################################
# This method is used to read the ECIM pib parameter value
#########################################################
readSystemTlsEcimPibValue(){
get_service_instance
ECIM_PIB_VALUE=$("$_PIB_CONFIG_SCRIPT" read --app_server_address "$service_instance_name":8080 --name="$PIB_NAME"|tr -d "\t\n\r ")
}

#########################################################
# This method is used to read the stored PIB parameter value
#########################################################
readStoredTlsEcimPibValue(){

if [[ -s "$OLD_PIB_PROP_FILE" ]];then
    source "$OLD_PIB_PROP_FILE"
else
    echo "OLD_PIB_VALUE=NULL" >> "$OLD_PIB_PROP_FILE";
    source "$OLD_PIB_PROP_FILE"
fi
oldPibValue=$(echo $OLD_PIB_VALUE);
}

#########################################################
# This method is used to configure FTPES config file for the given version
#########################################################
configFTPESfile(){
local -r version="$1"

if [[ "$version" == "$_TLS_VERSION_1" || "$version" == "$TLS_VERSION_1_0" ]]; then
"$_SED" -i "s/.*${_TLS1_0_TAG}.*/${_TLS1_0_TAG}YES/g"  "$_FTPESCONFIG_SCRIPT"
elif [[ "$version" == "$TLS_VERSION_1_1" ]]; then
"$_SED" -i "s/.*${_TLS1_1_TAG}.*/${_TLS1_1_TAG}YES/g" "$_FTPESCONFIG_SCRIPT"
elif [[ "$version" == "$TLS_VERSION_1_2" ]]; then
"$_SED" -i "s/.*${_TLS1_2_TAG}.*/${_TLS1_2_TAG}YES/g"  "$_FTPESCONFIG_SCRIPT"
elif [[ "$version" == "$TLS_VERSION_1_3" ]]; then
"$_SED" -i "s/.*${_TLS1_3_TAG}.*/${_TLS1_3_TAG}YES/g"  "$_FTPESCONFIG_SCRIPT"
fi
}

#########################################################
# This method is used to verify the given tls version with allowed TLS version.
#########################################################
verifyWithDefaultTLSVersions(){
local -r PIB_VALUE_ARRAY=("${@}")
for version in "${PIB_VALUE_ARRAY[@]}"; do
if [[ ! " ${_DEFAULT_TLS_VERSION_ARRAY[@]} " =~ " ${version} " ]]; then
    error "Given TLS version : [$version] is invalid . Please give any one of the inputs [${_DEFAULT_TLS_VERSION_ARRAY[*]}]"
    error "vSFTPD configuration is unsuccessful"
    exit 1;
fi
done
}

#########################################################
# This method is used to verify and configure tls tags in
# FTPES config file based on the TLS versions
#########################################################
verifyAndSetTLSversions(){
local -r tls_version_from_pib=$(echo "$1"|sed "s/ //g")
IFS="," read -r -a tls_versions_array <<< "$tls_version_from_pib"

verifyWithDefaultTLSVersions "${tls_versions_array[@]}"

"$_SED" -i "s/.*${_TLS1_0_TAG}.*/${_TLS1_0_TAG}NO/g"  "$_FTPESCONFIG_SCRIPT"
"$_SED" -i "s/.*${_TLS1_1_TAG}.*/${_TLS1_1_TAG}NO/g"  "$_FTPESCONFIG_SCRIPT"
"$_SED" -i "s/.*${_TLS1_2_TAG}.*/${_TLS1_2_TAG}NO/g"  "$_FTPESCONFIG_SCRIPT"
"$_SED" -i "s/.*${_TLS1_3_TAG}.*/${_TLS1_3_TAG}NO/g"  "$_FTPESCONFIG_SCRIPT"

for tlsVersion in "${tls_versions_array[@]}"
do
configFTPESfile "$tlsVersion"
done

}

#########################################################
# This method is used to set the old Pib value to the property file
#########################################################
setProperty(){
    "$_SED" -i "s/.*OLD_PIB_VALUE.*/OLD_PIB_VALUE=$ECIM_PIB_VALUE/g"  "$OLD_PIB_PROP_FILE"
}

#########################################################
# This method is used to set TLS tags in the FTPES config
# file based on the TLS versions, only when there is a PIB value change.
#########################################################
compareAndSetEcimPibValues(){
if [[ "$ECIM_PIB_VALUE" != "$oldPibValue" ]] ;then
    info "The enabledTLSProtocolsECIM PIB parameter has been changed from [$oldPibValue] to [$ECIM_PIB_VALUE]"
    verifyAndSetTLSversions "$ECIM_PIB_VALUE"
    "$_BASH" "$_FTPESCONFIG_SCRIPT";
    setProperty
    info "Successfully configured ftpes config file"
fi
exit 0;
}

#########################################################
# Main code
#########################################################
readSystemTlsEcimPibValue
readStoredTlsEcimPibValue
compareAndSetEcimPibValues


