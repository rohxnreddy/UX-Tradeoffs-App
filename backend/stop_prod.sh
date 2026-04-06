#!/bin/bash

PID_FILE="gunicorn.pid"
STREAMLIT_PID_FILE="streamlit.pid"

# ─── STOP GUNICORN ────────────────────────────
if [ -f $PID_FILE ]; then
    PID=$(cat $PID_FILE)
    if ps -p $PID > /dev/null 2>&1; then
        kill $PID
        echo "Gunicorn server stopped (PID: $PID)"
    else
        echo "Gunicorn process not running, removing stale PID file"
    fi
    rm -f $PID_FILE
else
    echo "No Gunicorn PID file found"
fi

# ─── STOP STREAMLIT ───────────────────────────
if [ -f $STREAMLIT_PID_FILE ]; then
    S_PID=$(cat $STREAMLIT_PID_FILE)
    if ps -p $S_PID > /dev/null 2>&1; then
        kill $S_PID
        echo "Streamlit dashboard stopped (PID: $S_PID)"
    else
        echo "Streamlit process not running, removing stale PID file"
    fi
    rm -f $STREAMLIT_PID_FILE
else
    echo "No Streamlit PID file found"
fi