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

#source the file which provides global properties in an associative array GLOBAL_PROPERTIES_ARRAY
. $JBOSS_HOME/bin/jbosslogger
#source the file which provides global properties in an associative array GLOBAL_PROPERTIES_ARRAY
. $JBOSS_HOME/bin/retrieve_global_properties
readonly PING6="/bin/ping6"
readonly IP6="/sbin/ip -6"
add_vip_if_not_present()
{
    vip="$1"
    #remove network suffix from vip
    vip_non_cidr=${vip%%/*}
    if $PING6 -q -c 2 -I lo "$vip_non_cidr" > /dev/null
    then
        info "able to ping6 $vip_non_cidr from loopback interface, so it is already added"
    else
        if $IP6 addr add "$vip" dev lo
        then
            info "Successfully added $vip to loopback interface"
        else
            error "Failed to add $vip to loopback interface, program will exit"
            exit 1
        fi
    fi
}
#Main starts here
cm_ip6_VIP=${GLOBAL_PROPERTIES_ARRAY[svc_CM_vip_ipv6address]}
fm_ip6_VIP=${GLOBAL_PROPERTIES_ARRAY[svc_FM_vip_ipv6address]}
if [ "$cm_ip6_VIP" == "" ]
then
    info "svc_CM_vip_ipv6address address is not present in global.properties( may be IPv4 setup ), so skipping Direct Routing"
    exit 0
else
     add_vip_if_not_present "$cm_ip6_VIP"
     add_vip_if_not_present "$fm_ip6_VIP"
fi
