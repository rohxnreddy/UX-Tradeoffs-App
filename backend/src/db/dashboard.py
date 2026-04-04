"""
dashboard.py
Run: streamlit run dashboard.py
"""

import os
import streamlit as st
import pandas as pd
import psycopg2
from psycopg2.extras import RealDictCursor
from dotenv import load_dotenv

load_dotenv()

st.set_page_config(page_title="DB Viewer", layout="wide")

# ─── DB ─────────────────────────────────────────────────────

@st.cache_resource
def get_connection():
    return psycopg2.connect(os.environ["DATABASE_URL"])


def query(sql):
    conn = get_connection()
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(sql)
            rows = cur.fetchall()
        return pd.DataFrame([dict(r) for r in rows])

    except Exception as e:
        conn.rollback()
        st.error(f"Query error: {e}")
        return pd.DataFrame()


# ─── Sidebar ────────────────────────────────────────────────

st.sidebar.title("DB Tables")

tables = [
    "device_sessions",
    "vmaf_results",
    "peaq_results",
    "pesq_results",
    "iqa_results"
]

selected_table = st.sidebar.selectbox("Select Table", tables)

limit = st.sidebar.number_input("Limit rows", min_value=10, max_value=10000, value=100)


# ─── Main ───────────────────────────────────────────────────

st.title("Database Viewer")

peaq_cols = """id, session_id, created_at,
    degraded_filename, noise_filename, has_noise_reduction,
    raw_odg, odg_score AS wiener_odg, ffmpeg_odg,
    odg_label, subtracted_audio_b64, raw_output"""

webrtc_cols = """id, session_id, created_at,
    call_type, recorded_filename,
    direct_pesq, pstn_pesq, volte_pesq, voip_pesq,
    degraded_audio_b64, raw_output"""

if selected_table == "peaq_results":
    df = query(f"SELECT {peaq_cols} FROM {selected_table} ORDER BY created_at DESC LIMIT {limit}")
elif selected_table == "pesq_results":
    df = query(f"SELECT {webrtc_cols} FROM {selected_table} ORDER BY created_at DESC LIMIT {limit}")
else:
    df = query(f"SELECT * FROM {selected_table} ORDER BY 1 DESC LIMIT {limit}")

if df.empty:
    st.warning("No data found.")
else:
    st.write(f"Showing {len(df)} rows from `{selected_table}`")
    st.dataframe(df, use_container_width=True, hide_index=True)

    st.download_button(
        "Download CSV",
        df.to_csv(index=False),
        f"{selected_table}.csv",
        "text/csv"
    )