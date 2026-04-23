#!/bin/bash

PID_FILE="gunicorn.pid"
STREAMLIT_PID_FILE="streamlit.pid"
DATA_VIEWER_PID_FILE="data_viewer.pid"

# ─── STOP GUNICORN ────────────────────────────
if [ -f $PID_FILE ]; then
    PID=$(cat $PID_FILE)
    if ps -p $PID > /dev/null 2>&1; then
        kill $PID
        echo "Waiting for Gunicorn server to stop (PID: $PID)..."
        while ps -p $PID > /dev/null 2>&1; do sleep 1; done
        echo "Gunicorn server stopped"
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

# ─── STOP DATA VIEWER ─────────────────────────
if [ -f $DATA_VIEWER_PID_FILE ]; then
    D_PID=$(cat $DATA_VIEWER_PID_FILE)
    if ps -p $D_PID > /dev/null 2>&1; then
        kill $D_PID
        echo "Data Viewer stopped (PID: $D_PID)"
    else
        echo "Data Viewer process not running, removing stale PID file"
    fi
    rm -f $DATA_VIEWER_PID_FILE
else
    echo "No Data Viewer PID file found"
fi