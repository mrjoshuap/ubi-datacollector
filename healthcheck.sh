#!/bin/sh

if [ ! -f /var/lib/lacework/datacollector.pid ]; then
    echo "Not running (no pid file)"
    exit 1
fi

if [ ! -f /var/lib/lacework/datacollector.lock ]; then
    echo "Not running (no lock file)"
    exit 2
fi

if [ ! -e /var/lib/lacework/datacollector.sock ]; then
    echo "Not running (no sock file)"
    exit 3
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
        exit 4
    ;;
esac
