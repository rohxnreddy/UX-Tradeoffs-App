"""
src/db/repository.py
─────────────────────
All database write operations.  Each function takes the result dict
returned by the compute_* functions plus context (session_id, filename, …)
and inserts one row into the appropriate table.
"""

from __future__ import annotations

import json
from datetime import datetime
from typing import Optional
from uuid import UUID

import asyncpg

from .database import get_pool


# ─── helpers ──────────────────────────────────────────────────────────────────

def _parse_dt(value) -> Optional[datetime]:
    """Coerce an ISO-8601 string (or datetime) to datetime, or return None."""
    if value is None:
        return None
    if isinstance(value, datetime):
        return value
    try:
        return datetime.fromisoformat(str(value))
    except (ValueError, TypeError):
        return None


def _jsonb(obj) -> Optional[str]:
    """Safely serialise an arbitrary dict to a JSON string for asyncpg JSONB columns."""
    if obj is None:
        return None
    try:
        return json.dumps(obj)
    except (TypeError, ValueError):
        return None


async def upsert_user(meta: dict) -> UUID:
    """
    Insert or update a user based on user_email.
    Returns the user's UUID.
    """
    pool = await get_pool()
    # Require email to upsert properly; if missing, we could just rely on the DB failure
    # or handle it nicely. Let's let the DB throw if user_email is NULL and there's a constraint,
    # or we can handle it at the API layer.
    row = await pool.fetchrow(
        """
        INSERT INTO users (
            username, user_email, user_photo_url,
            age_group, phone_condition, phone_duration, phone_history,
            primary_usage, internet_frequency, phone_sharing,
            internet_connection_type, phone_acquisition
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
        ON CONFLICT (user_email) DO UPDATE SET
            username = EXCLUDED.username,
            user_photo_url = EXCLUDED.user_photo_url,
            age_group = COALESCE(EXCLUDED.age_group, users.age_group),
            phone_condition = COALESCE(EXCLUDED.phone_condition, users.phone_condition),
            phone_duration = COALESCE(EXCLUDED.phone_duration, users.phone_duration),
            phone_history = COALESCE(EXCLUDED.phone_history, users.phone_history),
            primary_usage = COALESCE(EXCLUDED.primary_usage, users.primary_usage),
            internet_frequency = COALESCE(EXCLUDED.internet_frequency, users.internet_frequency),
            phone_sharing = COALESCE(EXCLUDED.phone_sharing, users.phone_sharing),
            internet_connection_type = COALESCE(EXCLUDED.internet_connection_type, users.internet_connection_type),
            phone_acquisition = COALESCE(EXCLUDED.phone_acquisition, users.phone_acquisition)
        RETURNING id
        """,
        meta.get("username"),
        meta.get("user_email"),
        meta.get("user_photo_url"),
        meta.get("age_group"),
        meta.get("phone_condition"),
        meta.get("phone_duration"),
        meta.get("phone_history"),
        meta.get("primary_usage"),
        meta.get("internet_frequency"),
        meta.get("phone_sharing"),
        meta.get("internet_connection_type"),
        meta.get("phone_acquisition"),
    )
    return row["id"]


async def insert_session(user_id: UUID, meta: dict) -> UUID:
    """
    Insert a sessions row linked to a user.
    Returns the new UUID so callers can attach subsequent test results.
    """
    pool = await get_pool()

    row = await pool.fetchrow(
        """
        INSERT INTO sessions (
            user_id,

            -- Hardware
            device_model, device_brand, device_manufacturer, device_product,
            device_hardware, supported_abis, cpu_cores,

            -- OS & System
            android_version, sdk_version, build_number, security_patch_level,
            build_fingerprint, bootloader, is_physical_device, is_rooted,

            -- App
            app_package_name, app_version_name, app_version_code,
            app_installer_package, is_debug_build,

            -- Screen
            screen_width_px, screen_height_px, screen_density, display_refresh_rate,

            -- Locale
            device_language, device_locale, timezone, country_code,

            -- Battery
            battery_level, battery_state,

            -- Network
            connection_type, wifi_name, wifi_bssid,
            local_ipv4, local_ipv6, is_vpn_active,
            network_speed_category, network_latency_ms,

            -- Location
            latitude, longitude, altitude, location_accuracy,
            speed, bearing, locality, country, postal_code,
            admin_area, iso_country_code,

            -- Permissions
            permission_statuses,

            -- Session Activity
            session_start, session_screen_views, session_user_actions,
            session_background_count,

            -- Performance
            app_launch_time_ms, frame_drop_count, last_crash_info,

            -- Memory & Storage
            device_tier, total_ram_mb, available_ram_mb,
            total_disk_mb, free_disk_mb,

            -- Audio
            audio_output_route
        ) VALUES (
            $1,

            -- Hardware
            $2, $3, $4, $5, $6, $7, $8,

            -- OS & System
            $9, $10, $11, $12, $13, $14, $15, $16,

            -- App
            $17, $18, $19, $20, $21,

            -- Screen
            $22, $23, $24, $25,

            -- Locale
            $26, $27, $28, $29,

            -- Battery
            $30, $31,

            -- Network
            $32, $33, $34, $35, $36, $37, $38, $39,

            -- Location
            $40, $41, $42, $43, $44, $45, $46, $47, $48, $49, $50,

            -- Permissions
            $51::jsonb,

            -- Session Activity
            $52, $53, $54, $55,

            -- Performance
            $56, $57, $58,

            -- Memory & Storage
            $59, $60, $61, $62, $63,

            -- Audio
            $64
        )
        RETURNING id
        """,
        user_id,

        # Hardware ($2–$8)
        meta.get("device_model"),
        meta.get("device_brand"),
        meta.get("device_manufacturer"),
        meta.get("device_product"),
        meta.get("device_hardware"),
        meta.get("supported_abis"),
        meta.get("cpu_cores"),

        # OS & System ($9–$16)
        meta.get("android_version"),
        meta.get("sdk_version"),
        meta.get("build_number"),
        meta.get("security_patch_level"),
        meta.get("build_fingerprint"),
        meta.get("bootloader"),
        meta.get("is_physical_device"),
        meta.get("is_rooted"),

        # App ($17–$21)
        meta.get("app_package_name"),
        meta.get("app_version_name"),
        meta.get("app_version_code"),
        meta.get("app_installer_package"),
        meta.get("is_debug_build"),

        # Screen ($22–$25)
        meta.get("screen_width_px"),
        meta.get("screen_height_px"),
        meta.get("screen_density"),
        meta.get("display_refresh_rate"),

        # Locale ($26–$29)
        meta.get("device_language"),
        meta.get("device_locale"),
        meta.get("timezone"),
        meta.get("country_code"),

        # Battery ($30–$31)
        meta.get("battery_level"),
        meta.get("battery_state"),

        # Network ($32–$39)
        meta.get("connection_type"),
        meta.get("wifi_name"),
        meta.get("wifi_bssid"),
        meta.get("local_ipv4"),
        meta.get("local_ipv6"),
        meta.get("is_vpn_active"),
        meta.get("network_speed_category"),
        meta.get("network_latency_ms"),

        # Location ($40–$50)
        meta.get("latitude"),
        meta.get("longitude"),
        meta.get("altitude"),
        meta.get("location_accuracy"),
        meta.get("speed"),
        meta.get("bearing"),
        meta.get("locality"),
        meta.get("country"),
        meta.get("postal_code"),
        meta.get("admin_area"),
        meta.get("iso_country_code"),

        # Permissions ($51)
        _jsonb(meta.get("permission_statuses")),

        # Session Activity ($52–$55)
        _parse_dt(meta.get("session_start")),
        meta.get("session_screen_views"),
        meta.get("session_user_actions"),
        meta.get("session_background_count"),

        # Performance ($56–$58)
        meta.get("app_launch_time_ms"),
        meta.get("frame_drop_count"),
        meta.get("last_crash_info"),

        # Memory & Storage ($59–$63)
        meta.get("device_tier"),
        meta.get("total_ram_mb"),
        meta.get("available_ram_mb"),
        meta.get("total_disk_mb"),
        meta.get("free_disk_mb"),

        # Audio ($64)
        meta.get("audio_output_route"),
    )
    return row["id"]


async def get_username_by_session(session_id: UUID) -> str:
    """Fetch the username associated with a session ID."""
    pool = await get_pool()
    row = await pool.fetchrow(
        """
        SELECT u.username
        FROM sessions s
        JOIN users u ON s.user_id = u.id
        WHERE s.id = $1
        """,
        session_id,
    )
    if not row or not row["username"]:
        return "anonymous"
    return row["username"]


# ─── 2. VMAF ──────────────────────────────────────────────────────────────────

async def insert_vmaf_result(
    *,
    session_id: Optional[UUID],
    filename: Optional[str],
    file_size_bytes: Optional[int],
    status: str = "pending",
    storage_path: Optional[str] = None,
) -> UUID:
    """Insert a shell for the VMAF result which will be updated later."""
    pool = await get_pool()
    row = await pool.fetchrow(
        """
        INSERT INTO vmaf_results (session_id, filename, file_size_bytes, status, storage_path)
        VALUES ($1, $2, $3, $4, $5)
        RETURNING id
        """,
        session_id,
        filename,
        file_size_bytes,
        status,
        storage_path,
    )
    return row["id"]


async def update_vmaf_result(
    record_id: UUID,
    status: str,
    vmaf_score: Optional[float] = None,
    raw_output: Optional[dict] = None,
    storage_path: Optional[str] = None,
) -> None:
    """Update an existing VMAF result with the actual score and final status."""
    pool = await get_pool()
    await pool.execute(
        """
        UPDATE vmaf_results
        SET status = $2, vmaf_score = $3, raw_output = $4::jsonb, storage_path = COALESCE($5, storage_path)
        WHERE id = $1
        """,
        record_id,
        status,
        vmaf_score,
        _jsonb(raw_output) if raw_output else None,
        storage_path,
    )


async def get_vmaf_result(record_id: UUID) -> Optional[dict]:
    """Fetch a VMAF result by its ID to check status/score."""
    pool = await get_pool()
    row = await pool.fetchrow(
        "SELECT id, status, vmaf_score, created_at FROM vmaf_results WHERE id = $1",
        record_id,
    )
    return dict(row) if row else None


# ─── 3. PEAQ ──────────────────────────────────────────────────────────────────

async def insert_peaq_result(
    *,
    session_id: Optional[UUID],
    degraded_filename: Optional[str],
    noise_filename: Optional[str],
    result: dict,
) -> UUID:
    """
    result is whatever compute_peaq_odg() returns.
    Expected keys: odg_score (wiener), raw_odg, ffmpeg_odg, odg_label
    """
    pool = await get_pool()
    has_noise = noise_filename is not None
    row = await pool.fetchrow(
        """
        INSERT INTO peaq_results (
            session_id, degraded_filename, noise_filename,
            has_noise_reduction, odg_score, raw_odg, ffmpeg_odg,
            odg_label, raw_output,
            degraded_storage_path, noise_storage_path
        )
        VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9::jsonb, $10, $11)
        RETURNING id
        """,
        session_id,
        degraded_filename,
        noise_filename,
        has_noise,
        result.get("odg_score"),
        result.get("raw_odg"),
        result.get("ffmpeg_odg"),
        result.get("odg_label"),
        _jsonb(result),
        result.get("degraded_storage_path"),
        result.get("noise_storage_path"),
    )
    return row["id"]


# ─── 4. PESQ (upload) ─────────────────────────────────────────────────────────

async def insert_pesq_result(
    *,
    session_id: Optional[UUID],
    degraded_filename: Optional[str],
    test_type: str = "upload",
    result: dict,
) -> UUID:
    """Insert a single-score PESQ result (POST /pesq/score)."""
    pool = await get_pool()
    row = await pool.fetchrow(
        """
        INSERT INTO pesq_results (
            session_id, call_type, recorded_filename,
            direct_pesq, raw_output, storage_path
        )
        VALUES ($1,$2,$3,$4,$5::jsonb, $6)
        RETURNING id
        """,
        session_id,
        test_type,
        degraded_filename,
        result.get("pesq_score"),
        _jsonb(result),
        result.get("storage_path"),
    )
    return row["id"]


# ─── 5. PESQ (WebRTC simulated / device call) ─────────────────────────────────

async def insert_pesq_result_from_webrtc(
    *,
    session_id: Optional[UUID],
    call_type: str = "simulated",     # "simulated" | "device"
    recorded_filename: Optional[str] = None,
    result: dict,
) -> UUID:
    """
    result expected keys (nested mappings):
    - direct_recording      (hardware only)
    - traditional_narrowband (G.711 / PSTN)
    - volte_wideband        (AMR-WB / VoLTE)
    - voip_wideband         (Opus / VoIP)
    """
    pool = await get_pool()
    row = await pool.fetchrow(
        """
        INSERT INTO pesq_results (
            session_id, call_type, recorded_filename,
            direct_pesq, pstn_pesq, volte_pesq, voip_pesq,
            raw_output, storage_path
        )
        VALUES ($1,$2,$3,$4,$5,$6,$7,$8::jsonb, $9)
        RETURNING id
        """,
        session_id,
        call_type,
        recorded_filename,
        result.get("direct_recording", {}).get("pesq_score"),
        result.get("traditional_narrowband", {}).get("pesq_score"),
        result.get("volte_wideband", {}).get("pesq_score"),
        result.get("voip_wideband", {}).get("pesq_score"),
        _jsonb(result),
        result.get("storage_path"),
    )
    return row["id"]


# ─── 6. IQA ───────────────────────────────────────────────────────────────────

async def insert_iqa_results(
    *,
    session_id: Optional[UUID],
    filenames: list[Optional[str]],
    file_sizes: list[Optional[int]],
    results: list[dict],             # list of {"image_index":…, "brisque":…, …}
) -> list[UUID]:
    """Insert one row per image; returns list of inserted UUIDs."""
    pool = await get_pool()
    ids: list[UUID] = []

    async with pool.acquire() as conn:
        for scores in results:
            idx = scores["image_index"]
            row = await conn.fetchrow(
                """
                INSERT INTO iqa_results (
                    session_id, image_index, filename, file_size_bytes,
                    brisque, niqe, piqe, raw_output, storage_path
                )
                VALUES ($1,$2,$3,$4,$5,$6,$7,$8::jsonb, $9)
                RETURNING id
                """,
                session_id,
                idx,
                filenames[idx] if idx < len(filenames) else None,
                file_sizes[idx] if idx < len(file_sizes) else None,
                scores.get("brisque"),
                scores.get("niqe"),
                scores.get("piqe"),
                _jsonb(scores),
                scores.get("storage_path"),
            )
            ids.append(row["id"])

    return ids