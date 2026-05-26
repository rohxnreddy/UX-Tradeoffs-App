from fastapi import FastAPI, HTTPException, File, UploadFile, Header, Query
from fastapi.responses import FileResponse, Response
from fastapi.concurrency import run_in_threadpool
from fastapi.staticfiles import StaticFiles
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

from src.db.database import init_pool, close_pool, get_pool_direct
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

# Global lock to ensure only one IQA test runs at a time on the entire server.
# This prevents OOM (Out of Memory) crashes when multiple users or images are processed.
iqa_lock = asyncio.Lock()


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


@app.get("/api/insights")
async def get_insights():
    pool = await get_pool_direct()
    async with pool.acquire() as conn:
        # 1. High level metrics
        total_users = await conn.fetchval("SELECT COUNT(*) FROM users")
        total_sessions = await conn.fetchval("SELECT COUNT(*) FROM sessions")
        
        # 2. Test counts
        vmaf_count = await conn.fetchval("SELECT COUNT(*) FROM vmaf_results")
        peaq_count = await conn.fetchval("SELECT COUNT(*) FROM peaq_results")
        pesq_count = await conn.fetchval("SELECT COUNT(*) FROM pesq_results")
        iqa_count = await conn.fetchval("SELECT COUNT(*) FROM iqa_results")
        
        # 3. Average scores
        vmaf_avg = await conn.fetchval("SELECT AVG(vmaf_score) FROM vmaf_results")
        
        peaq_row = await conn.fetchrow("""
            SELECT 
                AVG(odg_score) as avg_odg, 
                AVG(raw_odg) as avg_raw_odg, 
                AVG(ffmpeg_odg) as avg_ffmpeg_odg 
            FROM peaq_results
        """)
        
        pesq_row = await conn.fetchrow("""
            SELECT 
                AVG(direct_pesq) as avg_direct, 
                AVG(pstn_pesq) as avg_pstn, 
                AVG(volte_pesq) as avg_volte, 
                AVG(voip_pesq) as avg_voip 
            FROM pesq_results
        """)
        
        iqa_row = await conn.fetchrow("""
            SELECT 
                AVG(camera_score) as avg_camera, 
                AVG(brisque) as avg_brisque, 
                AVG(niqe) as avg_niqe, 
                AVG(piqe) as avg_piqe 
            FROM iqa_results
        """)
        
        # 4. Device distributions
        device_brands = await conn.fetch("""
            SELECT COALESCE(device_brand, 'Unknown') as brand, COUNT(*) as count 
            FROM sessions 
            GROUP BY device_brand 
            ORDER BY count DESC 
            LIMIT 15
        """)
        
        # 5. Connection distributions
        connection_types = await conn.fetch("""
            SELECT COALESCE(connection_type, 'Unknown') as type, COUNT(*) as count 
            FROM sessions 
            GROUP BY connection_type 
            ORDER BY count DESC
        """)
        
        # 6. Screen refresh rate distribution
        refresh_rates = await conn.fetch("""
            SELECT display_refresh_rate as rate, COUNT(*) as count 
            FROM sessions 
            WHERE display_refresh_rate IS NOT NULL 
            GROUP BY display_refresh_rate 
            ORDER BY rate
        """)

        # 6a. Android versions
        android_versions = await conn.fetch("""
            SELECT COALESCE(android_version, 'Unknown') as version, COUNT(*) as count 
            FROM sessions 
            GROUP BY android_version 
            ORDER BY count DESC
        """)

        # 6b. Age of phone (from survey)
        phone_ages = await conn.fetch("""
            SELECT COALESCE(phone_duration, 'Unknown') as age, COUNT(*) as count 
            FROM users 
            GROUP BY phone_duration 
            ORDER BY count DESC
        """)

        # 6c. Location data (coordinates for globe and countries summary)
        location_countries = await conn.fetch("""
            SELECT COALESCE(country, 'Unknown') as country, COUNT(*) as count 
            FROM sessions 
            GROUP BY country 
            ORDER BY count DESC
        """)

        location_coordinates = await conn.fetch("""
            SELECT 
                COALESCE(locality, 'Unknown') as city,
                COALESCE(country, 'Unknown') as country,
                latitude::float as lat,
                longitude::float as lon,
                COUNT(*)::int as count
            FROM sessions
            WHERE latitude IS NOT NULL AND longitude IS NOT NULL
            GROUP BY locality, country, latitude, longitude
        """)

        # 7. Recent sessions list
        recent_sessions = await conn.fetch("""
            SELECT s.id, s.created_at, COALESCE(u.username, 'Anonymous') as username, 
                   COALESCE(s.device_model, 'Unknown') as device_model, 
                   COALESCE(s.country, 'Unknown') as country 
            FROM sessions s 
            LEFT JOIN users u ON s.user_id = u.id 
            ORDER BY s.created_at DESC 
            LIMIT 5
        """)

        # 8. Time series of tests (for trend chart)
        recent_tests = await conn.fetch("""
            (SELECT 'VMAF' as test_type, created_at, vmaf_score::float as score FROM vmaf_results WHERE vmaf_score IS NOT NULL ORDER BY created_at DESC LIMIT 10)
            UNION ALL
            (SELECT 'PEAQ' as test_type, created_at, odg_score::float as score FROM peaq_results ORDER BY created_at DESC LIMIT 10)
            UNION ALL
            (SELECT 'PESQ' as test_type, created_at, direct_pesq::float as score FROM pesq_results ORDER BY created_at DESC LIMIT 10)
            UNION ALL
            (SELECT 'IQA' as test_type, created_at, camera_score::float as score FROM iqa_results ORDER BY created_at DESC LIMIT 10)
            ORDER BY created_at DESC
            LIMIT 30
        """)

        # 9. All individual scores for distribution
        all_vmaf = await conn.fetch("SELECT vmaf_score::float as score FROM vmaf_results WHERE vmaf_score IS NOT NULL")
        all_peaq = await conn.fetch("SELECT odg_score::float as score FROM peaq_results WHERE odg_score IS NOT NULL")
        all_pesq = await conn.fetch("SELECT direct_pesq::float as score FROM pesq_results WHERE direct_pesq IS NOT NULL")
        all_iqa = await conn.fetch("SELECT camera_score::float as score FROM iqa_results WHERE camera_score IS NOT NULL")

    return {
        "metrics": {
            "total_users": total_users,
            "total_sessions": total_sessions,
            "total_tests": (vmaf_count or 0) + (peaq_count or 0) + (pesq_count or 0) + (iqa_count or 0),
            "test_counts": {
                "vmaf": vmaf_count or 0,
                "peaq": peaq_count or 0,
                "pesq": pesq_count or 0,
                "iqa": iqa_count or 0
            }
        },
        "averages": {
            "vmaf": float(vmaf_avg) if vmaf_avg is not None else None,
            "peaq": {
                "odg_score": float(peaq_row["avg_odg"]) if peaq_row and peaq_row["avg_odg"] is not None else None,
                "raw_odg": float(peaq_row["avg_raw_odg"]) if peaq_row and peaq_row["avg_raw_odg"] is not None else None,
                "ffmpeg_odg": float(peaq_row["avg_ffmpeg_odg"]) if peaq_row and peaq_row["avg_ffmpeg_odg"] is not None else None,
            } if peaq_row else None,
            "pesq": {
                "direct_pesq": float(pesq_row["avg_direct"]) if pesq_row and pesq_row["avg_direct"] is not None else None,
                "pstn_pesq": float(pesq_row["avg_pstn"]) if pesq_row and pesq_row["avg_pstn"] is not None else None,
                "volte_pesq": float(pesq_row["avg_volte"]) if pesq_row and pesq_row["avg_volte"] is not None else None,
                "voip_pesq": float(pesq_row["avg_voip"]) if pesq_row and pesq_row["avg_voip"] is not None else None,
            } if pesq_row else None,
            "iqa": {
                "camera_score": float(iqa_row["avg_camera"]) if iqa_row and iqa_row["avg_camera"] is not None else None,
                "brisque": float(iqa_row["avg_brisque"]) if iqa_row and iqa_row["avg_brisque"] is not None else None,
                "niqe": float(iqa_row["avg_niqe"]) if iqa_row and iqa_row["avg_niqe"] is not None else None,
                "piqe": float(iqa_row["avg_piqe"]) if iqa_row and iqa_row["avg_piqe"] is not None else None,
            } if iqa_row else None,
        },
        "distributions": {
            "device_brands": [dict(r) for r in device_brands],
            "connection_types": [dict(r) for r in connection_types],
            "refresh_rates": [{"rate": float(r["rate"]), "count": r["count"]} for r in refresh_rates],
            "android_versions": [dict(r) for r in android_versions],
            "phone_ages": [dict(r) for r in phone_ages],
            "location_countries": [dict(r) for r in location_countries],
            "location_coordinates": [dict(r) for r in location_coordinates]
        },
        "recent_sessions": [
            {
                "id": str(r["id"]),
                "created_at": r["created_at"].isoformat(),
                "username": r["username"],
                "device_model": r["device_model"],
                "country": r["country"]
            } for r in recent_sessions
        ],
        "recent_tests": [
            {
                "test_type": r["test_type"],
                "created_at": r["created_at"].isoformat(),
                "score": float(r["score"]) if r["score"] is not None else None
            } for r in recent_tests
        ],
        "vmaf_all_scores": [r["score"] for r in all_vmaf],
        "peaq_all_scores": [r["score"] for r in all_peaq],
        "pesq_all_scores": [r["score"] for r in all_pesq],
        "iqa_all_scores": [r["score"] for r in all_iqa]
    }


# Serve the glass UI dashboard statically
INSIGHTS_DIR = Path(__file__).resolve().parent / "db" / "insights"
app.mount("/insights", StaticFiles(directory=str(INSIGHTS_DIR), html=True), name="insights")


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
    pool = await get_pool_direct()
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

@app.post("/camara/score")
async def calculate_iqa(
    images: list[UploadFile] = File(...),
    x_session_id: Optional[str] = Header(None),
):
    session_id = _parse_session_id(x_session_id)
    if not images:
        raise HTTPException(400, "No files uploaded")

    final_results = []

    # Use a global lock to ensure only ONE image is processed across the whole server at once.
    # This completely prevents OOM from concurrent requests on low-RAM servers.
    async with iqa_lock:
        for idx, image in enumerate(images):
            temp_path = None
            filename = image.filename or f"img_{idx}.jpg"
            try:
                suffix = Path(filename).suffix or ".jpg"
                
                # 1. Stream to Disk (don't load into RAM)
                with NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
                    # shutil.copyfileobj streams data, keeping memory usage constant.
                    await run_in_threadpool(shutil.copyfileobj, image.file, tmp)
                    temp_path = Path(tmp.name)
                
                file_size = temp_path.stat().st_size
                if file_size == 0:
                    raise HTTPException(400, f"Empty file: {filename}")

                # 2. Compute IQA Score (Sequential within the loop)
                scores = await run_in_threadpool(compute_iqa, temp_path)
                
                res_dict = {
                    "image_index": idx,
                    "brisque":     round(scores["brisque"], 2),
                    "niqe":        round(scores["niqe"],    2),
                    "piqe":        round(scores["piqe"],    2),
                }

                # 3. Insert into DB (single row batch)
                record_ids = await db.insert_iqa_results(
                    session_id=session_id,
                    filenames=[filename],
                    file_sizes=[file_size],
                    results=[res_dict],
                )
                rid = record_ids[0]

                # 4. Move to Storage
                storage_path = await _move_to_storage(temp_path, session_id, rid, filename, "iqa")
                await (await db.get_pool()).execute(
                    "UPDATE iqa_results SET storage_path = $1 WHERE id = $2",
                    storage_path, rid
                )
                
                final_results.append({**res_dict, "record_id": str(rid), "storage_path": storage_path})
                
            finally:
                if temp_path and temp_path.exists():
                    temp_path.unlink(missing_ok=True)
                    
    return {"results": final_results}
