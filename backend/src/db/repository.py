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


# ─── 1. Device Session ────────────────────────────────────────────────────────

async def insert_device_session(meta: dict) -> UUID:
    """
    Insert a device_sessions row from the raw DeviceMeta dict.
    Includes tester identity (Google Sign-In) and questionnaire answers.
    Returns the new UUID so callers can attach subsequent test results.
    """
    pool = await get_pool()

    row = await pool.fetchrow(
        """
        INSERT INTO device_sessions (
            -- Tester identity
            tester_name, tester_email, tester_photo_url,

            -- Questionnaire answers
            device_usage, network_env, testing_purpose, usage_frequency,

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
            -- Tester identity
            $1, $2, $3,

            -- Questionnaire answers
            $4, $5, $6, $7,

            -- Hardware
            $8, $9, $10, $11, $12, $13, $14,

            -- OS & System
            $15, $16, $17, $18, $19, $20, $21, $22,

            -- App
            $23, $24, $25, $26, $27,

            -- Screen
            $28, $29, $30, $31,

            -- Locale
            $32, $33, $34, $35,

            -- Battery
            $36, $37,

            -- Network
            $38, $39, $40, $41, $42, $43, $44, $45,

            -- Location
            $46, $47, $48, $49, $50, $51, $52, $53, $54, $55, $56,

            -- Permissions
            $57::jsonb,

            -- Session Activity
            $58, $59, $60, $61,

            -- Performance
            $62, $63, $64,

            -- Memory & Storage
            $65, $66, $67, $68, $69,

            -- Audio
            $70
        )
        RETURNING id
        """,
        # Tester identity ($1–$3)
        meta.get("tester_name"),
        meta.get("tester_email"),
        meta.get("tester_photo_url"),

        # Questionnaire answers ($4–$7)
        meta.get("device_usage"),
        meta.get("network_env"),
        meta.get("testing_purpose"),
        meta.get("usage_frequency"),

        # Hardware ($8–$14)
        meta.get("device_model"),
        meta.get("device_brand"),
        meta.get("device_manufacturer"),
        meta.get("device_product"),
        meta.get("device_hardware"),
        meta.get("supported_abis"),
        meta.get("cpu_cores"),

        # OS & System ($15–$22)
        meta.get("android_version"),
        meta.get("sdk_version"),
        meta.get("build_number"),
        meta.get("security_patch_level"),
        meta.get("build_fingerprint"),
        meta.get("bootloader"),
        meta.get("is_physical_device"),
        meta.get("is_rooted"),

        # App ($23–$27)
        meta.get("app_package_name"),
        meta.get("app_version_name"),
        meta.get("app_version_code"),
        meta.get("app_installer_package"),
        meta.get("is_debug_build"),

        # Screen ($28–$31)
        meta.get("screen_width_px"),
        meta.get("screen_height_px"),
        meta.get("screen_density"),
        meta.get("display_refresh_rate"),

        # Locale ($32–$35)
        meta.get("device_language"),
        meta.get("device_locale"),
        meta.get("timezone"),
        meta.get("country_code"),

        # Battery ($36–$37)
        meta.get("battery_level"),
        meta.get("battery_state"),

        # Network ($38–$45)
        meta.get("connection_type"),
        meta.get("wifi_name"),
        meta.get("wifi_bssid"),
        meta.get("local_ipv4"),
        meta.get("local_ipv6"),
        meta.get("is_vpn_active"),
        meta.get("network_speed_category"),
        meta.get("network_latency_ms"),

        # Location ($46–$56)
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

        # Permissions ($57)
        _jsonb(meta.get("permission_statuses")),

        # Session Activity ($58–$61)
        _parse_dt(meta.get("session_start")),
        meta.get("session_screen_views"),
        meta.get("session_user_actions"),
        meta.get("session_background_count"),

        # Performance ($62–$64)
        meta.get("app_launch_time_ms"),
        meta.get("frame_drop_count"),
        meta.get("last_crash_info"),

        # Memory & Storage ($65–$69)
        meta.get("device_tier"),
        meta.get("total_ram_mb"),
        meta.get("available_ram_mb"),
        meta.get("total_disk_mb"),
        meta.get("free_disk_mb"),

        # Audio ($70)
        meta.get("audio_output_route"),
    )
    return row["id"]


# ─── 2. VMAF ──────────────────────────────────────────────────────────────────

async def insert_vmaf_result(
    *,
    session_id: Optional[UUID],
    filename: Optional[str],
    file_size_bytes: Optional[int],
    result: dict,
) -> UUID:
    """result = {"vmaf_score": float, ...}"""
    pool = await get_pool()
    row = await pool.fetchrow(
        """
        INSERT INTO vmaf_results (session_id, filename, file_size_bytes, vmaf_score, raw_output)
        VALUES ($1, $2, $3, $4, $5::jsonb)
        RETURNING id
        """,
        session_id,
        filename,
        file_size_bytes,
        result.get("vmaf_score"),
        _jsonb(result),
    )
    return row["id"]


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
    Expected keys: odg_score (wiener), raw_odg, ffmpeg_odg,
                   odg_label, subtracted_audio_b64 (optional)
    """
    pool = await get_pool()
    has_noise = noise_filename is not None
    row = await pool.fetchrow(
        """
        INSERT INTO peaq_results (
            session_id, degraded_filename, noise_filename,
            has_noise_reduction, odg_score, raw_odg, ffmpeg_odg,
            odg_label, subtracted_audio_b64, raw_output
        )
        VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10::jsonb)
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
        result.get("subtracted_audio_b64"),
        _jsonb(result),
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
            direct_pesq, raw_output
        )
        VALUES ($1,$2,$3,$4,$5::jsonb)
        RETURNING id
        """,
        session_id,
        test_type,
        degraded_filename,
        result.get("pesq_score"),
        _jsonb(result),
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
            degraded_audio_b64, raw_output
        )
        VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9::jsonb)
        RETURNING id
        """,
        session_id,
        call_type,
        recorded_filename,
        result.get("direct_recording", {}).get("pesq_score"),
        result.get("traditional_narrowband", {}).get("pesq_score"),
        result.get("volte_wideband", {}).get("pesq_score"),
        result.get("voip_wideband", {}).get("pesq_score"),
        result.get("degraded_audio_b64"),
        _jsonb(result),
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
                    brisque, niqe, piqe, raw_output
                )
                VALUES ($1,$2,$3,$4,$5,$6,$7,$8::jsonb)
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
            )
            ids.append(row["id"])

    return ids