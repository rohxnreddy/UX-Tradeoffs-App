import numpy as np
from scipy.signal import stft, istft, resample
from pathlib import Path
import wave
import struct
import base64
import io


class PEAQError(Exception):
    pass


REFERENCE_AUDIO = Path(__file__).resolve().parent.parent.parent / "peaq-pesq-audio" / "peaq.wav"


def _load_wav(file_path: str | Path) -> tuple[np.ndarray, int]:
    """Load a WAV file and return (samples_float64, sample_rate)."""
    path = Path(file_path)
    if not path.exists():
        raise PEAQError(f"Audio file not found: {path}")

    try:
        with wave.open(str(path), "r") as w:
            sr = w.getframerate()
            ch = w.getnchannels()
            sw = w.getsampwidth()
            n = w.getnframes()
            raw = w.readframes(n)
    except wave.Error as e:
        raise PEAQError(f"Failed to read WAV file {path}: {e}")

    if sw == 2:
        samples = np.frombuffer(raw, dtype=np.int16).astype(np.float64) / 32768.0
    elif sw == 4:
        samples = np.frombuffer(raw, dtype=np.int32).astype(np.float64) / 2147483648.0
    else:
        raise PEAQError(f"Unsupported sample width: {sw} bytes")

    # Convert to mono
    if ch == 2:
        samples = samples.reshape(-1, 2).mean(axis=1)
    elif ch > 2:
        samples = samples.reshape(-1, ch).mean(axis=1)

    return samples, sr


def _write_wav_bytes(samples: np.ndarray, sr: int) -> bytes:
    """Write float64 samples to WAV bytes (16-bit PCM, mono)."""
    # Clip and convert to int16
    clipped = np.clip(samples, -1.0, 1.0)
    int16_data = (clipped * 32767).astype(np.int16)

    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(int16_data.tobytes())

    return buf.getvalue()


def spectral_subtract(
    degraded: np.ndarray,
    noise: np.ndarray,
    sr: int,
    oversubtraction: float = 2.0,
    gain_floor_db: float = -15.0,
) -> np.ndarray:
    """
    Wiener-style spectral subtraction: remove estimated noise from degraded signal.

    Uses a smooth gain function (0 to 1) per frequency bin instead of raw
    power subtraction. This avoids musical noise artifacts while still
    producing a clearly audible difference from the degraded signal.

    Parameters:
        degraded: Degraded audio signal (noise + audio played through speaker)
        noise: Room noise recording (ambient noise only)
        sr: Sample rate
        oversubtraction: Noise estimate multiplier (2.0 = moderate, audible)
        gain_floor_db: Minimum per-bin gain in dB (-15 dB = keeps ~18% of original)

    Returns:
        Cleaned signal with noise reduced
    """
    nperseg = 1024
    hop = nperseg // 4

    # STFT of degraded signal
    f_deg, t_deg, Z_deg = stft(degraded, sr, nperseg=nperseg, noverlap=nperseg - hop)

    # Estimate noise power spectrum from noise recording (average across all frames)
    _, _, Z_noise = stft(noise, sr, nperseg=nperseg, noverlap=nperseg - hop)
    noise_power = np.mean(np.abs(Z_noise) ** 2, axis=1, keepdims=True)

    # Degraded signal power
    deg_power = np.abs(Z_deg) ** 2
    deg_phase = np.angle(Z_deg)

    # Wiener-style gain: G = max(1 - alpha * noise / signal, floor)
    # This smoothly attenuates noise-dominated bins without creating
    # the harsh artifacts of raw power subtraction
    snr = deg_power / (oversubtraction * noise_power + 1e-10)
    gain = np.maximum(1.0 - 1.0 / snr, 10.0 ** (gain_floor_db / 20.0))

    # Smooth the gain across frequency bins (reduces musical noise)
    kernel = np.ones((3, 1)) / 3.0
    from scipy.ndimage import uniform_filter1d
    for col in range(gain.shape[1]):
        gain[:, col] = uniform_filter1d(gain[:, col], size=3)

    # Apply gain to degraded magnitudes + original phase
    clean_mag = np.abs(Z_deg) * gain
    Z_clean = clean_mag * np.exp(1j * deg_phase)

    _, cleaned = istft(Z_clean, sr, nperseg=nperseg, noverlap=nperseg - hop)

    # Trim to original length
    cleaned = cleaned[:len(degraded)]

    # Normalize to prevent clipping
    peak = np.max(np.abs(cleaned))
    if peak > 0.95:
        cleaned = cleaned * (0.95 / peak)

    return cleaned


def compute_peaq_odg(
    degraded_audio: str | Path,
    reference_audio: str | Path = REFERENCE_AUDIO,
    noise_audio: str | Path | None = None,
) -> dict:
    """
    Compute a PEAQ-like ODG score between reference and degraded audio
    using Log-Spectral Distance.

    If noise_audio is provided, spectral subtraction is applied first.

    Returns:
        dict with keys: odg_score, lsd, details, and optionally subtracted_audio_b64
    """
    ref_path = Path(reference_audio).resolve()
    deg_path = Path(degraded_audio).resolve()

    if not ref_path.exists():
        raise PEAQError(f"Reference audio not found: {ref_path}")
    if not deg_path.exists():
        raise PEAQError(f"Degraded audio not found: {deg_path}")

    # Load audio
    ref, fs_ref = _load_wav(ref_path)
    deg, fs_deg = _load_wav(deg_path)

    details = {
        "ref_sample_rate": fs_ref,
        "deg_sample_rate": fs_deg,
        "ref_duration": round(len(ref) / fs_ref, 2),
        "deg_duration": round(len(deg) / fs_deg, 2),
    }

    # Resample degraded to match reference if sample rates differ
    if fs_ref != fs_deg:
        num_samples = int(len(deg) * fs_ref / fs_deg)
        deg = resample(deg, num_samples)
        details["resampled"] = True

    result = {}

    # Spectral subtraction if noise provided
    if noise_audio is not None:
        noise_path = Path(noise_audio).resolve()
        if not noise_path.exists():
            raise PEAQError(f"Noise audio not found: {noise_path}")

        noise, fs_noise = _load_wav(noise_path)

        # Resample noise to match reference sample rate
        if fs_noise != fs_ref:
            num_samples = int(len(noise) * fs_ref / fs_noise)
            noise = resample(noise, num_samples)

        # Perform spectral subtraction
        subtracted = spectral_subtract(deg, noise, fs_ref)
        details["noise_duration"] = round(len(noise) / fs_ref, 2)
        details["spectral_subtraction"] = True

        # Encode subtracted audio as base64 WAV
        subtracted_wav = _write_wav_bytes(subtracted, fs_ref)
        result["subtracted_audio_b64"] = base64.b64encode(subtracted_wav).decode("ascii")

        # Use subtracted audio for scoring
        deg = subtracted

    # Trim to shortest length
    min_len = min(len(ref), len(deg))
    ref = ref[:min_len]
    deg = deg[:min_len]
    details["analysis_duration"] = round(min_len / fs_ref, 2)

    # Short-time Fourier Transform
    nperseg = 2048
    _, _, Z_ref = stft(ref, fs_ref, nperseg=nperseg)
    _, _, Z_deg = stft(deg, fs_ref, nperseg=nperseg)

    # Magnitude spectra
    mag_ref = np.abs(Z_ref)
    mag_deg = np.abs(Z_deg)

    # Log-Spectral Distance
    eps = 1e-10
    lsd = np.mean((np.log10(mag_ref + eps) - np.log10(mag_deg + eps)) ** 2)

    # Map LSD to ODG scale (-4.0 to 0.0)
    odg = -1.5 * np.sqrt(lsd)
    odg = float(np.clip(odg, -4.0, 0.0))

    result.update({
        "odg_score": round(odg, 3),
        "lsd": round(float(lsd), 6),
        "details": details,
    })

    return result
