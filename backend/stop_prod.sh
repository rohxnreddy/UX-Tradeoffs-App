#!/bin/bash

PID_FILE="gunicorn.pid"

if [ ! -f $PID_FILE ]; then
    echo "No PID file found"
    exit 1
fi

PID=$(cat $PID_FILE)

if ps -p $PID > /dev/null 2>&1; then
    kill $PID
    echo "Server stopped"
else
    echo "Process not running"
fi

rm -f $PID_FILE