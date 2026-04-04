from pydantic import BaseModel
from typing import Optional


class DeviceMeta(BaseModel):
    # ── Tester Identity (from Google Sign-In) ─────────────────────────────────
    username: Optional[str] = None
    user_email: Optional[str] = None
    user_photo_url: Optional[str] = None

    # ── Questionnaire Answers ─────────────────────────────────────────────────
    age_group: Optional[str] = None
    phone_condition: Optional[str] = None
    phone_duration: Optional[str] = None
    phone_history: Optional[str] = None
    primary_usage: Optional[str] = None
    internet_frequency: Optional[str] = None
    phone_sharing: Optional[str] = None
    internet_connection_type: Optional[str] = None
    phone_acquisition: Optional[str] = None

    # ── Device Hardware ───────────────────────────────────────────────────────
    device_model: Optional[str] = None
    device_brand: Optional[str] = None
    device_manufacturer: Optional[str] = None
    device_product: Optional[str] = None
    device_hardware: Optional[str] = None
    supported_abis: Optional[str] = None
    cpu_cores: Optional[int] = None

    # ── OS & System ───────────────────────────────────────────────────────────
    android_version: Optional[str] = None
    sdk_version: Optional[int] = None
    build_number: Optional[str] = None
    security_patch_level: Optional[str] = None
    build_fingerprint: Optional[str] = None
    bootloader: Optional[str] = None
    is_physical_device: Optional[bool] = None
    is_rooted: Optional[bool] = None

    # ── App Info ──────────────────────────────────────────────────────────────
    app_package_name: Optional[str] = None
    app_version_name: Optional[str] = None
    app_version_code: Optional[int] = None
    app_installer_package: Optional[str] = None
    is_debug_build: Optional[bool] = None

    # ── Screen ────────────────────────────────────────────────────────────────
    screen_width_px: Optional[float] = None
    screen_height_px: Optional[float] = None
    screen_density: Optional[float] = None
    display_refresh_rate: Optional[float] = None

    # ── Locale ────────────────────────────────────────────────────────────────
    device_language: Optional[str] = None
    device_locale: Optional[str] = None
    timezone: Optional[str] = None
    country_code: Optional[str] = None

    # ── Battery ───────────────────────────────────────────────────────────────
    battery_level: Optional[int] = None
    battery_state: Optional[str] = None

    # ── Network ───────────────────────────────────────────────────────────────
    connection_type: Optional[str] = None
    wifi_name: Optional[str] = None
    wifi_bssid: Optional[str] = None
    local_ipv4: Optional[str] = None
    local_ipv6: Optional[str] = None
    is_vpn_active: Optional[bool] = None
    network_speed_category: Optional[str] = None
    network_latency_ms: Optional[int] = None

    # ── Location ──────────────────────────────────────────────────────────────
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    altitude: Optional[float] = None
    location_accuracy: Optional[float] = None
    speed: Optional[float] = None
    bearing: Optional[float] = None
    locality: Optional[str] = None
    country: Optional[str] = None
    postal_code: Optional[str] = None
    admin_area: Optional[str] = None
    iso_country_code: Optional[str] = None

    # ── Permissions ───────────────────────────────────────────────────────────
    permission_statuses: Optional[dict] = None

    # ── Session Activity ──────────────────────────────────────────────────────
    session_start: Optional[str] = None
    session_screen_views: Optional[int] = None
    session_user_actions: Optional[int] = None
    session_background_count: Optional[int] = None

    # ── Performance ───────────────────────────────────────────────────────────
    app_launch_time_ms: Optional[int] = None
    frame_drop_count: Optional[int] = None
    last_crash_info: Optional[str] = None

    # ── Memory & Storage ──────────────────────────────────────────────────────
    device_tier: Optional[str] = None
    total_ram_mb: Optional[int] = None
    available_ram_mb: Optional[int] = None
    total_disk_mb: Optional[int] = None
    free_disk_mb: Optional[int] = None

    # ── Audio ─────────────────────────────────────────────────────────────────
    audio_output_route: Optional[str] = None