import streamlit as st
import os
import cv2
import shutil
from pathlib import Path
from datetime import datetime
from PIL import Image

# ─── PATH SETUP ─────────────────────────────────────────────────────────────
BASE_DIR = Path(__file__).resolve().parents[1]
DATA_DIR = BASE_DIR / "data"

st.set_page_config(
    page_title="Data Management Terminal", 
    layout="wide", 
    initial_sidebar_state="expanded"
)

# ─── PRECISION DARK CSS ─────────────────────────────────────────────────────
st.markdown("""
    <style>
    /* Main Background */
    .stApp {
        background-color: #0e1117;
        color: #e0e0e0;
    }

    /* Reduce Top Padding */
    .block-container {
        padding-top: 2rem !important;
        padding-bottom: 0rem !important;
    }

    /* Hide Header */
    header {
        visibility: hidden;
    }
    
    /* Global Text visibility */
    .stText, .stMarkdown p, .stMarkdown li, span, label {
        color: #e0e0e0 !important;
    }
    
    /* Headers */
    h1, h2, h3 {
        color: #ffffff !important;
        font-weight: 700 !important;
        letter-spacing: -0.5px !important;
    }
    
    /* Sidebar styling */
    [data-testid="stSidebar"] {
        background-color: #161b22;
        border-right: 1px solid #30363d;
    }
    
    /* Left Column: Full-Height Inventory */
    div.row-widget.stRadio > div [role="radiogroup"] {
        background-color: #161b22;
        border-radius: 8px;
        border: 1px solid #30363d;
        padding: 10px;
        height: 82vh; /* Anchor list to bottom */
        overflow-y: auto;
    }
    
    div.row-widget.stRadio > div [role="radiogroup"] > label {
        padding: 10px 14px;
        border-radius: 6px;
        transition: background-color 0.2s;
        border-bottom: 1px solid #21262d;
    }
    
    div.row-widget.stRadio > div [role="radiogroup"] > label:hover {
        background-color: #21262d;
    }

    /* Right Column: Split containers */
    .stSubheader {
        margin-top: -1.5rem !important;
        margin-bottom: 0.5rem !important;
    }

    /* Target the fixed-height containers - Removed borders/backgrounds */
    [data-testid="stElementContainer"] > div:has(div[data-testid="stVerticalBlockBorderWrapper"]) {
        border: none !important;
        background-color: transparent !important;
    }

    /* Professional Image Window for IQA */
    [data-testid="stImage"], [data-testid="stVideo"], [data-testid="stAudio"] {
        display: flex !important;
        justify-content: center !important;
        align-items: center !important;
        background-color: transparent !important;
        border-radius: 8px;
        padding: 0 !important;
        text-align: center !important;
        width: 100% !important;
    }
    
    img {
        max-height: 680px !important; 
        width: auto !important;
        object-fit: contain !important;
        box-shadow: 0 8px 16px rgba(0,0,0,0.6);
        margin: auto !important;
        display: block !important;
    }
    
    /* Remove redundant padding from selection */
    [role="radiogroup"] {
        padding-top: 0 !important;
    }

    /* Vertical Divider between Files and Visualizer */
    [data-testid="column"]:first-child {
        border-right: 1px solid #30363d !important;
        padding-right: 2rem !important;
    }

    /* Metadata Specification Layout */
    .detail-label {
        color: #8b949e !important;
        font-size: 0.7rem !important;
        text-transform: uppercase !important;
        letter-spacing: 1px !important;
        font-weight: 600 !important;
        margin-bottom: 4px !important;
    }
    
    .detail-value {
        color: #f0f6fc !important;
        font-size: 0.9rem !important;
        font-weight: 500 !important;
        margin-bottom: 1rem !important;
    }

    /* Divider */
    hr {
        margin: 1.5rem 0 !important;
        border-top: 1px solid #30363d !important;
    }

    /* Adjust Streamlit column padding */
    [data-testid="column"] {
        padding: 0 1rem !important;
    }
    
    /* Hide radio dot but keep label clickable */
    [data-testid="stWidgetLabel"] {
        display: none;
    }
    </style>
    """, unsafe_allow_html=True)

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
            st.subheader("Data Management Login")
            st.text_input("Username", key="username")
            st.text_input("Password", type="password", key="password")
            st.button("Log In", on_click=password_entered)
        return False
    elif not st.session_state["password_correct"]:
        cols = st.columns([1, 2, 1])
        with cols[1]:
            st.subheader("Data Management Login")
            st.text_input("Username", key="username")
            st.text_input("Password", type="password", key="password")
            st.button("Log In", on_click=password_entered)
            st.error(" User not known or password incorrect")
        return False
    else:
        return True

if not check_password():
    st.stop()

st.title("Data Management Terminal")

# ─── NAVIGATION ─────────────────────────────────────────────────────────────
CATEGORIES = {
    "VMAF Analysis": "vmaf",
    "IQA Evaluation": "iqa",
    "PEAQ Audio": "peaq",
    "PESQ Audio": "pesq"
}

category_label = st.sidebar.selectbox("Analysis Domain", list(CATEGORIES.keys()))
category_folder = CATEGORIES[category_label]
target_dir = DATA_DIR / category_folder

# ─── DATA LOADING ───────────────────────────────────────────────────────────
if not target_dir.exists():
    st.info(f"Domain '{category_label}' initialized. Waiting for incoming data streams.")
    st.stop()

try:
    files = sorted(
        [f for f in target_dir.iterdir() if f.is_file() and not f.name.startswith(".")],
        key=lambda x: x.stat().st_mtime,
        reverse=True
    )
except Exception as e:
    st.error(f"Access Denied: {e}")
    st.stop()

file_search = st.sidebar.text_input("Filter Files", placeholder="Enter query...")
if file_search:
    files = [f for f in files if file_search.lower() in f.name.lower()]

st.sidebar.markdown(f"**Selected Category Records:** {len(files)}")

if not files:
    st.sidebar.warning("No records matched filters.")
    st.info(f"No records available in '{category_label}'.")
    st.stop()

# ─── PRECISION GRID ─────────────────────────────────────────────────────────
col_inventory, col_visualizer = st.columns([1, 1], gap="medium")

# LEFT 1/2: INVENTORY (Full Height via Container)
with col_inventory:
    st.subheader("Files")
    with st.container(height=750, border=False):
        selected_filename = st.radio(
            label="Select a record",
            options=[f.name for f in files],
            key="file_selection",
            label_visibility="collapsed"
        )

# RIGHT 1/2: VISUALIZER (5/8) & SPECIFICATIONS (3/8)
with col_visualizer:
    # 5/8 Portion: Visualizer Window
    st.subheader("Visualizer")
    # Using fixed-height container to prevent "flowing" or jumping
    with st.container(height=720, border=False):
        if selected_filename:
            file_path = target_dir / selected_filename
            ext = file_path.suffix.lower()
            
            try:
                if ext in [".mp4", ".mov", ".avi", ".mkv"]:
                    st.video(str(file_path))
                elif ext in [".jpg", ".jpeg", ".png", ".webp", ".gif"]:
                    # Removed use_container_width to allow natural scaling within max-height
                    st.image(str(file_path), use_container_width=False)
                elif ext in [".wav", ".mp3", ".ogg", ".flac"]:
                    st.audio(str(file_path))
                else:
                    st.info("System preview not available.")
            except Exception as e:
                st.error(f"Render Error: {e}")
        else:
            st.info("Select a record to initialize.")

    # 3/8 Portion: Specifications
    st.subheader("Specifications")
    if selected_filename:
        file_path = target_dir / selected_filename
        stats = file_path.stat()
        file_size_mb = stats.st_size / (1024 * 1024)
        mod_time = datetime.fromtimestamp(stats.st_mtime).strftime('%Y-%m-%d %H:%M:%S')
        
        # Metadata Columns
        c1, c2 = st.columns(2)
        with c1:
            st.markdown(f'<p class="detail-label">Payload Name</p><p class="detail-value">{selected_filename}</p>', unsafe_allow_html=True)
            st.markdown(f'<p class="detail-label">File Size</p><p class="detail-value">{file_size_mb:.3f} MB</p>', unsafe_allow_html=True)
        with c2:
            st.markdown(f'<p class="detail-label">Last Modified</p><p class="detail-value">{mod_time}</p>', unsafe_allow_html=True)
            if ext in [".jpg", ".jpeg", ".png", ".webp", ".gif"]:
                try:
                    with Image.open(file_path) as img:
                        w, h = img.size
                        st.markdown(f'<p class="detail-label">Resolution</p><p class="detail-value">{w} × {h}</p>', unsafe_allow_html=True)
                except:
                    pass
            elif ext in [".mp4", ".mov", ".avi", ".mkv"]:
                try:
                    cap = cv2.VideoCapture(str(file_path))
                    if cap.isOpened():
                        w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
                        h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
                        fps = cap.get(cv2.CAP_PROP_FPS)
                        frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
                        duration = frames / fps if fps > 0 else 0
                        
                        st.markdown(f'<p class="detail-label">Resolution</p><p class="detail-value">{w} × {h}</p>', unsafe_allow_html=True)
                        st.markdown(f'<p class="detail-label">Frame Rate</p><p class="detail-value">{fps:.2f} FPS</p>', unsafe_allow_html=True)
                        st.markdown(f'<p class="detail-label">Duration</p><p class="detail-value">{duration:.2f} seconds</p>', unsafe_allow_html=True)
                    cap.release()
                except:
                    pass
            st.markdown(f'<p class="detail-label">Cluster Location</p><p class="detail-value">storage://{category_folder}/</p>', unsafe_allow_html=True)

        with open(file_path, "rb") as f:
            st.download_button(
                label="Export Raw Resource",
                data=f,
                file_name=selected_filename,
                mime="application/octet-stream"
            )

st.sidebar.divider()
st.sidebar.markdown("### Storage Status")
try:
    total, used, free = shutil.disk_usage("/")
    percent_used = (used / total) * 100
    
    # Calculate Data Directory Size
    data_size_bytes = sum(f.stat().st_size for f in DATA_DIR.glob('**/*') if f.is_file())
    data_size_mb = data_size_bytes / (1024 * 1024)
    
    st.sidebar.markdown(f"**Data Folder Size:** {data_size_mb:.2f} MB")
    st.sidebar.markdown(f"**Total Disk:** {total // (2**30)} GB")
    st.sidebar.markdown(f"**Free Space:** {free // (2**30)} GB")
    st.sidebar.progress(percent_used / 100, text=f"{percent_used:.1f}% Used")
except Exception as e:
    st.sidebar.error("Storage metrics unavailable.")
