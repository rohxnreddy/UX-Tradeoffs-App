import subprocess
import json
import re
from pathlib import Path
from tempfile import NamedTemporaryFile
from datetime import datetime
import multiprocessing
from functools import lru_cache
from concurrent.futures import ThreadPoolExecutor
import os

class VMAFError(Exception):
    pass

REFERENCE_VIDEO = Path(__file__).resolve().with_name("reference.mp4")
DEBUG_DIR = Path("debugvideo")


def get_video_metadata(path: Path):
    """Extracts width, height, FPS, and duration in a single ffprobe call."""
    cmd = [
        "ffprobe",
        "-v", "error",
        "-select_streams", "v:0",
        "-show_entries", "stream=width,height,r_frame_rate,avg_frame_rate:format=duration",
        "-of", "json",
        str(path)
    ]
    try:
        out = subprocess.check_output(cmd, stderr=subprocess.PIPE)
        info = json.loads(out)
        stream = info["streams"][0]
        fmt    = info["format"]

        width  = int(stream["width"])
        height = int(stream["height"])
        duration = float(fmt["duration"])

        def parse(s):
            try:
                if not s or s == "0/0": return 0
                n, d = map(int, s.split("/"))
                return n / d if d else 0
            except Exception:
                return 0

        fps = parse(stream.get("avg_frame_rate", "0/0"))
        if fps <= 0 or fps > 240:
            fps = parse(stream.get("r_frame_rate", "0/0"))
        if fps <= 0 or fps > 240:
            fps = 60.0

        return width, height, fps, duration
    except Exception as e:
        raise VMAFError(f"Failed to get video info for {path}: {e}")


@lru_cache(maxsize=1)
def get_reference_metadata():
    """Cached reference video metadata."""
    return get_video_metadata(REFERENCE_VIDEO)


def find_content_start(path: Path, duration: float) -> float:
    """
    Find exact timestamp where video content starts using scene change detection.
    The warmup black screen → first video frame is a large scene change (~1.0).
    Falls back to blackdetect, then 0.0.
    """
    scan_duration = min(10.0, duration)

    cmd = [
        "ffmpeg",
        "-t", str(scan_duration),
        "-i", str(path),
        "-vf", "select=gt(scene\\,0.15),showinfo",
        "-vsync", "vfr",
        "-f", "null", "-"
    ]

    try:
        result  = subprocess.run(cmd, stderr=subprocess.PIPE, text=True)
        matches = re.findall(r"pts_time:([\d.]+)", result.stderr)
        if matches:
            content_start = float(matches[0])
            print(f"[scenedetect] Content starts at {content_start:.4f}s")
            return content_start
    except Exception as e:
        print(f"[scenedetect] Warning: {e}")

    # Fallback: blackdetect
    cmd2 = [
        "ffmpeg",
        "-t", str(scan_duration),
        "-i", str(path),
        "-vf", "blackdetect=d=0.05:pix_th=0.15",
        "-an", "-f", "null", "-"
    ]
    try:
        result2  = subprocess.run(cmd2, stderr=subprocess.PIPE, text=True)
        matches2 = re.findall(r"black_end:([\d.]+)", result2.stderr)
        if matches2:
            content_start = float(matches2[-1])
            print(f"[blackdetect] Content starts at {content_start:.4f}s")
            return content_start
    except Exception as e:
        print(f"[blackdetect] Warning: {e}")

    print(f"[content_start] No transition detected — using 0.0s")
    return 0.0


def detect_crop_parameters(path: Path, duration: float) -> str:
    start_check = min(3.0, duration * 0.1)

    cmd = [
        "ffmpeg",
        "-ss", str(start_check),
        "-i", str(path),
        "-vframes", "30",
        "-vf", "cropdetect=24:2:0",
        "-f", "null",
        "-"
    ]

    try:
        result = subprocess.run(cmd, stderr=subprocess.PIPE, text=True)
        matches = re.findall(r"crop=(\d+:\d+:\d+:\d+)", result.stderr)
        if matches:
            return f"crop={matches[-1]}"
    except Exception:
        pass

    return "null"


def save_debug_video(input_path: Path, start_time: float, crop_filter: str) -> None:
    suffix = input_path.suffix or ".mp4"
    timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S-%f")
    output_path = DEBUG_DIR / f"{timestamp}{suffix}"

    vf_chain = crop_filter if crop_filter != "null" else "null"

    cmd = [
        "ffmpeg",
        "-y",
        "-ss", str(start_time),
        "-i", str(input_path),
        "-t", "20",
        "-vf", vf_chain,
        "-c:v", "mpeg4",
        "-q:v", "2",
        "-c:a", "copy",
        "-movflags", "+faststart",
        str(output_path),
    ]

    try:
        subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
        print(f"Debug video saved{' (cropped)' if crop_filter != 'null' else ''}: {output_path}")
    except subprocess.CalledProcessError as e:
        stderr_text = e.stderr.decode() if e.stderr else str(e)
        print(f"Warning: Could not save debug video. Error: {stderr_text}")


def compute_vmaf(
    distorted_video: str | Path,
    reference_video: str | Path = REFERENCE_VIDEO,
) -> float:
    dist_path = Path(distorted_video).resolve()
    ref_path  = Path(reference_video).resolve()

    if not ref_path.exists():
        raise VMAFError(f"Reference video not found: {ref_path}")
    if not dist_path.exists():
        raise VMAFError(f"Distorted video not found: {dist_path}")

    # Use cached reference info
    if ref_path == REFERENCE_VIDEO.resolve():
        ref_width, ref_height, ref_fps, _ = get_reference_metadata()
    else:
        ref_width, ref_height, ref_fps, _ = get_video_metadata(ref_path)

    dist_width, dist_height, dist_fps, dist_duration = get_video_metadata(dist_path)

    seek_duration = 20

    # Parallelize pre-processing (scenedetect and cropdetect)
    with ThreadPoolExecutor(max_workers=2) as executor:
        f_start = executor.submit(find_content_start, dist_path, dist_duration)
        f_crop  = executor.submit(detect_crop_parameters, dist_path, dist_duration)

        dist_start = f_start.result()
        crop_filter = f_crop.result()

    ref_start  = 0.0

    print(f"Detected Crop: {crop_filter}")
    print(f"ref  [{ref_start:.4f}s → {ref_start + seek_duration:.4f}s]")
    print(f"dist [{dist_start:.4f}s → {dist_start + seek_duration:.4f}s]")

    with NamedTemporaryFile(suffix=".json", delete=False) as tmp:
        output_json = Path(tmp.name)

    # libvmaf multi-threading
    n_threads = os.cpu_count() or 4

    dist_chain = f"[1:v]trim=start={dist_start}:duration={seek_duration},setpts=PTS-STARTPTS"
    if crop_filter != "null":
        dist_chain += f",{crop_filter}"
    dist_chain += f",scale={ref_width}:{ref_height},fps={ref_fps}[dist];"

    cores = multiprocessing.cpu_count()
    vmaf_filter = (
        f"[0:v]trim=start={ref_start}:duration={seek_duration},"
        f"setpts=PTS-STARTPTS,"
        f"scale={ref_width}:{ref_height},"
        f"fps={ref_fps}[ref];"

        f"{dist_chain}"

        f"[ref][dist]libvmaf="
        f"log_fmt=json:"
        f"log_path={output_json}:"
        f"n_threads={cores}:"
        f"n_subsample=5"
    )

    cmd = [
        "ffmpeg",
        "-y",
        "-threads", str(n_threads),
        "-i", str(ref_path),
        "-i", str(dist_path),
        "-lavfi", vmaf_filter,
        "-f", "null",
        "-"
    ]

    try:
        subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=True,
        )
    except subprocess.CalledProcessError as e:
        raise VMAFError(f"FFmpeg VMAF failed.\nStderr:\n{e.stderr}") from e

    if not output_json.exists():
        raise VMAFError("VMAF JSON output was not created")

    try:
        with output_json.open() as f:
            data = json.load(f)
        score = float(data["pooled_metrics"]["vmaf"]["mean"])
    except (KeyError, json.JSONDecodeError) as e:
        raise VMAFError(f"Invalid VMAF JSON output: {e}")
    finally:
        output_json.unlink(missing_ok=True)

    return score