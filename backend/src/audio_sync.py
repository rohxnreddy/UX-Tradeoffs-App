from __future__ import annotations

import io
import wave
from pathlib import Path

import numpy as np
from scipy.signal import fftconvolve

SYNC_MARKER_DEFAULT_PROFILE = "pesq"
SYNC_MARKER_PROFILES = {
    "pesq": {
        "name": "pesq",
        "version": "chirp-v1-pesq",
        "start_hz": 1800.0,
        "end_hz": 4200.0,
        "sweep_duration_seconds": 0.045,
        "intra_gap_seconds": 0.012,
        "repeat_count": 1,
        "repeat_gap_seconds": 0.0,
        "leading_silence_seconds": 0.0,
        "content_gap_seconds": 0.08,
        "tail_seconds": 0.12,
        "search_seconds": 2.5,
        "confidence_threshold": 0.35,
        "prominence_threshold": 4.0,
        "amplitude": 0.8,
    },
    "peaq": {
        "name": "peaq",
        "version": "chirp-v1-shared-peaq-lead",
        "start_hz": 1800.0,
        "end_hz": 4200.0,
        "sweep_duration_seconds": 0.045,
        "intra_gap_seconds": 0.012,
        "repeat_count": 1,
        "repeat_gap_seconds": 0.0,
        "leading_silence_seconds": 0.35,
        "content_gap_seconds": 0.08,
        "tail_seconds": 0.12,
        "search_seconds": 4.0,
        "confidence_threshold": 0.3,
        "prominence_threshold": 3.2,
        "amplitude": 0.8,
    },
}


def _get_sync_profile(profile: str | None) -> dict[str, float | str | int]:
    profile_name = profile or SYNC_MARKER_DEFAULT_PROFILE
    if profile_name not in SYNC_MARKER_PROFILES:
        raise ValueError(f"Unknown sync profile: {profile_name}")
    return SYNC_MARKER_PROFILES[profile_name]


def get_sync_marker_version(profile: str | None = None) -> str:
    sync_profile = _get_sync_profile(profile)
    return str(sync_profile["version"])


def _load_wav(file_path: str | Path) -> tuple[np.ndarray, int]:
    path = Path(file_path)
    with wave.open(str(path), "rb") as wav_file:
        sample_rate = wav_file.getframerate()
        channels = wav_file.getnchannels()
        sample_width = wav_file.getsampwidth()
        frame_count = wav_file.getnframes()
        raw = wav_file.readframes(frame_count)

    if sample_width == 2:
        samples = np.frombuffer(raw, dtype=np.int16).astype(np.float64) / 32768.0
    elif sample_width == 4:
        samples = np.frombuffer(raw, dtype=np.int32).astype(np.float64) / 2147483648.0
    else:
        raise ValueError(f"Unsupported sample width: {sample_width}")

    if channels == 2:
        samples = samples.reshape(-1, 2).mean(axis=1)
    elif channels > 2:
        samples = samples.reshape(-1, channels).mean(axis=1)

    return samples, sample_rate


def _write_wav_bytes(samples: np.ndarray, sample_rate: int) -> bytes:
    clipped = np.clip(samples, -1.0, 1.0)
    int16_data = (clipped * 32767).astype(np.int16)

    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        wav_file.writeframes(int16_data.tobytes())
    return buffer.getvalue()


def _linear_chirp(
    sample_rate: int,
    duration_seconds: float,
    start_hz: float,
    end_hz: float,
) -> np.ndarray:
    sample_count = max(1, int(round(sample_rate * duration_seconds)))
    t = np.linspace(0.0, duration_seconds, sample_count, endpoint=False)
    sweep_rate = (end_hz - start_hz) / max(duration_seconds, 1e-9)
    phase = 2.0 * np.pi * (start_hz * t + 0.5 * sweep_rate * t * t)
    chirp = np.sin(phase)
    if sample_count > 2:
        chirp *= np.hanning(sample_count)
    return chirp


def generate_sync_marker(
    sample_rate: int,
    profile: str | None = None,
) -> np.ndarray:
    sync_profile = _get_sync_profile(profile)
    sweep_duration = float(sync_profile["sweep_duration_seconds"])
    start_hz = float(sync_profile["start_hz"])
    end_hz = float(sync_profile["end_hz"])
    intra_gap = np.zeros(
        max(1, int(round(sample_rate * float(sync_profile["intra_gap_seconds"])))),
        dtype=np.float64,
    )
    repeat_gap = np.zeros(
        max(1, int(round(sample_rate * float(sync_profile["repeat_gap_seconds"])))),
        dtype=np.float64,
    )
    segments: list[np.ndarray] = []
    repeat_count = int(sync_profile["repeat_count"])
    for repeat_index in range(repeat_count):
        up = _linear_chirp(sample_rate, sweep_duration, start_hz, end_hz)
        down = _linear_chirp(sample_rate, sweep_duration, end_hz, start_hz)
        segments.extend([up, intra_gap, down])
        if repeat_index < repeat_count - 1 and len(repeat_gap) > 0:
            segments.append(repeat_gap)

    marker = np.concatenate(segments).astype(np.float64)
    peak = float(np.max(np.abs(marker)))
    if peak > 0:
        marker = float(sync_profile["amplitude"]) * (marker / peak)
    return marker


def build_playback_audio(
    reference: np.ndarray,
    sample_rate: int,
    profile: str | None = None,
) -> np.ndarray:
    sync_profile = _get_sync_profile(profile)
    lead_in_samples = int(round(sample_rate * float(sync_profile["leading_silence_seconds"])))
    lead_in = np.zeros(
        lead_in_samples,
        dtype=np.float64,
    )
    marker = generate_sync_marker(sample_rate, profile=profile)
    guard = np.zeros(
        max(1, int(round(sample_rate * float(sync_profile["content_gap_seconds"])))),
        dtype=np.float64,
    )
    tail = np.zeros(
        max(1, int(round(sample_rate * float(sync_profile["tail_seconds"])))),
        dtype=np.float64,
    )
    return np.concatenate([lead_in, marker, guard, reference, tail]).astype(np.float64)


def build_playback_wav(
    reference_audio: str | Path,
    profile: str | None = None,
) -> bytes:
    reference, sample_rate = _load_wav(reference_audio)
    playback = build_playback_audio(reference, sample_rate, profile=profile)
    return _write_wav_bytes(playback, sample_rate)


def detect_sync_marker(
    samples: np.ndarray,
    sample_rate: int,
    profile: str | None = None,
) -> dict[str, float | int | bool | str]:
    sync_profile = _get_sync_profile(profile)
    marker = generate_sync_marker(sample_rate, profile=profile)
    search_window = min(len(samples), int(round(sample_rate * float(sync_profile["search_seconds"]))))
    marker_len = len(marker)

    if search_window < marker_len:
        return {
            "profile": str(sync_profile["name"]),
            "version": str(sync_profile["version"]),
            "found": False,
            "confidence": 0.0,
            "prominence": 0.0,
            "marker_start_sample": 0,
            "content_start_sample": 0,
            "search_window_samples": search_window,
            "marker_samples": marker_len,
        }

    search = samples[:search_window]
    correlation = fftconvolve(search, marker[::-1], mode="valid")
    magnitude = np.abs(correlation)
    peak_index = int(np.argmax(magnitude))
    peak_value = float(magnitude[peak_index])
    segment = search[peak_index: peak_index + marker_len]
    denominator = (np.linalg.norm(segment) * np.linalg.norm(marker)) + 1e-12
    confidence = float(np.abs(np.dot(segment, marker)) / denominator)
    median_value = float(np.median(magnitude)) + 1e-12
    prominence = float(peak_value / median_value)
    content_start = peak_index + marker_len + int(
        round(sample_rate * float(sync_profile["content_gap_seconds"]))
    )
    found = (
        confidence >= float(sync_profile["confidence_threshold"])
        and prominence >= float(sync_profile["prominence_threshold"])
    )

    return {
        "profile": str(sync_profile["name"]),
        "version": str(sync_profile["version"]),
        "found": found,
        "confidence": round(confidence, 4),
        "prominence": round(prominence, 4),
        "marker_start_sample": peak_index,
        "content_start_sample": content_start,
        "search_window_samples": search_window,
        "marker_samples": marker_len,
    }


def trim_playback_capture(
    samples: np.ndarray,
    sample_rate: int,
    expected_content_samples: int,
    profile: str | None = None,
) -> tuple[np.ndarray, dict[str, float | int | bool | str]]:
    detection = detect_sync_marker(samples, sample_rate, profile=profile)
    trimmed = samples

    if detection["found"]:
        start = int(detection["content_start_sample"])
        end = min(len(samples), start + expected_content_samples)
        if 0 <= start < end:
            trimmed = samples[start:end]

    details = {
        **detection,
        "expected_content_samples": expected_content_samples,
        "trimmed_samples": len(trimmed),
        "trimmed_duration_seconds": round(len(trimmed) / sample_rate, 3),
    }
    return trimmed, details
