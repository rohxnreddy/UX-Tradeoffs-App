-- ============================================================
--  Quality Testing Platform — PostgreSQL Schema
--  Tables: users -> sessions  →  [vmaf|peaq|pesq|iqa]_results
-- ============================================================

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ─── 1. USERS ───────────────────────────────────────────────────────────────
--  One row per user (identified by email).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS users (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at              TIMESTAMPTZ NOT NULL    DEFAULT now(),

    -- Identity
    username                TEXT,
    user_email              TEXT        UNIQUE,
    user_photo_url          TEXT,

    -- Questionnaire Answers
    age_group               TEXT,
    phone_condition         TEXT,
    phone_duration          TEXT,
    phone_history           TEXT,
    primary_usage           TEXT,
    internet_frequency      TEXT,
    phone_sharing           TEXT,
    internet_connection_type TEXT,
    phone_acquisition       TEXT
);

CREATE INDEX IF NOT EXISTS idx_users_user_email ON users (user_email);


-- ─── 2. SESSIONS ─────────────────────────────────────────────────────────────
--  One row per POST /device/metadata call.
--  All subsequent test results FK into this table.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS sessions (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                 UUID        REFERENCES users (id) ON DELETE CASCADE,
    created_at              TIMESTAMPTZ NOT NULL    DEFAULT now(),

    -- Hardware
    device_model            TEXT,
    device_brand            TEXT,
    device_manufacturer     TEXT,
    device_product          TEXT,
    device_hardware         TEXT,
    supported_abis          TEXT,
    cpu_cores               INT,

    -- OS & System
    android_version         TEXT,
    sdk_version             INT,
    build_number            TEXT,
    security_patch_level    TEXT,
    build_fingerprint       TEXT,
    bootloader              TEXT,
    is_physical_device      BOOLEAN,
    is_rooted               BOOLEAN,

    -- App
    app_package_name        TEXT,
    app_version_name        TEXT,
    app_version_code        INT,
    app_installer_package   TEXT,
    is_debug_build          BOOLEAN,

    -- Screen
    screen_width_px         NUMERIC(10,2),
    screen_height_px        NUMERIC(10,2),
    screen_density          NUMERIC(10,4),
    display_refresh_rate    NUMERIC(10,4),

    -- Locale
    device_language         TEXT,
    device_locale           TEXT,
    timezone                TEXT,
    country_code            TEXT,

    -- Battery
    battery_level           INT,
    battery_state           TEXT,

    -- Network
    connection_type         TEXT,
    wifi_name               TEXT,
    wifi_bssid              TEXT,
    local_ipv4              INET,
    local_ipv6              INET,
    is_vpn_active           BOOLEAN,
    network_speed_category  TEXT,
    network_latency_ms      INT,

    -- Location
    latitude                NUMERIC(11,8),
    longitude               NUMERIC(11,8),
    altitude                NUMERIC(10,4),
    location_accuracy       NUMERIC(10,4),
    speed                   NUMERIC(10,4),
    bearing                 NUMERIC(10,4),
    locality                TEXT,
    country                 TEXT,
    postal_code             TEXT,
    admin_area              TEXT,
    iso_country_code        TEXT,

    -- Permissions (freeform JSON map)
    permission_statuses     JSONB,

    -- Session Activity
    session_start           TIMESTAMPTZ,
    session_screen_views    INT,
    session_user_actions    INT,
    session_background_count INT,

    -- Performance
    app_launch_time_ms      INT,
    frame_drop_count        INT,
    last_crash_info         TEXT,

    -- Memory & Storage
    device_tier             TEXT,
    total_ram_mb            INT,
    available_ram_mb        INT,
    total_disk_mb           INT,
    free_disk_mb            INT,

    -- Audio
    audio_output_route      TEXT
);

CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON sessions (user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_created_at    ON sessions (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sessions_device_model  ON sessions (device_model);
CREATE INDEX IF NOT EXISTS idx_sessions_app_version   ON sessions (app_version_name);


-- ─── 3. VMAF RESULTS ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS vmaf_results (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id          UUID        REFERENCES sessions (id) ON DELETE SET NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Input context
    filename            TEXT,
    file_size_bytes     BIGINT,

    -- Score (NULL until job completes)
    vmaf_score          NUMERIC(8,4),

    -- Job status: 'pending', 'processing', 'completed', 'failed'
    status              TEXT        NOT NULL DEFAULT 'pending',

    -- Local file path
    storage_path        TEXT,

    -- Optional: store raw model output for reanalysis
    raw_output          JSONB
);

CREATE INDEX IF NOT EXISTS idx_vmaf_session    ON vmaf_results (session_id);
CREATE INDEX IF NOT EXISTS idx_vmaf_created_at ON vmaf_results (created_at DESC);


-- ─── 4. PEAQ RESULTS ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS peaq_results (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id              UUID        REFERENCES sessions (id) ON DELETE SET NULL,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Input context
    degraded_filename       TEXT,
    noise_filename          TEXT,           -- NULL when no noise file supplied
    has_noise_reduction     BOOLEAN NOT NULL DEFAULT FALSE,

    -- Scores
    odg_score               NUMERIC(8,4),   -- Wiener-subtracted ODG (-4 to 0), primary score
    raw_odg                 NUMERIC(8,4),   -- Raw degraded ODG (no noise reduction)
    ffmpeg_odg              NUMERIC(8,4),   -- FFmpeg afftdn denoised ODG
    odg_label               TEXT,           -- e.g. "Imperceptible", "Perceptible but not annoying"

    degraded_storage_path   TEXT,
    noise_storage_path      TEXT,

    raw_output              JSONB
);

CREATE INDEX IF NOT EXISTS idx_peaq_session    ON peaq_results (session_id);
CREATE INDEX IF NOT EXISTS idx_peaq_created_at ON peaq_results (created_at DESC);


-- ─── 5. PESQ RESULTS ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pesq_results (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id              UUID        REFERENCES sessions (id) ON DELETE SET NULL,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- 'simulated' = GET /webrtc/call ; 'device' = POST /webrtc/device-call ; 'upload' = POST /pesq/score
    call_type               TEXT NOT NULL DEFAULT 'simulated',

    -- Scores
    direct_pesq             NUMERIC(6,4),   -- Phone hardware (no codec)
    pstn_pesq               NUMERIC(6,4),   -- G.711 codec
    volte_pesq              NUMERIC(6,4),   -- AMR-WB codec
    voip_pesq               NUMERIC(6,4),   -- Opus codec

    -- Device call extras
    recorded_filename       TEXT,

    storage_path            TEXT,

    raw_output              JSONB
);

CREATE INDEX IF NOT EXISTS idx_pesq_session    ON pesq_results (session_id);
CREATE INDEX IF NOT EXISTS idx_pesq_created_at ON pesq_results (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pesq_type       ON pesq_results (call_type);


-- ─── 6. IQA RESULTS ──────────────────────────────────────────────────────────
--  One row per image within a POST /camara/score batch call.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS iqa_results (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id          UUID        REFERENCES sessions (id) ON DELETE SET NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- One row per image within the batch
    image_index         INT  NOT NULL,
    filename            TEXT,
    file_size_bytes     BIGINT,

    -- No-reference IQA metrics (lower = better for all three)
    brisque             NUMERIC(10,4),
    niqe                NUMERIC(10,4),
    piqe                NUMERIC(10,4),

    -- Unified camera score (0-100, higher = better)
    -- Weighted geometric mean of "goodness" scores per metric.
    -- This correctly penalises catastrophic failures in any single dimension.
    camera_score        NUMERIC(10,4) GENERATED ALWAYS AS (
        POWER(GREATEST(100.0 - brisque, 0.0), 0.20) *
        POWER(GREATEST(100.0 - (niqe * 100.0 / 15.0), 0.0), 0.45) *
        POWER(GREATEST(100.0 - piqe, 0.0), 0.35)
    ) STORED,

    storage_path        TEXT,

    raw_output          JSONB
);

CREATE INDEX IF NOT EXISTS idx_iqa_session    ON iqa_results (session_id);
CREATE INDEX IF NOT EXISTS idx_iqa_created_at ON iqa_results (created_at DESC);