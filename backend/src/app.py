from fastapi import FastAPI, HTTPException, File, UploadFile, Form, Depends
from fastapi.responses import FileResponse
from src.database import create_db_and_tables, get_async_session
from sqlalchemy.ext.asyncio import AsyncSession
from contextlib import asynccontextmanager
from sqlalchemy import select
from pathlib import Path
from tempfile import NamedTemporaryFile

from src.vmaf.vmaf import compute_vmaf
from src.peaq.peaq import compute_peaq_odg, PEAQError
from src.pesq_module.pesq_score import compute_pesq, compute_pesq_comparison, PESQError
from src.webrtc.codec_call import make_webrtc_call, make_device_webrtc_call
from src.IMA.IMA import compute_iqa
from src.sessions import create_session, log_result, get_all_results, get_csv_path

# Audio files directory
AUDIO_DIR = Path(__file__).resolve().parent.parent / "peaq-pesq-audio"


@asynccontextmanager
async def lifespan(app: FastAPI):
    try:
        await create_db_and_tables()
    except Exception as e:
        print(f"⚠️  Database connection failed (non-critical): {e}")
        print("   Server will start without database. Audio/video features still work.")
    yield

app = FastAPI(lifespan=lifespan)


@app.get("/")
def init():
    return {"message": "Server is Up!"}


# ─── Sessions ─────────────────────────────────────────────────────

@app.post("/sessions/create")
async def create_test_session(
    phone_model: str = Form(...),
    tester_name: str = Form(""),
):
    """Create a new test session for a phone. Returns a short session ID."""
    session = create_session(phone_model, tester_name)
    return session


@app.post("/sessions/{session_id}/log")
async def log_test_result(
    session_id: str,
    test_type: str = Form(...),
    results: str = Form(...),
    notes: str = Form(""),
):
    """Manually log a test result for a session."""
    import json
    try:
        results_dict = json.loads(results)
    except json.JSONDecodeError:
        raise HTTPException(400, "Invalid JSON in results field")
    row = log_result(session_id, test_type, results_dict, notes)
    return {"status": "logged", "row": row}


@app.get("/sessions/results")
async def get_results():
    """Get all logged results as JSON."""
    return {"results": get_all_results()}


@app.get("/sessions/export")
async def export_results():
    """Download the results CSV file."""
    csv_path = get_csv_path()
    if not csv_path.exists():
        raise HTTPException(404, "No results logged yet")
    return FileResponse(
        path=str(csv_path),
        media_type="text/csv",
        filename="test_results.csv",
    )


# ─── VMAF ─────────────────────────────────────────────────────────

@app.post("/vmaf/score")
async def calculate_vmaf(
    distorted_video: UploadFile = File(...),
):
    contents = await distorted_video.read()
    if not contents:
        raise HTTPException(400, "Empty file uploaded")

    suffix = Path(distorted_video.filename or "").suffix or ".mp4"

    with NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        tmp.write(contents)
        original_path = Path(tmp.name)

    try:
        score = compute_vmaf(original_path)

        return {
            "vmaf_score": score,
        }

    finally:
        original_path.unlink(missing_ok=True)


# ─── Audio Streaming ──────────────────────────────────────────────

@app.get("/audio/peaq")
async def stream_peaq_audio():
    """Stream the PEAQ reference audio file to the client."""
    audio_path = AUDIO_DIR / "peaq.wav"
    if not audio_path.exists():
        raise HTTPException(404, "PEAQ reference audio not found")
    return FileResponse(
        path=str(audio_path),
        media_type="audio/wav",
        filename="peaq_reference.wav",
    )


@app.get("/audio/pesq")
async def stream_pesq_audio():
    """Stream the PESQ reference speech file to the client."""
    audio_path = AUDIO_DIR / "pesq.wav"
    if not audio_path.exists():
        raise HTTPException(404, "PESQ reference audio not found")
    return FileResponse(
        path=str(audio_path),
        media_type="audio/wav",
        filename="pesq_reference.wav",
    )


# ─── PEAQ ─────────────────────────────────────────────────────────

@app.post("/peaq/score")
async def calculate_peaq(
    degraded_audio: UploadFile = File(...),
    room_noise: UploadFile | None = File(None),
    session_id: str | None = Form(None),
):
    """
    Compute PEAQ ODG score.
    Accepts a degraded WAV file and optional room noise WAV for spectral subtraction.
    Returns ODG score, and if noise provided, the subtracted audio as base64.
    """
    contents = await degraded_audio.read()
    if not contents:
        raise HTTPException(400, "Empty degraded audio file uploaded")

    suffix = Path(degraded_audio.filename or "").suffix or ".wav"

    with NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        tmp.write(contents)
        deg_path = Path(tmp.name)

    noise_path = None
    if room_noise is not None:
        noise_contents = await room_noise.read()
        if noise_contents:
            noise_suffix = Path(room_noise.filename or "").suffix or ".wav"
            with NamedTemporaryFile(delete=False, suffix=noise_suffix) as tmp_noise:
                tmp_noise.write(noise_contents)
                noise_path = Path(tmp_noise.name)

    try:
        result = compute_peaq_odg(deg_path, noise_audio=noise_path)

        # Auto-log if session provided
        if session_id:
            log_result(session_id, "peaq", {
                "raw_odg": result.get("raw_odg", ""),
                "wiener_odg": result.get("wiener_odg", ""),
                "ffmpeg_odg": result.get("ffmpeg_odg", ""),
                "lsd": result.get("lsd", ""),
            })

        return result
    except PEAQError as e:
        raise HTTPException(500, f"PEAQ computation failed: {e}")
    finally:
        deg_path.unlink(missing_ok=True)
        if noise_path:
            noise_path.unlink(missing_ok=True)


# ─── PESQ ─────────────────────────────────────────────────────────

@app.post("/pesq/score")
async def calculate_pesq(
    degraded_audio: UploadFile = File(...),
):
    """
    Compute PESQ scores (wideband and narrowband).
    Accepts a degraded WAV file and compares against the stored reference speech.
    """
    contents = await degraded_audio.read()
    if not contents:
        raise HTTPException(400, "Empty file uploaded")

    suffix = Path(degraded_audio.filename or "").suffix or ".wav"

    with NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        tmp.write(contents)
        tmp_path = Path(tmp.name)

    try:
        result = compute_pesq(tmp_path)
        return result
    except PESQError as e:
        raise HTTPException(500, f"PESQ computation failed: {e}")
    finally:
        tmp_path.unlink(missing_ok=True)


@app.get("/pesq/compare")
async def pesq_comparison():
    """
    Compare narrowband (8 kHz, traditional call) vs wideband (16 kHz, VoIP)
    quality using simulated codec degradation on the reference speech.
    """
    try:
        result = compute_pesq_comparison()
        return result
    except PESQError as e:
        raise HTTPException(500, f"PESQ comparison failed: {e}")


# ─── WebRTC Codec Call ────────────────────────────────────────────

@app.get("/webrtc/call")
async def webrtc_call():
    """
    Simulate a WebRTC VoIP call using actual Opus and G.711 codecs.
    Processes reference audio through real WebRTC codecs via ffmpeg,
    computes PESQ scores, and returns degraded audio for playback.
    """
    try:
        result = make_webrtc_call()
        return result
    except Exception as e:
        raise HTTPException(500, f"WebRTC call failed: {e}")


@app.post("/webrtc/device-call")
async def webrtc_device_call(
    recorded_audio: UploadFile = File(...),
    session_id: str | None = Form(None),
):
    """
    Process a phone's mic recording through actual WebRTC codecs.
    The phone records reference speech through speaker → mic, uploads
    the recording, and the backend applies Opus, G.711, and AMR-WB
    codec processing before computing PESQ scores.

    Results vary by device because each phone's speaker/mic quality
    contributes to the degradation.
    """
    contents = await recorded_audio.read()
    if not contents:
        raise HTTPException(400, "Empty recording uploaded")

    suffix = Path(recorded_audio.filename or "").suffix or ".wav"

    with NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        tmp.write(contents)
        rec_path = Path(tmp.name)

    try:
        result = make_device_webrtc_call(rec_path)

        # Auto-log PESQ scores if session provided
        if session_id:
            log_result(session_id, "pesq", {
                "direct": result.get("direct_recording", {}).get("pesq_score", ""),
                "pstn": result.get("traditional_narrowband", {}).get("pesq_score", ""),
                "volte": result.get("volte_wideband", {}).get("pesq_score", ""),
                "voip": result.get("voip_wideband", {}).get("pesq_score", ""),
            })

        return result
    except Exception as e:
        raise HTTPException(500, f"WebRTC device call failed: {e}")
    finally:
        rec_path.unlink(missing_ok=True)


# ─── IQA ──────────────────────────────────────────────────────────

@app.post("/iqa/score")
async def calculate_iqa(
    image: UploadFile = File(...),
):
    contents = await image.read()
    if not contents:
        raise HTTPException(400, "Empty file uploaded")

    suffix = Path(image.filename or "").suffix or ".jpg"

    with NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        tmp.write(contents)
        image_path = Path(tmp.name)

    try:
        scores = compute_iqa(image_path)

        return {
            "brisque": round(scores["brisque"], 2),
            "niqe": round(scores["niqe"], 2),
            "piqe": round(scores["piqe"], 2),
        }

    finally:
        image_path.unlink(missing_ok=True)
