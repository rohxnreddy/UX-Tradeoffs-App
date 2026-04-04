from fastapi import FastAPI, HTTPException, File, UploadFile, Header
from fastapi.responses import FileResponse
from fastapi.concurrency import run_in_threadpool
from contextlib import asynccontextmanager
from pathlib import Path
from tempfile import NamedTemporaryFile
from typing import Optional
from uuid import UUID
import asyncio

from src.vmaf.vmaf import compute_vmaf
from src.peaq.peaq import compute_peaq_odg, PEAQError
from src.pesq.pesq import compute_pesq, PESQError
from src.webrtc.codec_call import make_webrtc_call, make_device_webrtc_call
from src.IMA.IMA import compute_iqa
from src.db.schemas import DeviceMeta

from src.db.database import init_pool, close_pool
from src.db import repository as db

from dotenv import load_dotenv
load_dotenv()

# Audio files directory
AUDIO_DIR = Path(__file__).resolve().parent.parent / "peaq-pesq-audio"

@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_pool()
    yield
    await close_pool()

app = FastAPI(lifespan=lifespan)


def _parse_session_id(raw: Optional[str]) -> Optional[UUID]:
    if not raw:
        return None
    try:
        return UUID(raw)
    except ValueError:
        return None


# ─── Health ───────────────────────────────────────────────────────────────────

@app.get("/")
def init():
    return {"message": "Server is Up!"}


# ─── Device Metadata ─────────────────────────────────────────────────────────
#
# Called once per app launch (after login + questionnaire).
# The body includes:
#   • username, user_email, user_photo_url  (from Google Sign-In)
#   • device_usage, network_env, testing_purpose, usage_frequency  (questionnaire)
#   • all device / OS / network / location fields
#
# Returns session_id which the Flutter app stores and attaches as the
# X-Session-Id header on every subsequent test call.

@app.post("/device/metadata")
async def receive_metadata(meta: DeviceMeta):
    meta_dict = meta.model_dump()
    user_id = await db.upsert_user(meta_dict)
    session_id = await db.insert_session(user_id, meta_dict)
    return {
        "status":     "ok",
        "session_id": str(session_id),
        # Echo back only the identity + questionnaire fields for the client to confirm
        "user": {
            "username":  meta.username,
            "email":     meta.user_email,
            "photo_url": meta.user_photo_url,
        },
        "questionnaire": {
            "device_usage":    meta.device_usage,
            "network_env":     meta.network_env,
            "testing_purpose": meta.testing_purpose,
            "usage_frequency": meta.usage_frequency,
        },
    }


# ─── Session lookup ───────────────────────────────────────────────────────────
#
# Lets the Flutter app (or the Streamlit dashboard) fetch a summary of one
# session by its UUID — useful for confirming what was stored.

@app.get("/session/{session_id}")
async def get_session(session_id: UUID):
    pool = await db.get_pool_direct()
    row = await pool.fetchrow(
        """
        SELECT
            s.id, s.created_at,
            u.username, u.user_email, u.user_photo_url,
            u.device_usage, u.network_env, u.testing_purpose, u.usage_frequency,
            s.device_model, s.device_brand, s.android_version,
            s.app_version_name, s.connection_type, s.country
        FROM sessions s
        JOIN users u ON s.user_id = u.id
        WHERE s.id = $1
        """,
        session_id,
    )
    if row is None:
        raise HTTPException(404, "Session not found")
    return dict(row)


# ─── Audio streams ────────────────────────────────────────────────────────────

@app.get("/audio/peaq")
async def stream_peaq_audio():
    audio_path = AUDIO_DIR / "peaq.wav"
    if not audio_path.exists():
        raise HTTPException(404, "PEAQ reference audio not found")
    return FileResponse(path=str(audio_path), media_type="audio/wav", filename="peaq_reference.wav")


@app.get("/audio/pesq")
async def stream_pesq_audio():
    audio_path = AUDIO_DIR / "pesq.wav"
    if not audio_path.exists():
        raise HTTPException(404, "PESQ reference audio not found")
    return FileResponse(path=str(audio_path), media_type="audio/wav", filename="pesq_reference.wav")


# ─── VMAF ─────────────────────────────────────────────────────────────────────

@app.post("/vmaf/score")
async def calculate_vmaf(
    distorted_video: UploadFile = File(...),
    x_session_id: Optional[str] = Header(None),
):
    session_id = _parse_session_id(x_session_id)

    contents = await distorted_video.read()
    if not contents:
        raise HTTPException(400, "Empty file uploaded")

    suffix   = Path(distorted_video.filename or "").suffix or ".mp4"
    filename = distorted_video.filename

    with NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        tmp.write(contents)
        original_path = Path(tmp.name)

    try:
        score = compute_vmaf(original_path)
        result = {"vmaf_score": score}
        record_id = await db.insert_vmaf_result(
            session_id=session_id,
            filename=filename,
            file_size_bytes=len(contents),
            result=result,
        )
        return {**result, "record_id": str(record_id)}
    finally:
        original_path.unlink(missing_ok=True)


# ─── PEAQ ─────────────────────────────────────────────────────────────────────

@app.post("/peaq/score")
async def calculate_peaq(
    degraded_audio: UploadFile = File(...),
    room_noise: Optional[UploadFile] = File(None),
    x_session_id: Optional[str] = Header(None),
):
    session_id = _parse_session_id(x_session_id)

    contents = await degraded_audio.read()
    if not contents:
        raise HTTPException(400, "Empty degraded audio file uploaded")

    suffix       = Path(degraded_audio.filename or "").suffix or ".wav"
    deg_filename = degraded_audio.filename

    with NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        tmp.write(contents)
        deg_path = Path(tmp.name)

    noise_path     = None
    noise_filename = None
    if room_noise is not None:
        noise_contents = await room_noise.read()
        if noise_contents:
            noise_suffix   = Path(room_noise.filename or "").suffix or ".wav"
            noise_filename = room_noise.filename
            with NamedTemporaryFile(delete=False, suffix=noise_suffix) as tmp_noise:
                tmp_noise.write(noise_contents)
                noise_path = Path(tmp_noise.name)

    try:
        result    = compute_peaq_odg(deg_path, noise_audio=noise_path)
        record_id = await db.insert_peaq_result(
            session_id=session_id,
            degraded_filename=deg_filename,
            noise_filename=noise_filename,
            result=result,
        )
        return {**result, "record_id": str(record_id)}
    except PEAQError as e:
        raise HTTPException(500, f"PEAQ computation failed: {e}")
    finally:
        deg_path.unlink(missing_ok=True)
        if noise_path:
            noise_path.unlink(missing_ok=True)


# ─── PESQ ─────────────────────────────────────────────────────────────────────

@app.post("/pesq/score")
async def calculate_pesq(
    degraded_audio: UploadFile = File(...),
    x_session_id: Optional[str] = Header(None),
):
    session_id = _parse_session_id(x_session_id)

    contents = await degraded_audio.read()
    if not contents:
        raise HTTPException(400, "Empty file uploaded")

    suffix   = Path(degraded_audio.filename or "").suffix or ".wav"
    filename = degraded_audio.filename

    with NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        tmp.write(contents)
        tmp_path = Path(tmp.name)

    try:
        result    = compute_pesq(tmp_path)
        record_id = await db.insert_pesq_result(
            session_id=session_id,
            degraded_filename=filename,
            test_type="upload",
            result=result,
        )
        return {**result, "record_id": str(record_id)}
    except PESQError as e:
        raise HTTPException(500, f"PESQ computation failed: {e}")
    finally:
        tmp_path.unlink(missing_ok=True)


# ─── WebRTC Codec Call ────────────────────────────────────────────────────────

@app.get("/webrtc/call")
async def webrtc_call(x_session_id: Optional[str] = Header(None)):
    session_id = _parse_session_id(x_session_id)

    try:
        result    = make_webrtc_call()
        record_id = await db.insert_pesq_result_from_webrtc(
            session_id=session_id,
            call_type="simulated",
            result=result,
        )
        return {**result, "record_id": str(record_id)}
    except Exception as e:
        raise HTTPException(500, f"WebRTC call failed: {e}")


@app.post("/webrtc/device-call")
async def webrtc_device_call(
    recorded_audio: UploadFile = File(...),
    x_session_id: Optional[str] = Header(None),
):
    session_id = _parse_session_id(x_session_id)

    contents = await recorded_audio.read()
    if not contents:
        raise HTTPException(400, "Empty recording uploaded")

    suffix   = Path(recorded_audio.filename or "").suffix or ".wav"
    filename = recorded_audio.filename

    with NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        tmp.write(contents)
        rec_path = Path(tmp.name)

    try:
        result    = make_device_webrtc_call(rec_path)
        record_id = await db.insert_pesq_result_from_webrtc(
            session_id=session_id,
            call_type="device",
            recorded_filename=filename,
            result=result,
        )
        return {**result, "record_id": str(record_id)}
    except Exception as e:
        raise HTTPException(500, f"WebRTC device call failed: {e}")
    finally:
        rec_path.unlink(missing_ok=True)


# ─── IQA ──────────────────────────────────────────────────────────────────────

@app.post("/iqa/score")
async def calculate_iqa(
    images: list[UploadFile] = File(...),
    x_session_id: Optional[str] = Header(None),
):
    session_id = _parse_session_id(x_session_id)

    if not images:
        raise HTTPException(400, "No files uploaded")

    temp_paths: list[Path]          = []
    filenames:  list[Optional[str]] = []
    file_sizes: list[Optional[int]] = []

    try:
        for image in images:
            contents = await image.read()
            if not contents:
                raise HTTPException(400, f"Empty file: {image.filename}")

            suffix = Path(image.filename or "").suffix or ".jpg"
            filenames.append(image.filename)
            file_sizes.append(len(contents))

            with NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
                tmp.write(contents)
                temp_paths.append(Path(tmp.name))

        tasks      = [run_in_threadpool(compute_iqa, path) for path in temp_paths]
        all_scores = await asyncio.gather(*tasks)

        response: list[dict] = []
        for idx, scores in enumerate(all_scores):
            response.append({
                "image_index": idx,
                "brisque":     round(scores["brisque"], 2),
                "niqe":        round(scores["niqe"],    2),
                "piqe":        round(scores["piqe"],    2),
            })

        record_ids = await db.insert_iqa_results(
            session_id=session_id,
            filenames=filenames,
            file_sizes=file_sizes,
            results=response,
        )

        return {
            "results": [
                {**r, "record_id": str(rid)}
                for r, rid in zip(response, record_ids)
            ]
        }

    finally:
        for path in temp_paths:
            path.unlink(missing_ok=True)