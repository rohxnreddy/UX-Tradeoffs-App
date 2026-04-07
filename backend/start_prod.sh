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
WORKERS=$(($(nproc) * 2 + 1))

LOG_DIR="logs"
PID_FILE="gunicorn.pid"
STREAMLIT_PID_FILE="streamlit.pid"
STREAMLIT_APP="src/db/dashboard.py"
STREAMLIT_PORT="8501"

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
        echo "Streamlit already running with PID $S_PID"
        exit 1
    else
        echo "Removing stale Streamlit PID file"
        rm -f $STREAMLIT_PID_FILE
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
    > /dev/null 2>&1 &

# ─── SAVE PID ────────────────────────────────
echo $! > $PID_FILE

# ─── START STREAMLIT ──────────────────────────
echo "Starting Streamlit dashboard..."
nohup streamlit run $STREAMLIT_APP \
    --server.port $STREAMLIT_PORT \
    --server.address $HOST \
    --server.headless true \
    > $LOG_DIR/dashboard.log 2>&1 &

# ─── SAVE STREAMLIT PID ───────────────────────
echo $! > $STREAMLIT_PID_FILE

echo "Server started successfully!"
echo "PID: $(cat $PID_FILE)"
echo "Streamlit PID: $(cat $STREAMLIT_PID_FILE)"
echo "Logs: $LOG_DIR/"