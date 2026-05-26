"""
dashboard.py
Run: streamlit run dashboard.py
"""

import os
from pathlib import Path
import streamlit as st
import pandas as pd
import psycopg2
from psycopg2.extras import RealDictCursor
from dotenv import load_dotenv

# Load backend/src/.env consistently even when Streamlit is launched from repo root.
_dotenv_path = Path(__file__).resolve().parents[1] / ".env"  # backend/src/.env
load_dotenv(dotenv_path=str(_dotenv_path))

if "DATABASE_URL" not in os.environ and _dotenv_path.exists():
    with open(_dotenv_path) as f:
        for line in f:
            if line.strip() and not line.startswith("#"):
                key, val = line.strip().split("=", 1)
                os.environ[key] = val

st.set_page_config(page_title="DB Viewer", layout="wide")

# Simple login protection
def check_password():
    """Returns True if the user had the correct username and password."""
    def password_entered():
        """Checks whether a password entered by the user is correct."""
        import hashlib
        pwd_hash = hashlib.sha256(st.session_state["password"].encode()).hexdigest()
        if (
            st.session_state["username"] == "admin"
            and pwd_hash == "870e727c5e5f5052ab10927cb477dfbf43a247d3e805ddb803479acc3ca3c310"
        ):
            st.session_state["password_correct"] = True
            del st.session_state["password"]
            del st.session_state["username"]
        else:
            st.session_state["password_correct"] = False

    if "password_correct" not in st.session_state:
        cols = st.columns([1, 2, 1])
        with cols[1]:
            st.subheader("Database Viewer Login")
            st.text_input("Username", key="username")
            st.text_input("Password", type="password", key="password")
            st.button("Log In", on_click=password_entered)
        return False
    elif not st.session_state["password_correct"]:
        cols = st.columns([1, 2, 1])
        with cols[1]:
            st.subheader("Database Viewer Login")
            st.text_input("Username", key="username")
            st.text_input("Password", type="password", key="password")
            st.button("Log In", on_click=password_entered)
            st.error(" User not known or password incorrect")
        return False
    else:
        return True

if not check_password():
    st.stop()

# ─── DB ─────────────────────────────────────────────────────

@st.cache_resource
def get_connection():
    return psycopg2.connect(os.environ["DATABASE_URL"])


def query(sql):
    conn = get_connection()
    if conn.closed != 0:
        get_connection.clear()
        conn = get_connection()

    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(sql)
            rows = cur.fetchall()
        return pd.DataFrame([dict(r) for r in rows])

    except Exception as e:
        if conn.closed == 0:
            conn.rollback()
        st.error(f"Query error: {e}")
        return pd.DataFrame()


# ─── Sidebar ────────────────────────────────────────────────

st.sidebar.title("DB Tables")

tables = [
    "users",
    "sessions",
    "vmaf_results",
    "peaq_results",
    "pesq_results",
    "iqa_results",
]

selected_table = st.sidebar.selectbox("Select Table", tables)
limit = st.sidebar.number_input("Limit rows", min_value=10, max_value=10000, value=100)
show_raw = st.sidebar.checkbox("Show raw_output column", value=False)


# ─── Column sets (derived from schema.sql) ──────────────────
# raw_output is excluded by default — it can be 10s of MB per row
# and will exceed Streamlit's 200 MB message limit quickly.
# Enable it via the sidebar checkbox when needed.

users_cols    = "*"
sessions_cols = "*"

vmaf_cols = """
    id, session_id, created_at,
    filename, file_size_bytes,
    vmaf_score,
    status
"""

peaq_cols = """
    id, session_id, created_at,
    degraded_filename, noise_filename, has_noise_reduction,
    raw_odg, odg_score AS wiener_odg, ffmpeg_odg,
    odg_label
"""

pesq_cols = """
    id, session_id, created_at,
    call_type, recorded_filename,
    direct_pesq, pstn_pesq, volte_pesq, voip_pesq
"""

iqa_cols = """
    id, session_id, created_at,
    image_index, filename, file_size_bytes,
    brisque, niqe, piqe,
    camera_score
"""

# Append raw_output only when the user explicitly opts in
RAW_TABLES = {"vmaf_results", "peaq_results", "pesq_results", "iqa_results"}

col_map = {
    "users":        (users_cols,    "created_at"),
    "sessions":     (sessions_cols, "created_at"),
    "vmaf_results": (vmaf_cols,     "created_at"),
    "peaq_results": (peaq_cols,     "created_at"),
    "pesq_results": (pesq_cols,     "created_at"),
    "iqa_results":  (iqa_cols,      "created_at"),
}

# ─── Main ───────────────────────────────────────────────────

st.title("Database Viewer")

cols, order_col = col_map[selected_table]

if show_raw and selected_table in RAW_TABLES:
    cols = cols.rstrip() + ", raw_output"

df = query(
    f"SELECT {cols} FROM {selected_table} ORDER BY {order_col} DESC LIMIT {limit}"
)

if df.empty:
    st.warning("No data found.")
else:
    st.write(f"Showing **{len(df)}** rows from `{selected_table}`")
    st.dataframe(df, use_container_width=True, hide_index=True)

    st.download_button(
        "⬇ Download CSV",
        df.to_csv(index=False),
        f"{selected_table}.csv",
        "text/csv",
    )