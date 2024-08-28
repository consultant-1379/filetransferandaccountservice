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

IPV6_GC_THRESHOLD3="$(cat /proc/sys/net/ipv6/neigh/default/gc_thresh3)"
IPV4_GC_THRESHOLD3="$(cat /proc/sys/net/ipv4/neigh/default/gc_thresh3)"

echo "Setting the new value for gc_threshold"
#update ipv6 gc_threshold3
if [ "$IPV6_GC_THRESHOLD3 " -lt 2048 ]
    then
    if ! sysctl -w net.ipv6.neigh.default.gc_thresh3=2048
        then
        logger "Changing Threshold value3 for ipv6 has been failed"
    fi
else
    logger "The threshold is already set to 2048"
fi
if [ "$IPV4_GC_THRESHOLD3 " -lt 2048 ]
    then
    if ! sysctl -w net.ipv4.neigh.default.gc_thresh3=2048
        then
        logger "Changing Threshold value3 ipv4 has been failed"
    fi
else
    logger "The threshold is already set to 2048"
fi

exit 0