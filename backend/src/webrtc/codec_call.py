"""
WebRTC Codec Call Simulator

Uses the ACTUAL WebRTC codecs (Opus, G.711 μ-law) via ffmpeg to encode
and decode audio, producing the exact same degradation that occurs
during a real WebRTC/VoIP call.

This is NOT a rough simulation — it uses the same libopus and G.711
implementations that WebRTC uses in production.

Codec pipeline:
  Wideband (VoIP):   PCM → Opus encode (48 kHz) → Opus decode → PCM 16 kHz
  Narrowband (PSTN): PCM → G.711 μ-law encode (8 kHz) → decode → PCM 16 kHz
"""

import subprocess
import tempfile
import wave
import io
import base64
import numpy as np
from pathlib import Path
from scipy.signal import resample

try:
    from pesq import pesq as pesq_score
except ImportError:
    pesq_score = None


REFERENCE_AUDIO = Path(__file__).resolve().parent.parent.parent / "peaq-pesq-audio" / "pesq.wav"


def _check_ffmpeg():
    """Verify ffmpeg is available."""
    try:
        result = subprocess.run(
            ["ffmpeg", "-version"],
            capture_output=True, timeout=5,
        )
        return result.returncode == 0
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False


def _load_wav(file_path: Path) -> tuple[np.ndarray, int]:
    """Load WAV file as float64 mono samples."""
    with wave.open(str(file_path), "r") as w:
        sr = w.getframerate()
        ch = w.getnchannels()
        sw = w.getsampwidth()
        raw = w.readframes(w.getnframes())

    if sw == 2:
        samples = np.frombuffer(raw, dtype=np.int16).astype(np.float64) / 32768.0
    elif sw == 4:
        samples = np.frombuffer(raw, dtype=np.int32).astype(np.float64) / 2147483648.0
    else:
        raise ValueError(f"Unsupported sample width: {sw}")

    if ch >= 2:
        samples = samples.reshape(-1, ch).mean(axis=1)

    return samples, sr


def _write_wav_b64(samples: np.ndarray, sr: int) -> str:
    """Convert float64 samples to base64-encoded WAV."""
    int16 = np.clip(samples * 32767, -32768, 32767).astype(np.int16)
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(int16.tobytes())
    return base64.b64encode(buf.getvalue()).decode("ascii")


def _float_to_int16(s: np.ndarray) -> np.ndarray:
    return np.clip(s * 32768.0, -32768, 32767).astype(np.int16)


def encode_decode_opus(input_wav: Path, bitrate: int = 32000) -> Path:
    """
    Encode WAV → Opus → decode back to WAV.
    This is the EXACT codec pipeline of a WebRTC wideband call.
    """
    opus_file = tempfile.NamedTemporaryFile(suffix=".ogg", delete=False)
    output_wav = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
    opus_file.close()
    output_wav.close()

    # Encode to Opus (WebRTC standard wideband codec)
    subprocess.run([
        "ffmpeg", "-y", "-i", str(input_wav),
        "-c:a", "libopus",
        "-b:a", str(bitrate),
        "-ar", "48000",         # Opus operates at 48 kHz internally
        "-ac", "1",
        "-application", "voip", # VoIP mode (optimized for speech)
        opus_file.name,
    ], capture_output=True, timeout=30)

    # Decode back to PCM WAV at 16 kHz (standard wideband output)
    subprocess.run([
        "ffmpeg", "-y", "-i", opus_file.name,
        "-c:a", "pcm_s16le",
        "-ar", "16000",
        "-ac", "1",
        output_wav.name,
    ], capture_output=True, timeout=30)

    # Clean up intermediate
    Path(opus_file.name).unlink(missing_ok=True)

    return Path(output_wav.name)


def encode_decode_g711(input_wav: Path) -> Path:
    """
    Encode WAV → G.711 μ-law (8 kHz) → decode back to WAV.
    This is the EXACT codec pipeline of a traditional PSTN phone call.
    """
    mulaw_file = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
    output_wav = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
    mulaw_file.close()
    output_wav.close()

    # Encode to G.711 μ-law at 8 kHz (PSTN narrowband standard)
    subprocess.run([
        "ffmpeg", "-y", "-i", str(input_wav),
        "-c:a", "pcm_mulaw",
        "-ar", "8000",
        "-ac", "1",
        mulaw_file.name,
    ], capture_output=True, timeout=30)

    # Decode back to PCM WAV at 16 kHz for PESQ comparison
    subprocess.run([
        "ffmpeg", "-y", "-i", mulaw_file.name,
        "-c:a", "pcm_s16le",
        "-ar", "16000",
        "-ac", "1",
        output_wav.name,
    ], capture_output=True, timeout=30)

    # Clean up intermediate
    Path(mulaw_file.name).unlink(missing_ok=True)

    return Path(output_wav.name)


def make_webrtc_call(
    reference_audio: str | Path = REFERENCE_AUDIO,
) -> dict:
    """
    Simulate a WebRTC call by encoding/decoding the reference audio
    through actual Opus (wideband) and G.711 μ-law (narrowband) codecs.

    Returns PESQ scores and the degraded audio as base64 for playback.
    """
    if not _check_ffmpeg():
        raise RuntimeError("ffmpeg not found — required for WebRTC codec processing")

    if pesq_score is None:
        raise RuntimeError("pesq package not installed")

    ref_path = Path(reference_audio).resolve()
    if not ref_path.exists():
        raise FileNotFoundError(f"Reference audio not found: {ref_path}")

    # Load reference for PESQ comparison (at 16 kHz)
    ref_samples, ref_sr = _load_wav(ref_path)
    if ref_sr != 16000:
        num = int(len(ref_samples) * 16000 / ref_sr)
        ref_16k = resample(ref_samples, num)
    else:
        ref_16k = ref_samples
    ref_int16 = _float_to_int16(ref_16k)

    result = {
        "type": "webrtc_codec_call",
        "description": "Audio processed through actual WebRTC codecs (Opus & G.711)",
        "reference_audio_b64": _write_wav_b64(ref_16k, 16000),
    }

    # === Wideband call: Opus codec ===
    try:
        wb_path = encode_decode_opus(ref_path, bitrate=32000)
        wb_samples, wb_sr = _load_wav(wb_path)

        # Resample to 16 kHz if needed
        if wb_sr != 16000:
            num = int(len(wb_samples) * 16000 / wb_sr)
            wb_samples = resample(wb_samples, num)

        # Trim to match
        min_len = min(len(ref_16k), len(wb_samples))
        wb_trimmed = _float_to_int16(wb_samples[:min_len])
        ref_trimmed_wb = ref_int16[:min_len]

        # PESQ
        wb_pesq = pesq_score(16000, ref_trimmed_wb, wb_trimmed, "wb")

        result["voip_wideband"] = {
            "pesq_score": round(float(wb_pesq), 3),
            "codec": "Opus (libopus)",
            "sample_rate": 48000,
            "bitrate": "32 kbps",
            "mode": "VoIP",
            "description": "WebRTC wideband call — Opus codec, 48 kHz, VoIP optimized",
        }
        result["wb_degraded_audio_b64"] = _write_wav_b64(wb_samples, 16000)

        wb_path.unlink(missing_ok=True)
    except Exception as e:
        result["voip_wideband"] = {"error": str(e)}

    # === Narrowband call: G.711 μ-law codec ===
    try:
        nb_path = encode_decode_g711(ref_path)
        nb_samples, nb_sr = _load_wav(nb_path)

        # Resample to 16 kHz if needed
        if nb_sr != 16000:
            num = int(len(nb_samples) * 16000 / nb_sr)
            nb_samples = resample(nb_samples, num)

        # Trim to match
        min_len = min(len(ref_16k), len(nb_samples))
        nb_trimmed = _float_to_int16(nb_samples[:min_len])
        ref_trimmed_nb = ref_int16[:min_len]

        # PESQ
        nb_pesq = pesq_score(16000, ref_trimmed_nb, nb_trimmed, "wb")

        result["traditional_narrowband"] = {
            "pesq_score": round(float(nb_pesq), 3),
            "codec": "G.711 μ-law (PCMU)",
            "sample_rate": 8000,
            "bitrate": "64 kbps",
            "mode": "PSTN",
            "description": "Traditional phone call — G.711 μ-law, 8 kHz narrowband",
        }
        result["nb_degraded_audio_b64"] = _write_wav_b64(nb_samples, 16000)

        nb_path.unlink(missing_ok=True)
    except Exception as e:
        result["traditional_narrowband"] = {"error": str(e)}

    return result


def make_device_webrtc_call(
    recorded_audio: str | Path,
    reference_audio: str | Path = REFERENCE_AUDIO,
) -> dict:
    """
    Process a phone's mic recording through actual WebRTC codecs.

    Flow:
      Phone: Reference → Speaker → Air → Mic → recorded_audio
      Backend: recorded_audio → Opus encode/decode → PESQ vs original reference
               recorded_audio → G.711 encode/decode → PESQ vs original reference

    This produces device-specific results because the recording quality
    varies by phone hardware (speaker, mic, DSP processing).

    Returns PESQ scores and the degraded audio as base64 for playback.
    """
    if not _check_ffmpeg():
        raise RuntimeError("ffmpeg not found — required for WebRTC codec processing")

    if pesq_score is None:
        raise RuntimeError("pesq package not installed")

    ref_path = Path(reference_audio).resolve()
    rec_path = Path(recorded_audio).resolve()

    if not ref_path.exists():
        raise FileNotFoundError(f"Reference audio not found: {ref_path}")
    if not rec_path.exists():
        raise FileNotFoundError(f"Recorded audio not found: {rec_path}")

    # Load reference at 16 kHz for PESQ
    ref_samples, ref_sr = _load_wav(ref_path)
    if ref_sr != 16000:
        num = int(len(ref_samples) * 16000 / ref_sr)
        ref_16k = resample(ref_samples, num)
    else:
        ref_16k = ref_samples
    ref_int16 = _float_to_int16(ref_16k)

    # Load the phone recording at 16 kHz
    rec_samples, rec_sr = _load_wav(rec_path)
    if rec_sr != 16000:
        num = int(len(rec_samples) * 16000 / rec_sr)
        rec_16k = resample(rec_samples, num)
    else:
        rec_16k = rec_samples

    # Also save the phone recording at 16 kHz as a temp WAV for ffmpeg
    rec_16k_path = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
    rec_16k_path.close()
    rec_16k_int16 = _float_to_int16(rec_16k)
    with wave.open(rec_16k_path.name, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(16000)
        w.writeframes(rec_16k_int16.tobytes())

    result = {
        "type": "webrtc_device_call",
        "description": "Phone recording processed through actual WebRTC codecs (Opus & G.711)",
        "reference_audio_b64": _write_wav_b64(ref_16k, 16000),
        "recorded_audio_b64": _write_wav_b64(rec_16k, 16000),
    }

    # Trim reference and recording to same length
    min_base = min(len(ref_16k), len(rec_16k))

    # ── Direct recording score (no codec, just hardware degradation) ──
    try:
        rec_trimmed = _float_to_int16(rec_16k[:min_base])
        ref_trimmed = ref_int16[:min_base]
        direct_pesq = pesq_score(16000, ref_trimmed, rec_trimmed, "wb")
        result["direct_recording"] = {
            "pesq_score": round(float(direct_pesq), 3),
            "description": "Phone speaker → mic only (no codec)",
        }
    except Exception as e:
        result["direct_recording"] = {"error": str(e)}

    # ── Wideband: recording → Opus encode → decode → PESQ vs reference ──
    try:
        wb_path = encode_decode_opus(Path(rec_16k_path.name), bitrate=32000)
        wb_samples, wb_sr = _load_wav(wb_path)
        if wb_sr != 16000:
            num = int(len(wb_samples) * 16000 / wb_sr)
            wb_samples = resample(wb_samples, num)

        min_len = min(min_base, len(wb_samples))
        wb_trimmed = _float_to_int16(wb_samples[:min_len])
        ref_trimmed_wb = ref_int16[:min_len]

        wb_pesq = pesq_score(16000, ref_trimmed_wb, wb_trimmed, "wb")

        result["voip_wideband"] = {
            "pesq_score": round(float(wb_pesq), 3),
            "codec": "Opus (libopus)",
            "sample_rate": 48000,
            "bitrate": "32 kbps",
            "mode": "VoIP",
            "description": "Phone recording → Opus codec → PESQ vs original",
        }
        result["wb_degraded_audio_b64"] = _write_wav_b64(wb_samples, 16000)
        wb_path.unlink(missing_ok=True)
    except Exception as e:
        result["voip_wideband"] = {"error": str(e)}

    # ── Narrowband: recording → G.711 encode → decode → PESQ vs reference ──
    try:
        nb_path = encode_decode_g711(Path(rec_16k_path.name))
        nb_samples, nb_sr = _load_wav(nb_path)
        if nb_sr != 16000:
            num = int(len(nb_samples) * 16000 / nb_sr)
            nb_samples = resample(nb_samples, num)

        min_len = min(min_base, len(nb_samples))
        nb_trimmed = _float_to_int16(nb_samples[:min_len])
        ref_trimmed_nb = ref_int16[:min_len]

        nb_pesq = pesq_score(16000, ref_trimmed_nb, nb_trimmed, "wb")

        result["traditional_narrowband"] = {
            "pesq_score": round(float(nb_pesq), 3),
            "codec": "G.711 μ-law (PCMU)",
            "sample_rate": 8000,
            "bitrate": "64 kbps",
            "mode": "PSTN",
            "description": "Phone recording → G.711 codec → PESQ vs original",
        }
        result["nb_degraded_audio_b64"] = _write_wav_b64(nb_samples, 16000)
        nb_path.unlink(missing_ok=True)
    except Exception as e:
        result["traditional_narrowband"] = {"error": str(e)}

    # Clean up
    Path(rec_16k_path.name).unlink(missing_ok=True)

    return result
