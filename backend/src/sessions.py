"""
Session-based result logging for field testing.

Manages test sessions (one per phone) and logs PEAQ/PESQ results
to a CSV file for easy analysis in Excel/Google Sheets.
"""

import csv
import uuid
from datetime import datetime
from pathlib import Path
from threading import Lock

# CSV file lives next to the backend code
RESULTS_DIR = Path(__file__).resolve().parent.parent / "test_results"
RESULTS_CSV = RESULTS_DIR / "results.csv"

# Thread-safe write lock
_csv_lock = Lock()

# CSV column headers
HEADERS = [
    "session_id",
    "phone_model",
    "tester_name",
    "timestamp",
    "test_type",
    # PEAQ columns
    "peaq_raw_odg",
    "peaq_wiener_odg",
    "peaq_ffmpeg_odg",
    "peaq_lsd",
    # PESQ columns
    "pesq_direct",
    "pesq_pstn",
    "pesq_volte",
    "pesq_voip",
    # Notes
    "notes",
]

# In-memory session store (session_id → metadata)
_sessions: dict[str, dict] = {}


def _ensure_csv():
    """Create the CSV file with headers if it doesn't exist."""
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    if not RESULTS_CSV.exists():
        with open(RESULTS_CSV, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=HEADERS)
            writer.writeheader()


def create_session(phone_model: str, tester_name: str = "") -> dict:
    """
    Create a new test session for a phone.

    Returns:
        dict with session_id and metadata
    """
    session_id = str(uuid.uuid4())[:8]  # Short ID: e.g., "a1b2c3d4"
    session = {
        "session_id": session_id,
        "phone_model": phone_model,
        "tester_name": tester_name,
        "created_at": datetime.now().isoformat(),
    }
    _sessions[session_id] = session
    return session


def get_session(session_id: str) -> dict | None:
    """Get session metadata by ID."""
    return _sessions.get(session_id)


def log_result(
    session_id: str,
    test_type: str,
    results: dict,
    notes: str = "",
) -> dict:
    """
    Log a test result to the CSV file.

    Args:
        session_id: The session ID from create_session
        test_type: "peaq" or "pesq"
        results: Dict of score values
        notes: Optional notes about this test

    Returns:
        The logged row as a dict
    """
    session = _sessions.get(session_id)
    if session is None:
        # Allow logging even without a pre-created session
        session = {"phone_model": "unknown", "tester_name": ""}

    _ensure_csv()

    row = {h: "" for h in HEADERS}
    row["session_id"] = session_id
    row["phone_model"] = session.get("phone_model", "unknown")
    row["tester_name"] = session.get("tester_name", "")
    row["timestamp"] = datetime.now().isoformat()
    row["test_type"] = test_type
    row["notes"] = notes

    # Fill in score columns from results
    if test_type == "peaq":
        row["peaq_raw_odg"] = results.get("raw_odg", "")
        row["peaq_wiener_odg"] = results.get("wiener_odg", "")
        row["peaq_ffmpeg_odg"] = results.get("ffmpeg_odg", "")
        row["peaq_lsd"] = results.get("lsd", "")
    elif test_type == "pesq":
        row["pesq_direct"] = results.get("direct", "")
        row["pesq_pstn"] = results.get("pstn", "")
        row["pesq_volte"] = results.get("volte", "")
        row["pesq_voip"] = results.get("voip", "")

    with _csv_lock:
        with open(RESULTS_CSV, "a", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=HEADERS)
            writer.writerow(row)

    return row


def get_all_results() -> list[dict]:
    """Read all results from the CSV file."""
    _ensure_csv()
    with open(RESULTS_CSV, "r", newline="") as f:
        reader = csv.DictReader(f)
        return list(reader)


def get_csv_path() -> Path:
    """Return the path to the CSV file."""
    _ensure_csv()
    return RESULTS_CSV
