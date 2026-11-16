import os
import subprocess
import numpy as np
from scipy.io import wavfile
import tempfile
import re


def extract_audio(video_path: str, output_audio_path: str):
    """
    Extracts the audio track from the video file as a 16kHz mono WAV for high-speed waveform analysis.
    """
    total_duration = 0.0
    duration_process = subprocess.run(["ffmpeg", "-i", video_path], stderr=subprocess.PIPE, universal_newlines=True)
    duration_match = re.search(r"Duration: (\d{2}):(\d{2}):(\d{2}\.\d{2})", duration_process.stderr)
    if duration_match:
        hours = int(duration_match.group(1))
        minutes = int(duration_match.group(2))
        seconds = float(duration_match.group(3))
        total_duration = hours * 3600 + minutes * 60 + seconds

    print("PROGRESS:Extracting audio track for energy peak detection (Step 1/2)...")
    command = [
        "ffmpeg", "-i", video_path,
        "-vn", "-ac", "1", "-ar", "16000", "-y", output_audio_path
    ]
    process = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, universal_newlines=True)
    time_regex = re.compile(r"time=(\d{2}):(\d{2}):(\d{2}\.\d{2})")
    for line in process.stderr:
        match = time_regex.search(line)
        if match and total_duration > 0:
            h = int(match.group(1))
            m = int(match.group(2))
            s = float(match.group(3))
            extracted_seconds = h * 3600 + m * 60 + s
            progress_percent = min(100, int((extracted_seconds / total_duration) * 100))
            print(f"PROGRESS:%{progress_percent} Audio Demux: {int(extracted_seconds)}/{int(total_duration)}s completed...")
    process.wait()


def find_peaks(audio_path: str, num_peaks: int = 15, min_distance_sec: int = 20) -> list[float]:
    """
    Finds prominent audio energy peaks within the audio track using moving-window RMS energy.
    Ensures peaks are spaced at least `min_distance_sec` seconds apart to avoid redundant clustering.
    """
    sample_rate, audio_data = wavfile.read(audio_path)

    # Normalize audio signal to float32 between -1.0 and 1.0
    if audio_data.dtype != np.float32 and audio_data.dtype != np.float64:
        audio_data = audio_data.astype(np.float32) / np.iinfo(audio_data.dtype).max

    # Window size: 0.5-second time windows
    window_size = int(sample_rate * 0.5)

    num_windows = len(audio_data) // window_size
    data_truncated = audio_data[:num_windows * window_size]
    reshaped_windows = np.abs(data_truncated).reshape((num_windows, window_size))
    energy_levels = np.mean(reshaped_windows, axis=1)

    # Timestamps (seconds): window index * 0.5s
    timestamps = np.arange(num_windows) * 0.5

    # Sort window indices descending by energy
    sorted_indices = np.argsort(energy_levels)[::-1]

    selected_peaks = []
    for index in sorted_indices:
        candidate_time = timestamps[index]

        # Enforce minimum distance from previously chosen peaks
        is_too_close = False
        for selected_time in selected_peaks:
            if abs(candidate_time - selected_time) < min_distance_sec:
                is_too_close = True
                break

        if not is_too_close:
            selected_peaks.append(candidate_time)

        if len(selected_peaks) >= num_peaks:
            break

    return selected_peaks


def analyze_video_audio(video_path: str, num_peaks: int = 15) -> list[float]:
    """
    Extracts audio from the specified video and returns timestamps (in seconds) of the highest energy peaks.
    """
    file_descriptor, temp_wav_path = tempfile.mkstemp(suffix=".wav")
    os.close(file_descriptor)

    try:
        extract_audio(video_path, temp_wav_path)
        peaks = find_peaks(temp_wav_path, num_peaks=num_peaks)
        return peaks
    finally:
        if os.path.exists(temp_wav_path):
            os.remove(temp_wav_path)
