#!/bin/sh

if [ ! -f /var/lib/lacework/datacollector.pid ]; then
    exit -1
fi

DATACOLLECTOR_PID=$(cat /var/lib/lacework/datacollector.pid)
DATACOLLECTOR_STAT=$(cat "/proc/$DATACOLLECTOR_PID/stat")
DATACOLLECTOR_STATE=$(echo $DATACOLLECTOR_STAT | awk '{ print $3; }')

case $DATACOLLECTOR_STATE in
    R|S)
        echo "Running code [$DATACOLLECTOR_STATE]"
        exit 0
    ;;
    *)
        echo "Not running code [$DATACOLLECTOR_STATE]"
        exit -2
    ;;
esac
