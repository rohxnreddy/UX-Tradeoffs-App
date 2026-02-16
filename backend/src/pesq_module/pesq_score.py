import numpy as np
from scipy.signal import resample
from pathlib import Path
import wave
import io
import base64

try:
    from pesq import pesq as pesq_score
except ImportError:
    pesq_score = None


class PESQError(Exception):
    pass


REFERENCE_AUDIO = Path(__file__).resolve().parent.parent.parent / "peaq-pesq-audio" / "pesq.wav"


def _load_wav(file_path: str | Path) -> tuple[np.ndarray, int]:
    """Load a WAV file and return (samples_float64, sample_rate)."""
    path = Path(file_path)
    if not path.exists():
        raise PESQError(f"Audio file not found: {path}")

    try:
        with wave.open(str(path), "r") as w:
            sr = w.getframerate()
            ch = w.getnchannels()
            sw = w.getsampwidth()
            n = w.getnframes()
            raw = w.readframes(n)
    except wave.Error as e:
        raise PESQError(f"Failed to read WAV file {path}: {e}")

    if sw == 2:
        samples = np.frombuffer(raw, dtype=np.int16).astype(np.float64) / 32768.0
    elif sw == 4:
        samples = np.frombuffer(raw, dtype=np.int32).astype(np.float64) / 2147483648.0
    else:
        raise PESQError(f"Unsupported sample width: {sw} bytes")

    # Convert to mono
    if ch == 2:
        samples = samples.reshape(-1, 2).mean(axis=1)
    elif ch > 2:
        samples = samples.reshape(-1, ch).mean(axis=1)

    return samples, sr


def _resample_to(samples: np.ndarray, orig_sr: int, target_sr: int) -> np.ndarray:
    """Resample audio to target sample rate."""
    if orig_sr == target_sr:
        return samples
    num_samples = int(len(samples) * target_sr / orig_sr)
    return resample(samples, num_samples)


def _float_to_int16(samples: np.ndarray) -> np.ndarray:
    """Convert float64 samples [-1, 1] to int16."""
    return np.clip(samples * 32768.0, -32768, 32767).astype(np.int16)


def _write_wav_b64(samples_float: np.ndarray, sr: int) -> str:
    """Convert float64 samples to a base64-encoded WAV string."""
    int16_data = _float_to_int16(samples_float)
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(int16_data.tobytes())
    return base64.b64encode(buf.getvalue()).decode("ascii")


def compute_pesq(
    degraded_audio: str | Path,
    reference_audio: str | Path = REFERENCE_AUDIO,
) -> dict:
    """
    Compute PESQ scores (wideband and narrowband) between reference and degraded audio.
    """
    if pesq_score is None:
        raise PESQError("pesq package is not installed. Install with: pip install pesq")

    ref_path = Path(reference_audio).resolve()
    deg_path = Path(degraded_audio).resolve()

    if not ref_path.exists():
        raise PESQError(f"Reference audio not found: {ref_path}")
    if not deg_path.exists():
        raise PESQError(f"Degraded audio not found: {deg_path}")

    ref, fs_ref = _load_wav(ref_path)
    deg, fs_deg = _load_wav(deg_path)

    details = {
        "ref_sample_rate": fs_ref,
        "deg_sample_rate": fs_deg,
        "ref_duration": round(len(ref) / fs_ref, 2),
        "deg_duration": round(len(deg) / fs_deg, 2),
    }

    target_sr = 16000
    ref_16k = _resample_to(ref, fs_ref, target_sr)
    deg_16k = _resample_to(deg, fs_deg, target_sr)

    min_len = min(len(ref_16k), len(deg_16k))
    ref_16k = ref_16k[:min_len]
    deg_16k = deg_16k[:min_len]
    details["analysis_duration"] = round(min_len / target_sr, 2)

    ref_int16 = _float_to_int16(ref_16k)
    deg_int16 = _float_to_int16(deg_16k)

    result = {}

    try:
        wb_score = pesq_score(target_sr, ref_int16, deg_int16, "wb")
        result["pesq_wb"] = round(float(wb_score), 3)
    except Exception as e:
        result["pesq_wb"] = None
        result["pesq_wb_error"] = str(e)

    try:
        nb_score = pesq_score(target_sr, ref_int16, deg_int16, "nb")
        result["pesq_nb"] = round(float(nb_score), 3)
    except Exception as e:
        result["pesq_nb"] = None
        result["pesq_nb_error"] = str(e)

    result["details"] = details
    return result


def compute_pesq_comparison(
    reference_audio: str | Path = REFERENCE_AUDIO,
) -> dict:
    """
    Simulate narrowband (8 kHz) vs wideband (16 kHz) codec degradation
    and compare PESQ scores. Returns degraded audio as base64 for playback.
    """
    if pesq_score is None:
        raise PESQError("pesq package is not installed. Install with: pip install pesq")

    ref_path = Path(reference_audio).resolve()
    if not ref_path.exists():
        raise PESQError(f"Reference audio not found: {ref_path}")

    ref, fs_ref = _load_wav(ref_path)

    # === Wideband simulation (16 kHz - VoIP quality) ===
    ref_16k = _resample_to(ref, fs_ref, 16000)
    ref_16k_int16 = _float_to_int16(ref_16k)

    wb_degraded = ref_16k.copy()
    wb_degraded = np.round(wb_degraded * 256) / 256
    wb_degraded += np.random.normal(0, 0.001, len(wb_degraded))
    wb_degraded = np.clip(wb_degraded, -1.0, 1.0)
    wb_deg_int16 = _float_to_int16(wb_degraded)

    # === Narrowband simulation (8 kHz - traditional phone quality) ===
    ref_8k = _resample_to(ref, fs_ref, 8000)
    nb_degraded = ref_8k.copy()
    nb_degraded = np.round(nb_degraded * 128) / 128
    nb_degraded += np.random.normal(0, 0.005, len(nb_degraded))
    nb_degraded = np.clip(nb_degraded, -1.0, 1.0)
    nb_degraded_16k = _resample_to(nb_degraded, 8000, 16000)

    # Trim to match lengths
    min_len = min(len(ref_16k), len(nb_degraded_16k))
    ref_trimmed = _float_to_int16(ref_16k[:min_len])
    nb_trimmed = _float_to_int16(nb_degraded_16k[:min_len])

    result = {
        "description": "Comparison of narrowband (traditional call, 8 kHz) vs wideband (VoIP, 16 kHz) quality",
        # Base64 audio for playback
        "reference_audio_b64": _write_wav_b64(ref_16k, 16000),
        "wb_degraded_audio_b64": _write_wav_b64(wb_degraded, 16000),
        "nb_degraded_audio_b64": _write_wav_b64(nb_degraded, 8000),
    }

    # Wideband PESQ score
    try:
        wb_pesq = pesq_score(16000, ref_16k_int16, wb_deg_int16, "wb")
        result["voip_wideband"] = {
            "pesq_score": round(float(wb_pesq), 3),
            "sample_rate": 16000,
            "codec_simulation": "Wideband VoIP (Opus/G.722-like)",
        }
    except Exception as e:
        result["voip_wideband"] = {"error": str(e)}

    # Narrowband PESQ score
    try:
        nb_pesq = pesq_score(16000, ref_trimmed, nb_trimmed, "nb")
        result["traditional_narrowband"] = {
            "pesq_score": round(float(nb_pesq), 3),
            "sample_rate": 8000,
            "codec_simulation": "Narrowband telephony (G.711-like)",
        }
    except Exception as e:
        result["traditional_narrowband"] = {"error": str(e)}

    return result
