#!/bin/sh

echo "Starting Lacework Agent datacollector"
/var/lib/lacework/datacollector &

while [ ! -f /var/log/lacework/datacollector.log ]; do
    echo "Waiting for log file"
    sleep 1
done

echo "Tailing log file"
tail -f /var/log/lacework/datacollector.log
