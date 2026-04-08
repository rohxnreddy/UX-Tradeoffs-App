"""
WebRTC & VoLTE Codec Call Simulator

Uses ACTUAL codecs (Opus, G.711 μ-law, AMR-WB when available) via ffmpeg to
encode and decode audio, producing the exact same degradation that occurs
during a real WebRTC/VoIP/VoLTE call.

Codec pipeline:
  Wideband (VoIP):   PCM → Opus encode (48 kHz) → Opus decode → PCM 16 kHz
  Narrowband (PSTN): PCM → G.711 μ-law encode (8 kHz) → decode → PCM 16 kHz
  VoLTE (AMR-WB):    PCM → AMR-WB encode → AMR-WB decode → PCM 16 kHz
"""

import subprocess
import tempfile
import wave
import io
import base64
import numpy as np
from pathlib import Path
from scipy.signal import resample

from src.audio_sync import trim_playback_capture
from src.audio_diagnostics import summarize_capture_diagnostics

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


def _run_ffmpeg(cmd: list[str], *, timeout: int = 30) -> None:
    result = subprocess.run(cmd, capture_output=True, timeout=timeout)
    if result.returncode != 0:
        stderr = result.stderr.decode(errors="replace").strip()
        raise RuntimeError(stderr or "ffmpeg command failed")


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


def align_audio(ref: np.ndarray, deg: np.ndarray) -> np.ndarray:
    """Align degraded audio to the reference using cross-correlation."""
    try:
        from scipy.signal import fftconvolve
    except ImportError:
        return deg

    chunk_len = min(len(ref), int(len(ref) * 0.5), 16000 * 3)
    if chunk_len < 100:
        return deg

    ref_chunk = ref[:chunk_len]
    corr = fftconvolve(deg, ref_chunk[::-1], mode="full")
    delay_samples = int(np.argmax(corr)) - len(ref_chunk) + 1

    if delay_samples > 0:
        return deg[delay_samples:]
    if delay_samples < 0:
        return np.pad(deg, (-delay_samples, 0))
    return deg


def _score_wideband_pesq(
    ref_16k: np.ndarray,
    deg_16k: np.ndarray,
    *,
    align: bool = True,
) -> tuple[float, np.ndarray]:
    """Score a 16 kHz signal in wideband mode and return the aligned signal."""
    prepared = align_audio(ref_16k, deg_16k) if align else deg_16k
    min_len = min(len(ref_16k), len(prepared))
    ref_trimmed = _float_to_int16(ref_16k[:min_len])
    deg_trimmed = _float_to_int16(prepared[:min_len])
    return float(pesq_score(16000, ref_trimmed, deg_trimmed, "wb")), prepared


def _score_narrowband_pesq(
    ref_16k: np.ndarray,
    deg_16k: np.ndarray,
    *,
    align: bool = True,
) -> tuple[float, np.ndarray]:
    """Score a 16 kHz signal in narrowband mode by downsampling to 8 kHz."""
    prepared = align_audio(ref_16k, deg_16k) if align else deg_16k
    min_len = min(len(ref_16k), len(prepared))
    ref_trimmed = ref_16k[:min_len]
    deg_trimmed = prepared[:min_len]
    nb_len = max(1, int(min_len * 8000 / 16000))
    ref_8k = resample(ref_trimmed, nb_len)
    deg_8k = resample(deg_trimmed, nb_len)
    ref_nb = _float_to_int16(ref_8k)
    deg_nb = _float_to_int16(deg_8k)
    return float(pesq_score(8000, ref_nb, deg_nb, "nb")), prepared


def _validate_recording_duration(
    recorded: np.ndarray,
    reference: np.ndarray,
    sr: int,
    *,
    minimum_fraction: float = 0.8,
) -> None:
    """Reject recordings that are far shorter than the reference sample."""
    recorded_duration = len(recorded) / sr
    reference_duration = len(reference) / sr
    if recorded_duration < reference_duration * minimum_fraction:
        raise RuntimeError(
            "Recorded clip is too short "
            f"({recorded_duration:.2f}s vs expected {reference_duration:.2f}s). "
            "Playback likely interrupted the recording."
        )


def _raise_for_branch_errors(result: dict, expected: dict[str, str]) -> None:
    """Fail the overall analysis if any required branch failed or is missing."""
    errors: list[str] = []
    for key, label in expected.items():
        branch = result.get(key)
        if not isinstance(branch, dict):
            errors.append(f"{label}: missing result")
            continue
        if branch.get("error"):
            errors.append(f"{label}: {branch['error']}")
            continue
        if branch.get("pesq_score") is None:
            errors.append(f"{label}: missing pesq_score")

    if errors:
        raise RuntimeError("Incomplete codec analysis: " + "; ".join(errors))


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
    # Try with -application voip first (VoIP mode, optimized for speech).
    # Some FFmpeg builds don't expose this libopus private option, so fall
    # back to the default application mode ("audio") if it fails.
    base_cmd = [
        "ffmpeg", "-y", "-i", str(input_wav),
        "-c:a", "libopus",
        "-b:a", str(bitrate),
        "-ar", "48000",         # Opus operates at 48 kHz internally
        "-ac", "1",
    ]
    try:
        _run_ffmpeg(base_cmd + ["-application", "voip", opus_file.name])
    except RuntimeError as exc:
        if "application" in str(exc).lower():
            _run_ffmpeg(base_cmd + [opus_file.name])
        else:
            raise

    # Decode back to PCM WAV at 16 kHz (standard wideband output)
    _run_ffmpeg([
        "ffmpeg", "-y", "-i", opus_file.name,
        "-c:a", "pcm_s16le",
        "-ar", "16000",
        "-ac", "1",
        output_wav.name,
    ])

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
    _run_ffmpeg([
        "ffmpeg", "-y", "-i", str(input_wav),
        "-c:a", "pcm_mulaw",
        "-ar", "8000",
        "-ac", "1",
        mulaw_file.name,
    ])

    # Decode back to PCM WAV at 16 kHz for PESQ comparison
    _run_ffmpeg([
        "ffmpeg", "-y", "-i", mulaw_file.name,
        "-c:a", "pcm_s16le",
        "-ar", "16000",
        "-ac", "1",
        output_wav.name,
    ])

    # Clean up intermediate
    Path(mulaw_file.name).unlink(missing_ok=True)

    return Path(output_wav.name)


def _simulate_amrwb_like(input_wav: Path) -> Path:
    """
    Fallback approximation for AMR-WB / VoLTE when a real AMR-WB codec
    round trip is unavailable in ffmpeg.
    """
    output_wav = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
    output_wav.close()

    _run_ffmpeg([
        "ffmpeg", "-y", "-i", str(input_wav),
        "-ar", "16000",
        "-ac", "1",
        "-af", "highpass=f=50,lowpass=f=7000",
        "-c:a", "pcm_s16le",
        output_wav.name,
    ])

    return Path(output_wav.name)


def encode_decode_amrwb(input_wav: Path) -> tuple[Path, dict[str, str]]:
    """
    Encode WAV → AMR-WB in 3GP → decode back to WAV.

    Falls back to a band-limited AMR-WB-like approximation if the local
    ffmpeg build cannot perform the real codec round trip.
    """
    amr_file = tempfile.NamedTemporaryFile(suffix=".3gp", delete=False)
    output_wav = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
    amr_file.close()
    output_wav.close()

    try:
        _run_ffmpeg([
            "ffmpeg", "-y", "-i", str(input_wav),
            "-ar", "16000",
            "-ac", "1",
            "-c:a", "libvo_amrwbenc",
            "-b:a", "23850",
            amr_file.name,
        ])
        _run_ffmpeg([
            "ffmpeg", "-y", "-i", amr_file.name,
            "-c:a", "pcm_s16le",
            "-ar", "16000",
            "-ac", "1",
            output_wav.name,
        ])
        return Path(output_wav.name), {
            "codec": "AMR-WB (VoLTE)",
            "bitrate": "23.85 kbps",
            "implementation": "real_amr_wb",
            "description": "VoLTE call — real AMR-WB codec round trip in 3GP container",
        }
    except Exception as exc:
        Path(output_wav.name).unlink(missing_ok=True)
        fallback_path = _simulate_amrwb_like(input_wav)
        return fallback_path, {
            "codec": "AMR-WB-like simulation",
            "bitrate": "N/A",
            "implementation": "amr_wb_fallback_simulation",
            "description": "VoLTE-like call — AMR-WB unavailable, using 50-7000 Hz simulation",
            "fallback_reason": str(exc),
        }
    finally:
        Path(amr_file.name).unlink(missing_ok=True)


def make_webrtc_call(
    reference_audio: str | Path = REFERENCE_AUDIO,
) -> dict:
    """
    Simulate calls by encoding/decoding the reference audio
    through actual Opus (wideband), G.711 μ-law (narrowband),
    and AMR-WB (VoLTE) codecs.

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

    result = {
        "type": "webrtc_codec_call",
        "description": "Audio processed through Opus, G.711, and AMR-WB (VoLTE) codecs",
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

        wb_pesq, wb_aligned = _score_wideband_pesq(ref_16k, wb_samples)

        result["voip_wideband"] = {
            "pesq_score": round(float(wb_pesq), 3),
            "codec": "Opus (libopus)",
            "sample_rate": 48000,
            "bitrate": "32 kbps",
            "mode": "VoIP",
            "description": "WebRTC wideband call — Opus codec, 48 kHz, VoIP optimized",
        }
        result["wb_degraded_audio_b64"] = _write_wav_b64(wb_aligned, 16000)

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

        nb_pesq, nb_aligned = _score_narrowband_pesq(ref_16k, nb_samples)

        result["traditional_narrowband"] = {
            "pesq_score": round(float(nb_pesq), 3),
            "codec": "G.711 μ-law (PCMU)",
            "sample_rate": 8000,
            "bitrate": "64 kbps",
            "mode": "PSTN",
            "description": "Traditional phone call — G.711 μ-law, 8 kHz narrowband",
        }
        result["nb_degraded_audio_b64"] = _write_wav_b64(nb_aligned, 16000)

        nb_path.unlink(missing_ok=True)
    except Exception as e:
        result["traditional_narrowband"] = {"error": str(e)}

    # === VoLTE call: AMR-WB codec round trip ===
    try:
        volte_path, volte_meta = encode_decode_amrwb(ref_path)
        volte_samples, volte_sr = _load_wav(volte_path)

        # Resample to 16 kHz if needed
        if volte_sr != 16000:
            num = int(len(volte_samples) * 16000 / volte_sr)
            volte_samples = resample(volte_samples, num)

        volte_pesq, volte_aligned = _score_wideband_pesq(ref_16k, volte_samples)

        result["volte_wideband"] = {
            "pesq_score": round(float(volte_pesq), 3),
            "codec": volte_meta["codec"],
            "sample_rate": 16000,
            "bitrate": volte_meta["bitrate"],
            "mode": "VoLTE",
            "description": volte_meta["description"],
            "implementation": volte_meta["implementation"],
        }
        if "fallback_reason" in volte_meta:
            result["volte_wideband"]["fallback_reason"] = volte_meta["fallback_reason"]
        result["volte_degraded_audio_b64"] = _write_wav_b64(volte_aligned, 16000)

        volte_path.unlink(missing_ok=True)
    except Exception as e:
        result["volte_wideband"] = {"error": str(e)}

    _raise_for_branch_errors(
        result,
        {
            "voip_wideband": "VoIP",
            "traditional_narrowband": "PSTN",
            "volte_wideband": "VoLTE",
        },
    )

    return result


def make_device_webrtc_call(
    recorded_audio: str | Path,
    reference_audio: str | Path = REFERENCE_AUDIO,
) -> dict:
    """
    Process a phone's mic recording through actual WebRTC and VoLTE codecs.

    Flow:
      Phone: Reference → Speaker → Air → Mic → recorded_audio
      Backend: recorded_audio → Opus encode/decode → PESQ vs original reference
               recorded_audio → G.711 encode/decode → PESQ vs original reference
               recorded_audio → AMR-WB (VoLTE) → PESQ vs original reference

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

    # Load the phone recording at 16 kHz
    rec_samples, rec_sr = _load_wav(rec_path)
    if rec_sr != 16000:
        num = int(len(rec_samples) * 16000 / rec_sr)
        rec_16k = resample(rec_samples, num)
    else:
        rec_16k = rec_samples
    rec_16k, sync_details = trim_playback_capture(
        rec_16k,
        16000,
        len(ref_16k),
        profile="pesq",
    )
    _validate_recording_duration(rec_16k, ref_16k, 16000)
    diagnostics = summarize_capture_diagnostics(
        rec_16k,
        16000,
        expected_samples=len(ref_16k),
        sync_details=sync_details,
        content_kind="speech",
    )
    aligned_rec_16k = align_audio(ref_16k, rec_16k)

    # Also save the phone recording at 16 kHz as a temp WAV for ffmpeg
    rec_16k_path = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
    rec_16k_path.close()
    rec_16k_int16 = _float_to_int16(aligned_rec_16k)
    with wave.open(rec_16k_path.name, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(16000)
        w.writeframes(rec_16k_int16.tobytes())

    result = {
        "type": "webrtc_device_call",
        "description": "Phone recording processed through Opus, G.711, and AMR-WB (VoLTE) codecs",
        "reference_audio_b64": _write_wav_b64(ref_16k, 16000),
        "recorded_audio_b64": _write_wav_b64(aligned_rec_16k, 16000),
        "sync_marker": sync_details,
        "diagnostics": diagnostics,
    }

    # Trim reference and recording to same length
    min_base = min(len(ref_16k), len(aligned_rec_16k))

    # ── Direct recording score (no codec, just hardware degradation) ──
    try:
        rec_trimmed = _float_to_int16(aligned_rec_16k[:min_base])
        ref_trimmed = _float_to_int16(ref_16k[:min_base])
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

        wb_pesq, wb_aligned = _score_wideband_pesq(ref_16k, wb_samples)

        result["voip_wideband"] = {
            "pesq_score": round(float(wb_pesq), 3),
            "codec": "Opus (libopus)",
            "sample_rate": 48000,
            "bitrate": "32 kbps",
            "mode": "VoIP",
            "description": "Phone recording → Opus codec → PESQ vs original",
        }
        result["wb_degraded_audio_b64"] = _write_wav_b64(wb_aligned, 16000)
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

        nb_pesq, nb_aligned = _score_narrowband_pesq(ref_16k, nb_samples)

        result["traditional_narrowband"] = {
            "pesq_score": round(float(nb_pesq), 3),
            "codec": "G.711 μ-law (PCMU)",
            "sample_rate": 8000,
            "bitrate": "64 kbps",
            "mode": "PSTN",
            "description": "Phone recording → G.711 codec → PESQ vs original",
        }
        result["nb_degraded_audio_b64"] = _write_wav_b64(nb_aligned, 16000)
        nb_path.unlink(missing_ok=True)
    except Exception as e:
        result["traditional_narrowband"] = {"error": str(e)}

    # ── VoLTE: recording → AMR-WB codec round trip → PESQ vs reference ──
    try:
        volte_path, volte_meta = encode_decode_amrwb(Path(rec_16k_path.name))
        volte_samples, volte_sr = _load_wav(volte_path)
        if volte_sr != 16000:
            num = int(len(volte_samples) * 16000 / volte_sr)
            volte_samples = resample(volte_samples, num)

        volte_pesq, volte_aligned = _score_wideband_pesq(ref_16k, volte_samples)

        result["volte_wideband"] = {
            "pesq_score": round(float(volte_pesq), 3),
            "codec": volte_meta["codec"],
            "sample_rate": 16000,
            "bitrate": volte_meta["bitrate"],
            "mode": "VoLTE",
            "description": "Phone recording → " + volte_meta["description"] + " → PESQ vs original",
            "implementation": volte_meta["implementation"],
        }
        if "fallback_reason" in volte_meta:
            result["volte_wideband"]["fallback_reason"] = volte_meta["fallback_reason"]
        result["volte_degraded_audio_b64"] = _write_wav_b64(volte_aligned, 16000)
        volte_path.unlink(missing_ok=True)
    except Exception as e:
        result["volte_wideband"] = {"error": str(e)}

    _raise_for_branch_errors(
        result,
        {
            "direct_recording": "Device hardware",
            "voip_wideband": "VoIP",
            "traditional_narrowband": "PSTN",
            "volte_wideband": "VoLTE",
        },
    )

    # Clean up
    Path(rec_16k_path.name).unlink(missing_ok=True)

    return result
