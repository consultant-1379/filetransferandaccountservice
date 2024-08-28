#!/bin/bash
###########################################################################
# COPYRIGHT Ericsson 2022
#
# The copyright to the computer program(s) herein is the property of
# Ericsson Inc. The programs may be used and/or copied only with written
# permission from Ericsson Inc. or in accordance with the terms and
# conditions stipulated in the agreement/contract under which the
# program(s) have been supplied.
###########################################################################

startTime=$(date +%s%3N)
DATE=$(date +%d%m%y)
DATE_TIME=$(date +%y%m%d:%H:%M)
SECURE_DATE_FORMAT=$(date '+%b %e %H:%M' -d '1 min ago')
MKDIR="mkdir -p"
HOSTNAME=$(hostname)
SMRS_DDC_PATH=/home/smrs/smrsroot/sftppslog/$DATE/"$HOSTNAME"
SMRS_DDC_FILE=instrumentation.log
SMRS_DDC_FILE_PATH=$SMRS_DDC_PATH/$SMRS_DDC_FILE

CONNECTION_TYPE="SFTP"
SPACE=""
BORDER="------------------------------------------------------------------------------------------------------"
CONNECTION_TYPE_TAG="CONNECTION_TYPE"
READ_TAG="READ"
WRITE_TAG="WRITE"
USE_CASE_TAG="USECASE"
NO_OF_SESSIONS_TAG="NO_OF_SESSIONS"
SUCCESS_SESSION_COUNT_TAG="SUCCESS_SESSIONS_COUNT"
BASENAME=basename
SCRIPT_NAME="${BASENAME} ${0}"
FILETRANSFER_TRANSFER_CONNECTIONS_TAG="FILETRANSFER.TRANSFER_CONNECTIONS"
SECURE_TEMP_FILE="/tmp/secureTempFile"
SECURE_TEMP_CLOSE_FILE="/tmp/secureTempClose.log"

OTHERS_READ=0
OTHERS_WRITE=0
OTHERS_NO_OF_SESSIONS=0
OTHERS_SUCCESS_SESSION_COUNT=0

###########################################################################
# This function will convert data from bytes to Megabytes.
# Argunents: bytes data
# Return: Converted value in MBs
###########################################################################

_bytes_to_MB_conversion(){
echo $1 | awk '{ byte =$1 /1024/1024; print byte}'
}

###########################################################################
# This function will add header to instrumentation.log file which is used for internal troubleshooting.
# Argunents: None
# Return: None
###########################################################################
_addHeaderInFile(){
echo $SPACE >> "$SMRS_DDC_FILE_PATH"
echo $DATE_TIME >> "$SMRS_DDC_FILE_PATH"
echo "$CONNECTION_TYPE_TAG  $NO_OF_SESSIONS_TAG  $READ_TAG             $WRITE_TAG         $USE_CASE_TAG        $SUCCESS_SESSION_COUNT_TAG" >> "$SMRS_DDC_FILE_PATH"
}

###########################################################################
# This function will add CPU usage details to instrumentation.log file which is used for internal troubleshooting.
# Argunents: None
# Return: None
####################################################################
_updateCPUusageDetails(){
echo $SPACE >> "$SMRS_DDC_FILE_PATH"
echo "PID    PPID  TIME    %CPU    ELAPSED  %MEM  RSS    UID USER     CMD" >> "$SMRS_DDC_FILE_PATH"
echo $BORDER >> "$SMRS_DDC_FILE_PATH"
/bin/ps -eo pid,ppid,time,pcpu,etime,pmem,rss,uid,user,cmd | grep "sshd" | grep -v grep >> "$SMRS_DDC_FILE_PATH"
}

###########################################################################
# This function will identify and group the use case/user names, store the resultant vaules in the temporary list.
# Argunents: List which is having usecase names
# Return: List which having segregated usecase names.
####################################################################
_updateWithUsecase(){
case "$1" in
   *"backup"*) tempUserList=(${tempUserList[@]} "backup")
   ;;
   *"software"* | *"tn_system"*) tempUserList=(${tempUserList[@]} "software")
   ;;
   *"certificate"* | *"mm-cert"*) tempUserList=(${tempUserList[@]} "cert")
   ;;
   *"licence"*) tempUserList=(${tempUserList[@]} "licence")
   ;;
   *"pm_push"* | *"tn_pm"* | *"/pm/"* | *"-pm"*) tempUserList=(${tempUserList[@]} "pm")
   ;;
   "mm-laad") tempUserList=(${tempUserList[@]} "laad")
   ;;
   "mm-ai") tempUserList=(${tempUserList[@]} "ai")
   ;;
   *"oradio"*) tempUserList=(${tempUserList[@]} "oradio")
   ;;
   *"/nl/"* | *"-nl-"*) tempUserList=(${tempUserList[@]} "nl")
   ;;
   *"ul_spectrum"*) tempUserList=(${tempUserList[@]} "ul_spectrum")
   ;;
  *) tempUserList=(${tempUserList[@]} "$1")
   ;;
esac
}

###########################################################################
# This function will map the usecase names to generic usecase names which are used to represent the usecase details
# Argunents: $1 usecase
# Return: Respective usecase name
####################################################################
_userNameMap(){
case "$1" in
   "backup") echo "SHM-BACKUP"
   ;;
   "software") echo "SHM-SOFTWARE"
   ;;
    "cert") echo "CERTIFICATE"
   ;;
   "licence") echo "SHM-LICENSE"
   ;;
   "pm") echo "PM"
   ;;
   "laad") echo "LAAD"
   ;;
   "ai") echo "AI"
   ;;
   "oradio") echo "ORADIO"
   ;;
   "ul_spectrum") echo "UL_SPECTRUM"
   ;;
   "nl") echo "NETLOG"
   ;;
  *) echo "OTHERS"
   ;;
esac
}

###########################################################################
# This function will add sftp connection details per usecase to instrumentation.log file which is used for internal troubleshooting.
# Argunents:
# $1 Connection type
# $2 Total number of sessions
# $3 Read size
# $4 Write Size
# $5 Usecase name
# $6 Number of success sessions
# Return: None
####################################################################
_update_sftp_ps_ddc_data() {
if [ ! -d "$SMRS_DDC_PATH" ]; then
    info "Creating directory $SMRS_DDC_FILE_PATH"
    $MKDIR "$SMRS_DDC_FILE_PATH"
fi
printf "%s\t\t|%d\t\t |%s\t |%s\t |%s\t\t |%d\n" "$1" "$2" "$3" "$4" "$5" "$6" >> $SMRS_DDC_FILE_PATH
}

###########################################################################
# This function will send the connection details to the logviewer/elatic log using logger command.
# Argunents:
# $1 Total number of sessions
# $2 Read size
# $3 Write Size
# $4 Usecase name
# $5 Number of success sessions
# Return: None
####################################################################
ddc_info()
{
 logger  -p local2.info -t DDCDATA[$($SCRIPT_NAME)] $FILETRANSFER_TRANSFER_CONNECTIONS_TAG {\"$CONNECTION_TYPE_TAG\":\"$CONNECTION_TYPE\",\"$NO_OF_SESSIONS_TAG\":$1, \"$READ_TAG\":$2, \"$WRITE_TAG\":$3, \"$USE_CASE_TAG\":\"$4\",  \"$SUCCESS_SESSION_COUNT_TAG\":$5}
}

###########################################################################
# This function will process the sftp connections data over a minute
# Argunents: None
# Return: None
####################################################################
_fetchAndUpdatedata(){
grep "$SECURE_DATE_FORMAT" /var/log/secure >> $SECURE_TEMP_FILE
declare -a userList
declare -a finalUserList
declare -a tempUserList
userList=($(grep -E "session closed for user | session opened for user" $SECURE_TEMP_FILE | grep -v "cloud-user" | grep -v "root" | grep -v "jboss_user" | grep -oP '(?<=user )[^ ]*' | sort -u))
userList+=($(grep -i "authentication" $SECURE_TEMP_FILE | grep "sshd" | grep -v "cloud-user" | grep -v "root"| grep -v "jboss_user" | grep -oP '(?<=user=)[^ ]*' | sort -u))
userList+=($(grep -E "open .*mode | close" $SECURE_TEMP_FILE | grep "postauth" | grep -oP '(?<=").*?(?=")' | sort -u))

for data in "${userList[@]}"
do
_updateWithUsecase "$data"
done

finalUserList=($(echo "${tempUserList[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

for useCase in "${finalUserList[@]}"
do
    READ=0
    WRITE=0
    No_of_Sessions=0
    useCaseName=
    declare -a ppidsList
    if [ "$useCase" == "software" ];then
    ppidsList=($(grep -E "session closed for user | session opened for user | authentication.*sshd* | open .*mode | close" $SECURE_TEMP_FILE | grep "$useCase\|tn_system*" | grep -oP '(?<=sshd).*?(?= )' | grep -o '[0-9]*' | sort -u))
    else
    ppidsList=($(grep -E "session closed for user | session opened for user | authentication.*sshd* | open .*mode | close" $SECURE_TEMP_FILE | grep "$useCase"  | grep -oP '(?<=sshd).*?(?= )' | grep -o '[0-9]*' | sort -u))
    fi
    grep "close " $SECURE_TEMP_FILE | grep "$useCase" > $SECURE_TEMP_CLOSE_FILE
    No_of_Sessions=${#ppidsList[@]}
    success_Session_Count=0
    failures_Session_Count=$(grep -E "forced.*[postauth] | failure.*sshd*" "$SECURE_TEMP_FILE" | grep "$useCase" | wc -l)
        while read -r eachLine
        do
          declare -a readValues
          declare -a writeValues
          writeValues=`echo $eachLine | grep -oP '(?<=written ).*?(?=\[)'`
          if [[ $writeValues -le 0 ]];then
            readValues=`echo $eachLine | grep -oP '(?<=read ).*?(?=w)'`
            READ=`expr $READ + $readValues`
          else
            WRITE=`expr $WRITE + $writeValues`
          fi
        done < $SECURE_TEMP_CLOSE_FILE
        readConversion=$(printf '%.6f' $(_bytes_to_MB_conversion $READ))
        ceilReadValue=$(echo "$readConversion" | awk 'function ceil(x, y){y=int(x); return(x>y?y+1:y)} {print ceil($0)}')
        writeConversion=$(printf '%.6f' $(_bytes_to_MB_conversion $WRITE))
        ceilWriteValue=$(echo "$writeConversion" | awk 'function ceil(x, y){y=int(x); return(x>y?y+1:y)} {print ceil($0)}')
        useCaseName="$(_userNameMap $useCase)"
        success_Session_Count=$(($No_of_Sessions - $failures_Session_Count))
        if [[ "$useCaseName" == "OTHERS" ]];then
             OTHERS_READ=$(($OTHERS_READ + $READ))
             OTHERS_WRITE=$(($OTHERS_WRITE + $WRITE))
             OTHERS_NO_OF_SESSIONS=$(($OTHERS_NO_OF_SESSIONS + $No_of_Sessions))
             OTHERS_SUCCESS_SESSION_COUNT=$(($OTHERS_SUCCESS_SESSION_COUNT + $success_Session_Count))
        else
             _update_sftp_ps_ddc_data "${CONNECTION_TYPE}" "${No_of_Sessions}" "${readConversion}" "${writeConversion}" "${useCaseName}" "${success_Session_Count}"
             ddc_info "${No_of_Sessions}" "${ceilReadValue}" "${ceilWriteValue}" "${useCaseName}" "${success_Session_Count}"
        fi
done
if [[ $OTHERS_NO_OF_SESSIONS -gt 0 ]];then
     otherReadConversion=$(printf '%.6f' $(_bytes_to_MB_conversion $OTHERS_READ))
     ceilOtherReadValue=$(echo "$otherReadConversion" | awk 'function ceil(x, y){y=int(x); return(x>y?y+1:y)} {print ceil($0)}')
     otherWriteConversion=$(printf '%.6f' $(_bytes_to_MB_conversion $OTHERS_WRITE))
     ceilOtherWriteValue=$(echo "$otherWriteConversion" | awk 'function ceil(x, y){y=int(x); return(x>y?y+1:y)} {print ceil($0)}')
     _update_sftp_ps_ddc_data "${CONNECTION_TYPE}" "${OTHERS_NO_OF_SESSIONS}" "${otherReadConversion}" "${otherWriteConversion}" "OTHERS" "${OTHERS_SUCCESS_SESSION_COUNT}"
     ddc_info "${OTHERS_NO_OF_SESSIONS}" "${ceilOtherReadValue}" "${ceilOtherWriteValue}" "OTHERS" "${OTHERS_SUCCESS_SESSION_COUNT}"
fi
> $SECURE_TEMP_FILE
> $SECURE_TEMP_CLOSE_FILE
}
> $SECURE_TEMP_FILE
> $SECURE_TEMP_CLOSE_FILE
_addHeaderInFile
_fetchAndUpdatedata
_updateCPUusageDetails
endTime=$(date +%s%3N)
runtime=$((endTime-startTime))
echo "runtime is $runtime milli secs"  >>  "$SMRS_DDC_FILE_PATH"