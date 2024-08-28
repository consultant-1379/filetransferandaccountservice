#!/bin/bash

###########################################################################
# COPYRIGHT Ericsson 2021
#
# The copyright to the computer program(s) herein is the property of
# Ericsson Inc. The programs may be used and/or copied only with written
# permission from Ericsson Inc. or in accordance with the terms and
# conditions stipulated in the agreement/contract under which the
# program(s) have been supplied.
#
# This script requires bash 4 or above
#
# Performs required configurations for enabling Direct Routing for IPv6
##########################################################################

readonly PING6="/bin/ping6"
readonly IP6="/sbin/ip -6"

#/////////////////////////////////////////////////////////////
# Action :
#    Responsible for adding the vip if it's not currently
#    present.
# Globals :
#   None
# Arguments:
#    $1 - the vip to add
# Returns:
#/////////////////////////////////////////////////////////////
add_vip_if_not_present()
{
    vip="$1"
    # remove network suffix from vip
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

#/////////////////////////////////////////////////////////////
# Action :
#   main program
# Globals :
#   None
# Arguments:
#   None
# Returns:
#/////////////////////////////////////////////////////////////
cm_ip6_VIP=$(cat /ericsson/tor/data/global.properties | grep svc_CM_vip_ipv6address | cut -d '=' -f2)
fm_ip6_VIP=$(cat /ericsson/tor/data/global.properties | grep svc_FM_vip_ipv6address | cut -d '=' -f2)
if [ "$cm_ip6_VIP" == "" ]
then
    info "svc_CM_vip_ipv6address address is not present in global.properties( may be IPv4 setup ), so skipping Direct Routing"
    exit 0
else
    add_vip_if_not_present "$cm_ip6_VIP"
    add_vip_if_not_present "$fm_ip6_VIP"
fi
