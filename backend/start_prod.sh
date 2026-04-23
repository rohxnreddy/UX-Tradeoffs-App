#!/bin/bash

# env loading
set -a
source .env
set +a

# ─── VIRTUAL ENV ──────────────────────────────
if [ -d "venv" ]; then
    echo "Activating virtual environment..."
    source venv/bin/activate
fi

# ─── CONFIG ───────────────────────────────────
APP_MODULE="src.app:app"
HOST="0.0.0.0"
PORT="8000"
WORKERS=3

LOG_DIR="logs"
PID_FILE="gunicorn.pid"
STREAMLIT_PID_FILE="streamlit.pid"
STREAMLIT_APP="src/db/dashboard.py"
STREAMLIT_PORT="8501"

DATA_VIEWER_PID_FILE="data_viewer.pid"
DATA_VIEWER_APP="src/data_viewer.py"
DATA_VIEWER_PORT="8502"

# ─── SETUP ───────────────────────────────────
mkdir -p $LOG_DIR

echo "Starting server..."

# ─── PREVENT MULTIPLE INSTANCES ───────────────
if [ -f $PID_FILE ]; then
    PID=$(cat $PID_FILE)
    if ps -p $PID > /dev/null 2>&1; then
        echo "Server already running with PID $PID"
        exit 1
    else
        echo "Removing stale PID file"
        rm -f $PID_FILE
    fi
fi

if [ -f $STREAMLIT_PID_FILE ]; then
    S_PID=$(cat $STREAMLIT_PID_FILE)
    if ps -p $S_PID > /dev/null 2>&1; then
        echo "Streamlit dashboard already running with PID $S_PID"
        exit 1
    else
        echo "Removing stale Streamlit PID file"
        rm -f $STREAMLIT_PID_FILE
    fi
fi

if [ -f $DATA_VIEWER_PID_FILE ]; then
    D_PID=$(cat $DATA_VIEWER_PID_FILE)
    if ps -p $D_PID > /dev/null 2>&1; then
        echo "Data Viewer already running with PID $D_PID"
        exit 1
    else
        echo "Removing stale Data Viewer PID file"
        rm -f $DATA_VIEWER_PID_FILE
    fi
fi

# ─── START GUNICORN ───────────────────────────
nohup gunicorn $APP_MODULE \
    --worker-class uvicorn.workers.UvicornWorker \
    --workers $WORKERS \
    --bind $HOST:$PORT \
    --timeout 120 \
    --keep-alive 5 \
    --log-level info \
    --access-logfile $LOG_DIR/access.log \
    --error-logfile $LOG_DIR/error.log \
    --pid $PID_FILE \
    > /dev/null 2>&1 &

# ─── START STREAMLIT ──────────────────────────
echo "Starting Streamlit dashboard..."
nohup streamlit run $STREAMLIT_APP \
    --server.port $STREAMLIT_PORT \
    --server.address $HOST \
    --server.headless true \
    > $LOG_DIR/dashboard.log 2>&1 &

# ─── SAVE STREAMLIT PID ───────────────────────
echo $! > $STREAMLIT_PID_FILE

# ─── START DATA VIEWER ────────────────────────
echo "Starting Streamlit data viewer..."
nohup streamlit run $DATA_VIEWER_APP \
    --server.port $DATA_VIEWER_PORT \
    --server.address $HOST \
    --server.headless true \
    > $LOG_DIR/data_viewer.log 2>&1 &

# ─── SAVE DATA VIEWER PID ─────────────────────
echo $! > $DATA_VIEWER_PID_FILE

sleep 2

echo "Server started successfully!"
if [ -f $PID_FILE ]; then
    echo "PID: $(cat $PID_FILE)"
else
    echo "PID: Gunicorn PID file not found yet"
fi
echo "Streamlit PID: $(cat $STREAMLIT_PID_FILE)"
echo "Data Viewer PID: $(cat $DATA_VIEWER_PID_FILE)"
echo "Logs: $LOG_DIR/"