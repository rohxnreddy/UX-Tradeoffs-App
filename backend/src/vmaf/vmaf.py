import subprocess
import json
import re
from pathlib import Path
from tempfile import NamedTemporaryFile
from datetime import datetime

class VMAFError(Exception):
    pass

REFERENCE_VIDEO = Path(__file__).resolve().with_name("reference.mp4")
DEBUG_DIR = Path("debugvideo")


def get_video_info(path: Path):
    """Extracts width, height, and FPS."""
    cmd = [
        "ffprobe",
        "-v", "error",
        "-select_streams", "v:0",
        "-show_entries", "stream=width,height,r_frame_rate",
        "-of", "json",
        str(path)
    ]
    try:
        out = subprocess.check_output(cmd, stderr=subprocess.PIPE)
        info = json.loads(out)
        stream = info["streams"][0]

        width = int(stream["width"])
        height = int(stream["height"])
        num, den = map(int, stream["r_frame_rate"].split("/"))
        fps = num / den
        return width, height, fps
    except Exception as e:
        raise VMAFError(f"Failed to get video info for {path}: {e}")


def get_video_duration(path: Path) -> float:
    cmd = [
        "ffprobe",
        "-v", "error",
        "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1",
        str(path)
    ]
    try:
        out = subprocess.check_output(cmd, stderr=subprocess.PIPE)
        return float(out.strip())
    except Exception as e:
        raise VMAFError(f"Failed to get duration for {path}: {e}")


def detect_crop_parameters(path: Path, duration: float) -> str:
    start_check = max(0, duration / 2)
    
    cmd = [
        "ffmpeg",
        "-ss", str(start_check),
        "-i", str(path),
        "-vframes", "10",  
        "-vf", "cropdetect=24:16:0",
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

    if crop_filter != "null":
        vf_chain = crop_filter
    else:
        vf_chain = "null" 

    cmd = [
        "ffmpeg",
        "-y",
        "-ss", str(start_time),      
        "-i", str(input_path),
        "-t", "30",                   
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
    ref_path = Path(reference_video).resolve()

    if not ref_path.exists():
        raise VMAFError(f"Reference video not found: {ref_path}")
    if not dist_path.exists():
        raise VMAFError(f"Distorted video not found: {dist_path}")


    ref_width, ref_height, ref_fps = get_video_info(ref_path)
    dist_duration = get_video_duration(dist_path)
    ref_duration = get_video_duration(ref_path)

    seek_duration = 30
    dist_start = max(0, dist_duration - seek_duration)
    ref_start = max(0, ref_duration - seek_duration)


    crop_filter = detect_crop_parameters(dist_path, dist_duration)
    print(f"Detected Crop: {crop_filter}")


    # save_debug_video(dist_path, dist_start, crop_filter)


    with NamedTemporaryFile(suffix=".json", delete=False) as tmp:
        output_json = Path(tmp.name)

    
    dist_chain = f"[1:v]trim=start={dist_start}:duration={seek_duration},setpts=PTS-STARTPTS"
    if crop_filter != "null":
        dist_chain += f",{crop_filter}"
    

    dist_chain += f",scale={ref_width}:{ref_height},fps={ref_fps}[dist];"

    vmaf_filter = (
        f"[0:v]trim=start={ref_start}:duration={seek_duration},"
        f"setpts=PTS-STARTPTS,"
        f"scale={ref_width}:{ref_height},"
        f"fps={ref_fps}[ref];"
        
        f"{dist_chain}"
        
        f"[ref][dist]libvmaf="
        f"log_fmt=json:"
        f"log_path={output_json}"
    )

    cmd = [
        "ffmpeg",
        "-y",
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