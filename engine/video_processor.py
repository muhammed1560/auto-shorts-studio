import os
import sys
import subprocess
import tempfile
import re
import platform
import concurrent.futures


def get_video_encoder() -> str:
    """Detects available hardware-accelerated video encoder, falls back to libx264."""
    if platform.system() == "Darwin":
        return "h264_videotoolbox"
    return "libx264"


def detect_silence(video_path: str, noise_db: int = -35, min_duration: float = 0.5) -> list[tuple[float, float]]:
    """Detects start and end timestamps of silent audio segments in the video using FFmpeg silencedetect."""
    command = [
        "ffmpeg",
        "-i", video_path,
        "-af", f"silencedetect=noise={noise_db}dB:d={min_duration}",
        "-f", "null",
        "-"
    ]

    result = subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)

    silence_intervals = []
    current_silence_start = None

    for line in result.stderr.splitlines():
        if "silence_start" in line:
            match = re.search(r"silence_start: ([\d\.]+)", line)
            if match:
                current_silence_start = float(match.group(1))
        elif "silence_end" in line:
            match = re.search(r"silence_end: ([\d\.]+)", line)
            if match and current_silence_start is not None:
                silence_end = float(match.group(1))
                silence_intervals.append((current_silence_start, silence_end))
                current_silence_start = None

    return silence_intervals


def create_jumpcut_clip(input_path: str, output_path: str):
    """Removes silent parts within a clip using a single-pass FFmpeg filter complex."""
    silence_intervals = detect_silence(input_path)

    if not silence_intervals:
        subprocess.run(["cp", input_path, output_path], check=True)
        return

    keep_segments = []
    current_time = 0.0

    for silence_start, silence_end in silence_intervals:
        if silence_start > current_time + 0.2:  # Keep active segments longer than 200ms
            keep_segments.append((current_time, silence_start))
        current_time = silence_end

    keep_segments.append((current_time, 20.0))

    if not keep_segments:
        subprocess.run(["cp", input_path, output_path], check=True)
        return

    filter_complex = []
    concat_inputs = ""

    for index, (start, end) in enumerate(keep_segments):
        filter_complex.append(f"[0:v]trim=start={start}:end={end},setpts=PTS-STARTPTS[v{index}]")
        filter_complex.append(f"[0:a]atrim=start={start}:end={end},asetpts=PTS-STARTPTS[a{index}]")
        concat_inputs += f"[v{index}][a{index}]"

    filter_complex.append(f"{concat_inputs}concat=n={len(keep_segments)}:v=1:a=1[outv][outa]")

    encoder = get_video_encoder()
    command = [
        "ffmpeg", "-threads", "2", "-i", input_path,
        "-filter_complex", ";".join(filter_complex),
        "-map", "[outv]", "-map", "[outa]",
        "-c:v", encoder, "-b:v", "5M", "-c:a", "aac",
        "-y", output_path
    ]
    subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    if not os.path.exists(output_path):
        subprocess.run(["cp", input_path, output_path], check=True)


def process_short(video_path: str, peaks: list[float], output_path: str, fit_mode: str = 'crop', target_duration: int = 60) -> float:
    """Takes 15s clips around peaks, applies jump-cuts, merges, and formats into 9:16 vertical video."""
    with tempfile.TemporaryDirectory() as temp_dir:
        subclip_files = [None] * len(peaks)

        def process_peak(index: int, peak_timestamp: float):
            start_time = max(0, peak_timestamp - 10)
            clip_duration = 15

            raw_clip_path = os.path.join(temp_dir, f"raw_{index}.mp4")
            extract_command = [
                "ffmpeg", "-threads", "1", "-ss", str(start_time), "-i", video_path,
                "-t", str(clip_duration),
                "-c:v", "copy", "-c:a", "copy",
                "-y", raw_clip_path
            ]
            subprocess.run(extract_command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

            if os.path.exists(raw_clip_path):
                jumpcut_clip_path = os.path.join(temp_dir, f"jc_{index}.mp4")
                create_jumpcut_clip(raw_clip_path, jumpcut_clip_path)
                if os.path.exists(jumpcut_clip_path) and os.path.getsize(jumpcut_clip_path) > 1024:
                    subclip_files[index] = jumpcut_clip_path

        # Concurrently process peaks with 2 workers to keep system responsive
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
            futures = [executor.submit(process_peak, index, peak) for index, peak in enumerate(peaks)]
            concurrent.futures.wait(futures)

        valid_subclips = [clip for clip in subclip_files if clip is not None]

        if not valid_subclips:
            raise RuntimeError("No valid candidate subclips could be generated.")

        concat_manifest_path = os.path.join(temp_dir, "concat_shorts.txt")
        with open(concat_manifest_path, "w") as manifest_file:
            for clip_path in valid_subclips:
                manifest_file.write(f"file '{clip_path}'\n")

        joined_clip_path = os.path.join(temp_dir, "joined.mp4")
        concat_command = [
            "ffmpeg", "-f", "concat", "-safe", "0",
            "-i", concat_manifest_path,
            "-c", "copy", "-y",
            joined_clip_path
        ]
        subprocess.run(concat_command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)

        encoder = get_video_encoder()

        # 9:16 (1080x1920) vertical formatting
        if fit_mode == 'blur':
            video_filter = "[0:v]scale=1080:1920:force_original_aspect_ratio=increase,boxblur=40:20,crop=1080:1920[bg];[0:v]scale=1080:1920:force_original_aspect_ratio=decrease[fg];[bg][fg]overlay=(W-w)/2:(H-h)/2"
            final_command = [
                "ffmpeg", "-threads", "2", "-i", joined_clip_path,
                "-filter_complex", video_filter,
                "-t", str(target_duration),
                "-c:v", encoder, "-b:v", "8M",
                "-c:a", "aac", "-b:a", "192k",
                "-y", output_path
            ]
        else:
            final_command = [
                "ffmpeg", "-threads", "2", "-i", joined_clip_path,
                "-vf", "crop=ih*9/16:ih,scale=1080:1920",
                "-t", str(target_duration),
                "-c:v", encoder, "-b:v", "8M",
                "-c:a", "aac", "-b:a", "192k",
                "-y", output_path
            ]

        print("PROGRESS:Final render (9:16 vertical) in progress...")
        process = subprocess.Popen(final_command, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, universal_newlines=True)
        time_regex = re.compile(r"time=(\d{2}):(\d{2}):(\d{2}\.\d{2})")
        final_rendered_seconds = 0.0

        for line in process.stderr:
            match = time_regex.search(line)
            if match:
                h = int(match.group(1))
                m = int(match.group(2))
                s = float(match.group(3))
                final_rendered_seconds = h * 3600 + m * 60 + s
                percent = min(100, int((final_rendered_seconds / target_duration) * 100))
                print(f"PROGRESS:%{percent} Render: {int(final_rendered_seconds)}/{target_duration}s completed...")

        process.wait()
        return final_rendered_seconds
