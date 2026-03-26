-- ============================================================
--  Quality Testing Platform — PostgreSQL Schema
--  Tables: device_sessions  →  [vmaf|peaq|pesq|iqa|webrtc]_results
-- ============================================================

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ─── 1. DEVICE SESSIONS ──────────────────────────────────────────────────────
--  One row per POST /device/metadata call.
--  All subsequent test results FK into this table.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS device_sessions (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
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

CREATE INDEX IF NOT EXISTS idx_device_sessions_created_at   ON device_sessions (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_device_sessions_device_model ON device_sessions (device_model);
CREATE INDEX IF NOT EXISTS idx_device_sessions_app_version  ON device_sessions (app_version_name);


-- ─── 2. VMAF RESULTS ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS vmaf_results (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id          UUID        REFERENCES device_sessions (id) ON DELETE SET NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Input context
    filename            TEXT,
    file_size_bytes     BIGINT,

    -- Score
    vmaf_score          NUMERIC(8,4) NOT NULL,

    -- Optional: store raw model output for reanalysis
    raw_output          JSONB
);

CREATE INDEX IF NOT EXISTS idx_vmaf_session    ON vmaf_results (session_id);
CREATE INDEX IF NOT EXISTS idx_vmaf_created_at ON vmaf_results (created_at DESC);


-- ─── 3. PEAQ RESULTS ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS peaq_results (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id              UUID        REFERENCES device_sessions (id) ON DELETE SET NULL,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Input context
    degraded_filename       TEXT,
    noise_filename          TEXT,           -- NULL when no noise file supplied
    has_noise_reduction     BOOLEAN NOT NULL DEFAULT FALSE,

    -- Score
    odg_score               NUMERIC(8,4),   -- Objective Difference Grade (-4 to 0)
    odg_label               TEXT,           -- e.g. "Imperceptible", "Perceptible but not annoying"

    -- Noise reduction artifact (base64 audio returned to client)
    subtracted_audio_b64    TEXT,           -- only populated when noise supplied

    raw_output              JSONB
);

CREATE INDEX IF NOT EXISTS idx_peaq_session    ON peaq_results (session_id);
CREATE INDEX IF NOT EXISTS idx_peaq_created_at ON peaq_results (created_at DESC);


-- ─── 4. PESQ RESULTS ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pesq_results (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id              UUID        REFERENCES device_sessions (id) ON DELETE SET NULL,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Input context
    degraded_filename       TEXT,
    test_type               TEXT NOT NULL DEFAULT 'upload',   -- 'upload' | 'comparison' | 'webrtc_simulated'

    -- Scores
    pesq_wb                 NUMERIC(6,4),   -- Wideband MOS-LQO  (1.0 – 4.5)
    pesq_nb                 NUMERIC(6,4),   -- Narrowband MOS-LQO (1.0 – 4.5)

    -- Comparison extras (populated only for /pesq/compare)
    wb_codec                TEXT,
    nb_codec                TEXT,
    sample_rate_hz          INT,

    raw_output              JSONB
);

CREATE INDEX IF NOT EXISTS idx_pesq_session    ON pesq_results (session_id);
CREATE INDEX IF NOT EXISTS idx_pesq_created_at ON pesq_results (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pesq_type       ON pesq_results (test_type);


-- ─── 5. WEBRTC CALL RESULTS ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS webrtc_results (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id              UUID        REFERENCES device_sessions (id) ON DELETE SET NULL,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- 'simulated' = GET /webrtc/call ; 'device' = POST /webrtc/device-call
    call_type               TEXT NOT NULL DEFAULT 'simulated',

    -- Scores (mirrors PESQ columns — WebRTC returns PESQ internally)
    opus_pesq_wb            NUMERIC(6,4),
    opus_pesq_nb            NUMERIC(6,4),
    g711_pesq_wb            NUMERIC(6,4),
    g711_pesq_nb            NUMERIC(6,4),

    -- Device call extras
    recorded_filename       TEXT,

    -- Degraded audio returned to client (base64)
    degraded_audio_b64      TEXT,

    raw_output              JSONB
);

CREATE INDEX IF NOT EXISTS idx_webrtc_session    ON webrtc_results (session_id);
CREATE INDEX IF NOT EXISTS idx_webrtc_created_at ON webrtc_results (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_webrtc_type       ON webrtc_results (call_type);


-- ─── 6. IQA RESULTS ──────────────────────────────────────────────────────────
--  One parent row per POST /iqa/score call (can hold many images).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS iqa_results (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id          UUID        REFERENCES device_sessions (id) ON DELETE SET NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- One row per image within the batch
    image_index         INT  NOT NULL,
    filename            TEXT,
    file_size_bytes     BIGINT,

    -- No-reference IQA metrics (lower = better for all three)
    brisque             NUMERIC(10,4),
    niqe                NUMERIC(10,4),
    piqe                NUMERIC(10,4),

    raw_output          JSONB
);

CREATE INDEX IF NOT EXISTS idx_iqa_session    ON iqa_results (session_id);
CREATE INDEX IF NOT EXISTS idx_iqa_created_at ON iqa_results (created_at DESC);