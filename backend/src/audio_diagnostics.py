from __future__ import annotations

import math

import numpy as np


def _dbfs(amplitude: float) -> float:
    return 20.0 * math.log10(max(float(amplitude), 1e-6))


def _frame_rms(samples: np.ndarray, frame_size: int) -> np.ndarray:
    if len(samples) == 0:
        return np.zeros(0, dtype=np.float64)

    if len(samples) <= frame_size:
        return np.array([float(np.sqrt(np.mean(samples ** 2)))], dtype=np.float64)

    frame_count = len(samples) // frame_size
    trimmed = samples[: frame_count * frame_size].reshape(frame_count, frame_size)
    rms = np.sqrt(np.mean(trimmed ** 2, axis=1))

    remainder = samples[frame_count * frame_size :]
    if len(remainder) > 0:
        tail_rms = float(np.sqrt(np.mean(remainder ** 2)))
        rms = np.concatenate([rms, np.array([tail_rms], dtype=np.float64)])

    return rms.astype(np.float64)


def summarize_capture_diagnostics(
    samples: np.ndarray,
    sample_rate: int,
    *,
    expected_samples: int | None = None,
    sync_details: dict | None = None,
    content_kind: str = "speech",
) -> dict[str, object]:
    if len(samples) == 0:
        return {
            "trust_level": "low",
            "trust_label": "Low",
            "trust_score": 0,
            "summary": "No audio captured",
            "flags": ["empty"],
            "duration_seconds": 0.0,
            "duration_percent": 0.0,
            "rms_dbfs": -120.0,
            "peak_dbfs": -120.0,
            "clipped_percent": 0.0,
            "active_percent": 0.0,
            "sync_found": bool(sync_details.get("found")) if isinstance(sync_details, dict) else None,
            "sync_confidence": float(sync_details.get("confidence", 0.0)) if isinstance(sync_details, dict) else None,
        }

    abs_samples = np.abs(samples)
    rms = float(np.sqrt(np.mean(samples ** 2)))
    peak = float(np.max(abs_samples))
    clipped_percent = float(np.mean(abs_samples >= 0.995) * 100.0)

    frame_size = max(1, int(round(sample_rate * 0.05)))
    frame_rms = _frame_rms(samples, frame_size)
    noise_floor = float(np.percentile(frame_rms, 10)) if len(frame_rms) > 0 else 0.0
    active_multiplier = 2.5 if content_kind == "speech" else 1.8
    active_floor = 0.01 if content_kind == "speech" else 0.006
    active_threshold = max(active_floor, noise_floor * active_multiplier)
    active_percent = float(np.mean(frame_rms >= active_threshold) * 100.0) if len(frame_rms) > 0 else 0.0

    duration_seconds = len(samples) / sample_rate
    duration_percent = 100.0
    if expected_samples and expected_samples > 0:
        duration_percent = float(len(samples) / expected_samples * 100.0)

    sync_found = None
    sync_confidence = None
    if isinstance(sync_details, dict):
        sync_found = bool(sync_details.get("found"))
        confidence_value = sync_details.get("confidence")
        if confidence_value is not None:
            sync_confidence = float(confidence_value)

    trust_score = 100
    flags: list[str] = []

    if sync_found is False:
        trust_score -= 45
        flags.append("sync fail")
    elif sync_confidence is not None and sync_confidence < 0.55:
        trust_score -= 18
        flags.append("weak sync")

    if duration_percent < 90.0:
        trust_score -= 35
        flags.append("short")
    elif duration_percent < 97.0:
        trust_score -= 14
        flags.append("trimmed")

    rms_dbfs = _dbfs(rms)
    peak_dbfs = _dbfs(peak)

    if rms_dbfs < -34.0:
        trust_score -= 24
        flags.append("quiet")
    elif rms_dbfs < -28.0:
        trust_score -= 10
        flags.append("low level")

    if clipped_percent >= 0.5:
        trust_score -= 30
        flags.append("clipping")
    elif clipped_percent >= 0.1:
        trust_score -= 14
        flags.append("hot")

    if content_kind == "speech":
        if active_percent < 55.0:
            trust_score -= 15
            flags.append("gaps")
        elif active_percent < 70.0:
            trust_score -= 5
    else:
        if active_percent < 18.0:
            trust_score -= 8
            flags.append("gaps")
        elif active_percent < 30.0:
            trust_score -= 3

    trust_score = max(0, min(100, trust_score))
    if trust_score >= 80:
        trust_level = "high"
        trust_label = "High"
    elif trust_score >= 55:
        trust_level = "medium"
        trust_label = "Medium"
    else:
        trust_level = "low"
        trust_label = "Low"

    sync_text = "Sync fail"
    if sync_confidence is not None and sync_found is not False:
        sync_text = f"Sync {sync_confidence:.2f}"
    elif sync_confidence is None and sync_found is None:
        sync_text = "Sync n/a"

    summary_parts = [
        sync_text,
        f"{rms_dbfs:.1f} dBFS",
        f"{duration_percent:.0f}%",
    ]
    if clipped_percent >= 0.05:
        summary_parts.append(f"Clip {clipped_percent:.1f}%")

    return {
        "trust_level": trust_level,
        "trust_label": trust_label,
        "trust_score": trust_score,
        "summary": " | ".join(summary_parts),
        "flags": flags,
        "duration_seconds": round(duration_seconds, 3),
        "duration_percent": round(duration_percent, 1),
        "rms_dbfs": round(rms_dbfs, 2),
        "peak_dbfs": round(peak_dbfs, 2),
        "clipped_percent": round(clipped_percent, 3),
        "active_percent": round(active_percent, 1),
        "sync_found": sync_found,
        "sync_confidence": round(sync_confidence, 4) if sync_confidence is not None else None,
    }
