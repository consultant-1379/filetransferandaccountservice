#!/bin/bash

readonly _SED=/bin/sed
readonly _AWK=/bin/awk
readonly SCRIPT_NAME="${0}"
readonly LOG_TAG="Config_SSH_ciphers_in_SSHD_CONFIG_file"
readonly _SSHD_CONFIG_file="/etc/ssh/sshd_config"
readonly OLD_PIB_PROP_FILE="/etc/ssh/scripts/ssh_pib_old_pib_values.properties"
readonly KEX_PIB_NAME="disableWeakKeyexchangeAlgorithms"
readonly CIPHER_PIB_NAME="disableWeakEncryptionAlgorithms"
readonly MAC_PIB_NAME="disableWeakHashingAlgorithms"
readonly _PIB_CONFIG_SCRIPT="/opt/ericsson/PlatformIntegrationBridge/etc/config.py";
readonly GLOBAL_PROPERTIES_FILE="/ericsson/tor/data/global.properties"
readonly DDC_ON_CLOUD_KEY="DDC_ON_CLOUD="

#readonly ciphers_array=(chacha20-poly1305@openssh.com aes128-ctr aes192-ctr aes256-ctr aes128-gcm@openssh.com aes256-gcm@openssh.com aes128-cbc aes192-cbc aes256-cbc blowfish-cbc cast128-cbc 3des-cbc)

#readonly mac_array=(umac-64-etm@openssh.com umac-128-etm@openssh.com hmac-sha2-256-etm@openssh.com hmac-sha2-512-etm@openssh.com hmac-sha1-etm@openssh.com umac-64@openssh.com umac-128@openssh.com hmac-sha2-256 hmac-sha2-512 hmac-sha1)

#readonly kex_array=(curve25519-sha256 curve25519-sha256@libssh.org ecdh-sha2-nistp256 ecdh-sha2-nistp384 ecdh-sha2-nistp521 diffie-hellman-group-exchange-sha256 diffie-hellman-group16-sha512 diffie-hellman-group18-sha512 diffie-hellman-group-exchange-sha1 diffie-hellman-group14-sha256 diffie-hellman-group14-sha1 diffie-hellman-group1-sha1)

readonly ciphers_array=($(ssh -Q cipher))
readonly mac_array=($(ssh -Q mac))
readonly kex_array=($(ssh -Q kex))

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
# This method is used to read the sps instance from physical or cloud
#########################################################
get_service_instance() {
    if [ -f ${GLOBAL_PROPERTIES_FILE} ] ; then
        
        service_instance_name="$(consul members | grep -i "\-consfiletransferandaccount" |awk '{print $2}'|cut -d: -f1 |head -n 1)";
        ping -c 3 "$service_instance_name" >/dev/null 2>&1
        if [[ "$?" != 0 ]] ; then
            service_instance_name="$(consul members | grep -i "\-sps" |awk '{print $2}'|cut -d: -f1 |head -n 1)";
        fi

        ping -c 3 "$service_instance_name" >/dev/null 2>&1;
        if [[ "$?" != "0" ]] ; then
            error "The obtained service instance [$service_instance_name] is not pingable. Exiting the script"
            exit 1;
        fi
    else
        error "The ${GLOBAL_PROPERTIES_FILE} file does not exist"
        exit 1;
    fi

}

#########################################################
# This method is used to read the SSH weak ciphers pib parameter value
#########################################################
readSystemSshCiphersPibValue(){

    get_service_instance

    kexPibValue=$("$_PIB_CONFIG_SCRIPT" read --app_server_address "$service_instance_name":8080 --name="$KEX_PIB_NAME"|tr -d "\t\n\r "|sed 's/.*[Ss][Ss][Hh]\:/SSH\:/g')
    cipherPibValue=$("$_PIB_CONFIG_SCRIPT" read --app_server_address "$service_instance_name":8080 --name="$CIPHER_PIB_NAME"|tr -d "\t\n\r "|sed 's/.*[Ss][Ss][Hh]\:/SSH\:/g')
    macPibValue=$("$_PIB_CONFIG_SCRIPT" read --app_server_address "$service_instance_name":8080 --name="$MAC_PIB_NAME"|tr -d "\t\n\r "|sed 's/.*[Ss][Ss][Hh]\:/SSH\:/g')

}



#########################################################
# This method is used to read the stored ssh PIB parameters value
#########################################################
readStoredSshCiphersPibValue(){

    if [[ -s "$OLD_PIB_PROP_FILE" ]];then
        source "$OLD_PIB_PROP_FILE"
    else
        echo "${KEX_PIB_NAME}=NULL" >> "$OLD_PIB_PROP_FILE";
        echo "${CIPHER_PIB_NAME}=NULL" >> "$OLD_PIB_PROP_FILE";
        echo "${MAC_PIB_NAME}=NULL" >> "$OLD_PIB_PROP_FILE";
        source "$OLD_PIB_PROP_FILE"
    fi
    kexOldValue=$(echo ${!KEX_PIB_NAME});
    cipherOldValue=$(echo ${!CIPHER_PIB_NAME});
    macOldValue=$(echo ${!MAC_PIB_NAME});

}



#########################################################
# This method is used to set the old Pib value to the property file
#########################################################
setProperty(){
   OLD_PIB="$1"
   PIB_VALUE="$2"
   "$_SED" -i "s/.*$OLD_PIB.*/$OLD_PIB=$PIB_VALUE/g"  "$OLD_PIB_PROP_FILE"
}



#########################################################
# This method is used to set the ciphers to sshd_config file
#########################################################
set_filtered_ciphers(){
    declare -a default_array
    local pib_value="$1"
    local cipher_id="$2"
    local default_array=($3)
    weak_ciphers=($(echo "$pib_value"|sed 's/.*[Ss][Ss][Hh]\://g'|tr '+' "\n"))
    if [[ ${#weak_ciphers[@]} -eq 0 || " ${weak_ciphers[*],,} " =~ "none" ]] ; then
        assembled_ciphers=$(echo "${cipher_id} $(IFS=, ; echo "${default_array[*]}")")
    else
        strong_ciphers=( "${default_array[@]}" )
        for target in "${weak_ciphers[@]}"; do
            if [[ " ${strong_ciphers[*]} " =~ " ${target} " ]]; then
                for i in "${!strong_ciphers[@]}"; do
            if [[ ${strong_ciphers[i]} == ${target} ]]; then
                unset 'strong_ciphers[i]'
            fi
        done
            strong_ciphers=( $(echo "${strong_ciphers[@]}") )
            else
                error "The given ciphers [$target] is skipped as it is not a valid cipher of [${cipher_id} algorithm]"
                echo "The given ciphers [$target] is skipped as it is not a valid cipher of [${cipher_id} algorithm]"
            fi
        done
        printf -v joined_strong_ciphers '%s,' "${strong_ciphers[@]}"
        assembled_ciphers=$(echo "${cipher_id} ${joined_strong_ciphers%,}")
    fi

    cat "$_SSHD_CONFIG_file" |grep "$cipher_id" >/dev/null 2>&1
    if [[ "$?" == "0" ]] ; then
        "$_SED" -i "s/.*${cipher_id}.*/${assembled_ciphers}/g" "$_SSHD_CONFIG_file"
    else
        "$_SED" -i "/.*\#ChrootDirectory.*/a ${assembled_ciphers}" "${_SSHD_CONFIG_file}"
    fi
}



#########################################################
# This method is used to set SSH ciphers in the sshd config
# file by filtering the weak ciphers, only when there is a PIB value change.
#########################################################
compareAndSetSshCiphersPibValues(){
    if [[ "$kexPibValue" != "$kexOldValue" ]] ; then
        info "The ${KEX_PIB_NAME} PIB parameter has been changed from [$kexOldValue] to [$kexPibValue]"
        set_filtered_ciphers "$kexPibValue" "KexAlgorithms" "${kex_array[*]}"
        setProperty ${KEX_PIB_NAME} ${kexPibValue}
        info "Successfully configured sshd config file ${KEX_PIB_NAME}"
    fi

    if [[ "$cipherPibValue" != "$cipherOldValue" ]] ; then
        info "The ${CIPHER_PIB_NAME} PIB parameter has been changed from [$cipherOldValue] to [$cipherPibValue]"
        set_filtered_ciphers "$cipherPibValue" "Ciphers" "${ciphers_array[*]}"
        setProperty ${CIPHER_PIB_NAME} ${cipherPibValue}
        info "Successfully configured sshd config file with ${CIPHER_PIB_NAME}"
    fi

    if [[ "$macPibValue" != "$macOldValue" ]] ; then
        info "The ${MAC_PIB_NAME} PIB parameter has been changed from [$macOldValue] to [$macPibValue]"
        set_filtered_ciphers "$macPibValue" "MACs" "${mac_array[*]}"
        setProperty ${MAC_PIB_NAME} ${macPibValue}
        info "Successfully configured sshd config file with ${MAC_PIB_NAME}"
    fi

    /bin/systemctl restart sshd.service

}


##main_method
readSystemSshCiphersPibValue
readStoredSshCiphersPibValue
compareAndSetSshCiphersPibValues