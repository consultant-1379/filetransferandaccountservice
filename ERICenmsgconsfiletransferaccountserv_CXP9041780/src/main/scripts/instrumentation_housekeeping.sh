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

LOG_TAG="INSTRUMENTATION_HOUSEKEEPING"
SCRIPT_NAME="${0}"
SFTP_INSTRMN_LOGS_DIR='/home/smrs/smrsroot/sftppslog/'


###########################################################################
# standard linux commands
###########################################################################
_ECHO="/bin/echo"
_MKDIR="/bin/mkdir -p"
_GREP="/bin/grep"


############################################################################
# This function will print an error message to /var/log/messages
# Arguments:
#       $1 - Message
# Return: None
###########################################################################
error()
{
    logger  -t ${LOG_TAG} -p user.err "ERROR ( ${SCRIPT_NAME} ): $1"
}
info()
{
    logger  -t ${LOG_TAG} -p user.notice "INFORMATION ( ${SCRIPT_NAME} ): $1"
}

###########################################################################
# This function is used to list the directories which are 30 days older
# or above
#
###########################################################################
instrumentation_Housekeeping_List() {
info "Collecting the directories to be deleted"
find "$SFTP_INSTRMN_LOGS_DIR" -maxdepth 1 -type d -mtime +30 | grep -E '[0-9]{6}$' > /home/smrs/smrsroot/sftppslog/directories_to_delete.txt
info "Directories to be deleted listed in directories_to_delete.txt"
}

##########################################################################
# This function performs the instrumentation housekeeping by deleting
# the directories that are listed
#
##########################################################################
instrumentation_Housekeeping() {

start=$(date +%s%N)
directory_count=1
while read directory;

do

if [ `expr $directory_count % 20` -eq 0 ];
then
        echo "Sleeping before next deletion"
        sleep 4
fi
if [[ -d "$directory" ]];
then
        rm -rf "$directory"
        ((directory_count++))
fi
done < /home/smrs/smrsroot/sftppslog/directories_to_delete.txt

end=$(date +%s%N)

info "Elapsed time for instrumentation housekeeping: $(($end-$start)) ns"

}


instrumentation_Housekeeping_List
instrumentation_Housekeeping

exit 0
