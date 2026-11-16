import os
import subprocess
import tempfile
import numpy as np
from scipy.io import wavfile
import json
import shutil
import uuid
import re
import imageio_ffmpeg


def get_ffmpeg_executable() -> str:
    """Resolves the FFmpeg binary path via imageio_ffmpeg or system PATH."""
    try:
        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        path = shutil.which("ffmpeg")
        if path:
            return path
        return "ffmpeg"


FFMPEG_CMD = get_ffmpeg_executable()


def compute_audio_energy(video_path: str, fps: int = 1) -> np.ndarray:
    """
    Extracts audio from video as a 16kHz mono WAV file and calculates RMS energy scores per second.
    """
    total_duration = 0.0
    duration_proc = subprocess.run([FFMPEG_CMD, "-i", video_path], stderr=subprocess.PIPE, universal_newlines=True)
    duration_match = re.search(r"Duration: (\d{2}):(\d{2}):(\d{2}\.\d{2})", duration_proc.stderr)
    if duration_match:
        hours = int(duration_match.group(1))
        minutes = int(duration_match.group(2))
        seconds = float(duration_match.group(3))
        total_duration = hours * 3600 + minutes * 60 + seconds

    temp_wav = os.path.join(tempfile.gettempdir(), f"temp_audio_{uuid.uuid4().hex}.wav")
    try:
        print("PROGRESS:Extracting audio track for energy analysis (Step 1/3)...")
        command = [
            FFMPEG_CMD, "-i", video_path, "-vn", "-ac", "1", "-ar", "16000", "-y", temp_wav
        ]
        process = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, universal_newlines=True)
        time_regex = re.compile(r"time=(\d{2}):(\d{2}):(\d{2}\.\d{2})")
        for line in process.stderr:
            match = time_regex.search(line)
            if match and total_duration > 0:
                h = int(match.group(1))
                m = int(match.group(2))
                s = float(match.group(3))
                rendered_sec = h * 3600 + m * 60 + s
                percent = min(100, int((rendered_sec / total_duration) * 100))
                print(f"PROGRESS:%{percent} Audio Demux: {int(rendered_sec)}/{int(total_duration)}s completed...")
        process.wait()

        print("PROGRESS:Calculating audio waveform RMS energy...")
        sample_rate, audio_data = wavfile.read(temp_wav)
        if len(audio_data.shape) > 1:
            audio_data = audio_data.mean(axis=1)

        samples_per_frame = sample_rate // fps
        num_frames = len(audio_data) // samples_per_frame

        energy_scores = []
        for i in range(num_frames):
            frame_data = audio_data[i * samples_per_frame : (i + 1) * samples_per_frame]
            # Root Mean Square (RMS) energy calculation
            rms_energy = np.sqrt(np.mean(frame_data.astype(np.float64)**2))
            energy_scores.append(rms_energy)

        return np.array(energy_scores)
    finally:
        if os.path.exists(temp_wav):
            os.remove(temp_wav)


def compute_visual_motion(video_path: str, fps: int = 1, total_duration_sec: int = 0) -> np.ndarray:
    """
    Extracts downscaled grayscale frames (160x90) at 1 fps to calculate per-second pixel variance motion scores.
    """
    print("PROGRESS:Starting visual motion analysis (optical frame differencing)...")
    width, height = 160, 90
    frame_size = width * height
    command = [
        FFMPEG_CMD, "-threads", "2", "-i", video_path,
        "-vf", f"fps={fps},scale={width}:{height},format=gray",
        "-f", "rawvideo", "-pix_fmt", "gray", "-"
    ]

    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)

    motion_scores = []
    previous_frame = None
    frame_count = 0

    while True:
        raw_frame = process.stdout.read(frame_size)
        if len(raw_frame) != frame_size:
            break

        current_frame = np.frombuffer(raw_frame, dtype=np.uint8)

        if previous_frame is not None:
            # Mean absolute pixel difference between adjacent frames
            pixel_diff = np.mean(np.abs(current_frame.astype(np.int16) - previous_frame.astype(np.int16)))
            motion_scores.append(pixel_diff)
        else:
            motion_scores.append(0.0)

        previous_frame = current_frame
        frame_count += 1

        if frame_count % 5 == 0:
            if total_duration_sec > 0:
                percent = min(100, int((frame_count / total_duration_sec) * 100))
                print(f"PROGRESS:%{percent} Visual Analysis: {frame_count}/{total_duration_sec}s processed...")
            else:
                print(f"PROGRESS:Visual Analysis: {frame_count}s processed...")

    process.stdout.close()
    process.wait()

    return np.array(motion_scores)


def analyze_long_video(video_path: str) -> str:
    """
    Performs dual-factor analysis (audio energy + visual motion) to identify dull or silent scenes,
    generates jump-cut trim segments, and outputs structured JSON metadata.
    """
    sampling_fps = 1

    audio_energy = compute_audio_energy(video_path, sampling_fps)
    visual_motion = compute_visual_motion(video_path, sampling_fps, len(audio_energy))

    # Synchronize timeline lengths
    min_length = min(len(audio_energy), len(visual_motion))
    audio_energy = audio_energy[:min_length]
    visual_motion = visual_motion[:min_length]

    # Min-max normalization
    normalized_audio = audio_energy / (audio_energy.max() + 1e-6)
    normalized_motion = visual_motion / (visual_motion.max() + 1e-6)

    print("PROGRESS:Detecting silence and inactivity thresholds...")
    audio_threshold = np.mean(normalized_audio) * 0.4
    motion_threshold = np.mean(normalized_motion) * 0.2

    # Retain frame if either speech/audio energy OR visual motion exceeds threshold
    keep_mask = (normalized_audio > audio_threshold) | (normalized_motion > motion_threshold)

    print("PROGRESS:Smoothing cuts with Median Filter...")
    from scipy.signal import medfilt
    keep_mask = medfilt(keep_mask.astype(float), kernel_size=5) > 0.5

    print("PROGRESS:Compiling edit timeline statistics...")
    segments = []
    current_action = "keep" if keep_mask[0] else "delete"
    segment_start_time = 0

    for i in range(1, min_length):
        action = "keep" if keep_mask[i] else "delete"
        if action != current_action:
            segments.append({
                "start": float(segment_start_time),
                "end": float(i),
                "action": current_action
            })
            segment_start_time = i
            current_action = action

    segments.append({
        "start": float(segment_start_time),
        "end": float(min_length),
        "action": current_action
    })

    new_duration = sum([segment["end"] - segment["start"] for segment in segments if segment["action"] == "keep"])
    total_cut_duration = sum([segment["end"] - segment["start"] for segment in segments if segment["action"] == "delete"])

    sfx_count = 0
    for i in range(1, len(segments)):
        if segments[i]["action"] == "keep" and segments[i - 1]["action"] == "delete":
            sfx_count += 1

    result = {
        "original_duration_sec": int(min_length),
        "new_duration_sec": int(new_duration),
        "total_cut_sec": int(total_cut_duration),
        "sfx_count": sfx_count,
        "segments": segments
    }

    print("PROGRESS:Analysis completed successfully!")
    print("RESULT_JSON:" + json.dumps(result))
    return json.dumps(result)


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1:
        analyze_long_video(sys.argv[1])
