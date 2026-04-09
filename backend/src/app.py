from fastapi import FastAPI, HTTPException, File, UploadFile, Header, Query
from fastapi.responses import FileResponse, Response
from fastapi.concurrency import run_in_threadpool
from contextlib import asynccontextmanager
from pathlib import Path
from tempfile import NamedTemporaryFile
from typing import Optional
from uuid import UUID
import asyncio
import shutil

from src.vmaf.vmaf import compute_vmaf
from src.audio_sync import build_playback_wav, get_sync_marker_version
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
DATA_DIR  = Path(__file__).resolve().parent.parent / "data"

async def _move_to_storage(temp_path: Path, session_id: Optional[UUID], record_id: UUID, original_filename: str, category: str) -> str:
    """Helper to move a temporary file to the permanent data/{category} directory."""
    username = "anonymous"
    if session_id:
        username = await db.get_username_by_session(session_id)
    
    # Sanitise filename
    safe_name = (original_filename or "unnamed").replace(" ", "_").replace("/", "_")
    new_filename = f"{username}_{session_id or 'no_session'}_{record_id}_{safe_name}"
    
    dest_dir = DATA_DIR / category
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest_path = dest_dir / new_filename
    
    # Move the file
    await run_in_threadpool(shutil.move, str(temp_path), str(dest_path))
    
    # Return relative path for DB
    return f"data/{category}/{new_filename}"

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
            "age_group": meta.age_group,
            "phone_condition": meta.phone_condition,
            "phone_duration": meta.phone_duration,
            "phone_history": meta.phone_history,
            "primary_usage": meta.primary_usage,
            "internet_frequency": meta.internet_frequency,
            "phone_sharing": meta.phone_sharing,
            "internet_connection_type": meta.internet_connection_type,
            "phone_acquisition": meta.phone_acquisition,
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
            u.age_group, u.phone_condition, u.phone_duration,
            u.phone_history, u.primary_usage, u.internet_frequency,
            u.phone_sharing, u.internet_connection_type, u.phone_acquisition,
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
async def stream_peaq_audio(playback: bool = Query(False)):
    audio_path = AUDIO_DIR / "peaq.wav"
    if not audio_path.exists():
        raise HTTPException(404, "PEAQ reference audio not found")
    if playback:
        wav_bytes = await run_in_threadpool(build_playback_wav, audio_path, "peaq")
        return Response(
            content=wav_bytes,
            media_type="audio/wav",
            headers={"X-Audio-Sync": get_sync_marker_version("peaq")},
        )
    return FileResponse(path=str(audio_path), media_type="audio/wav", filename="peaq_reference.wav")


@app.get("/audio/pesq")
async def stream_pesq_audio(playback: bool = Query(False)):
    audio_path = AUDIO_DIR / "pesq.wav"
    if not audio_path.exists():
        raise HTTPException(404, "PESQ reference audio not found")
    if playback:
        wav_bytes = await run_in_threadpool(build_playback_wav, audio_path, "pesq")
        return Response(
            content=wav_bytes,
            media_type="audio/wav",
            headers={"X-Audio-Sync": get_sync_marker_version("pesq")},
        )
    return FileResponse(path=str(audio_path), media_type="audio/wav", filename="pesq_reference.wav")


# ─── VMAF ─────────────────────────────────────────────────────────────────────

async def _bg_vmaf_task(record_id: UUID, file_path: Path):
    """Background task to compute VMAF and update the database."""
    try:
        score = await run_in_threadpool(compute_vmaf, file_path)
        await db.update_vmaf_result(
            record_id=record_id,
            status="completed",
            vmaf_score=score,
            raw_output={"vmaf_score": score},
        )
    except Exception as e:
        print(f"Background VMAF task error: {e}")
        await db.update_vmaf_result(record_id=record_id, status="failed")


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
        temp_path = Path(tmp.name)

    # 1. Create a shell record
    record_id = await db.insert_vmaf_result(
        session_id=session_id,
        filename=filename,
        file_size_bytes=len(contents),
        status="processing",
    )

    # 2. Persist the file
    storage_path = await _move_to_storage(temp_path, session_id, record_id, filename or "video.mp4", "vmaf")
    await db.update_vmaf_result(record_id, status="processing", storage_path=storage_path)

    # 3. Fire-and-forget the background calculation (using the persistent path)
    asyncio.create_task(_bg_vmaf_task(record_id, DATA_DIR.parent / storage_path))

    return {
        "status":    "processing",
        "record_id": str(record_id),
        "storage_path": storage_path,
        "message":   "VMAF calculation started in the background."
    }


@app.get("/vmaf/status/{record_id}")
async def get_vmaf_status(record_id: UUID):
    result = await db.get_vmaf_result(record_id)
    if not result:
        raise HTTPException(404, "VMAF result not found")
    return result


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
        
        # 1. Generate record ID first (or we can do it after moving, but we need the ID for filename)
        # We'll insert with placeholder paths and then update, or just generate a UUID.
        # Let's insert first.
        record_id = await db.insert_peaq_result(
            session_id=session_id,
            degraded_filename=deg_filename,
            noise_filename=noise_filename,
            result=result,
        )

        # 2. Move files to storage
        degraded_storage_path = await _move_to_storage(deg_path, session_id, record_id, f"degraded_{deg_filename}", "peaq")
        noise_storage_path = None
        if noise_path:
            noise_storage_path = await _move_to_storage(noise_path, session_id, record_id, f"noise_{noise_filename}", "peaq")
        
        # 3. Update DB with storage paths
        await (await db.get_pool()).execute(
            "UPDATE peaq_results SET degraded_storage_path = $1, noise_storage_path = $2 WHERE id = $3",
            degraded_storage_path, noise_storage_path, record_id
        )

        return {**result, "record_id": str(record_id), "storage_path": degraded_storage_path}
    except PEAQError as e:
        raise HTTPException(500, f"PEAQ computation failed: {e}")
    finally:
        if deg_path.exists(): deg_path.unlink(missing_ok=True)
        if noise_path and noise_path.exists(): noise_path.unlink(missing_ok=True)


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
        # Create record to get ID
        record_id = await db.insert_pesq_result(
            session_id=session_id,
            degraded_filename=filename,
            test_type="upload",
            result=result,
        )
        # Move to storage
        storage_path = await _move_to_storage(tmp_path, session_id, record_id, filename or "audio.wav", "pesq")
        # Update record
        await (await db.get_pool()).execute(
            "UPDATE pesq_results SET storage_path = $1 WHERE id = $2",
            storage_path, record_id
        )
        return {**result, "record_id": str(record_id), "storage_path": storage_path}
    except PESQError as e:
        raise HTTPException(500, f"PESQ computation failed: {e}")
    finally:
        if tmp_path.exists(): tmp_path.unlink(missing_ok=True)


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
        # Move to storage
        storage_path = await _move_to_storage(rec_path, session_id, record_id, filename or "recording.wav", "pesq")
        # Update record
        await (await db.get_pool()).execute(
            "UPDATE pesq_results SET storage_path = $1 WHERE id = $2",
            storage_path, record_id
        )
        return {**result, "record_id": str(record_id), "storage_path": storage_path}
    except Exception as e:
        raise HTTPException(500, f"WebRTC device call failed: {e}")
    finally:
        if rec_path.exists(): rec_path.unlink(missing_ok=True)


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

        all_scores = []
        for path in temp_paths:
            score = await run_in_threadpool(compute_iqa, path)
            all_scores.append(score)

        # 1. Insert records to get IDs
        response_base: list[dict] = []
        for idx, scores in enumerate(all_scores):
            response_base.append({
                "image_index": idx,
                "brisque":     round(scores["brisque"], 2),
                "niqe":        round(scores["niqe"],    2),
                "piqe":        round(scores["piqe"],    2),
            })

        record_ids = await db.insert_iqa_results(
            session_id=session_id,
            filenames=filenames,
            file_sizes=file_sizes,
            results=response_base,
        )

        # 2. Move files and update paths
        final_results = []
        for idx, (rid, tmp_path) in enumerate(zip(record_ids, temp_paths)):
            storage_path = await _move_to_storage(tmp_path, session_id, rid, filenames[idx] or f"img_{idx}.jpg", "iqa")
            await (await db.get_pool()).execute(
                "UPDATE iqa_results SET storage_path = $1 WHERE id = $2",
                storage_path, rid
            )
            final_results.append({**response_base[idx], "record_id": str(rid), "storage_path": storage_path})

        return {"results": final_results}

    finally:
        for path in temp_paths:
            if path.exists(): path.unlink(missing_ok=True)
