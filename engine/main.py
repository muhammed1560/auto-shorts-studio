import os
import sys
import argparse
import subprocess
import tempfile
import shutil
import datetime

try:
    import imageio_ffmpeg
    ffmpeg_exe = imageio_ffmpeg.get_ffmpeg_exe()

    # Handle custom binary names (e.g., ffmpeg-macos-aarch64-v7.1)
    # Create symlink named "ffmpeg" in temp directory so subprocess can find it reliably.
    ffmpeg_bin_dir = os.path.join(tempfile.gettempdir(), "ffmpeg_bin_alias")
    os.makedirs(ffmpeg_bin_dir, exist_ok=True)
    ffmpeg_symlink = os.path.join(ffmpeg_bin_dir, "ffmpeg")

    if not os.path.exists(ffmpeg_symlink):
        os.symlink(ffmpeg_exe, ffmpeg_symlink)

    os.environ["PATH"] = ffmpeg_bin_dir + os.pathsep + os.environ.get("PATH", "")
except ImportError:
    pass

from audio_analyzer import analyze_video_audio
from video_processor import process_short


def download_youtube_video(url: str, output_path: str):
    """Downloads a YouTube video using yt-dlp."""
    print(f"PROGRESS:Downloading video from [{url}]... Network speed determines download time.")
    command = [
        "python3", "-m", "yt_dlp",
        "--extractor-args", "youtube:player_client=android",
        "-f", "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best",
        "-o", output_path,
        url
    ]
    subprocess.run(command, check=True)
    print("PROGRESS:Download completed successfully!")


def generate_shorts(video_path: str, output_dir: str, duration: int = 60, count: int = 6, fit_mode: str = 'crop'):
    """Extracts energy peaks and generates the requested number of jump-cut vertical shorts."""
    if not os.path.exists(output_dir):
        os.makedirs(output_dir, exist_ok=True)

    # Silence removal (jump-cut) can shorten duration by ~40-50%.
    # Therefore, extract extra candidate clips (peaks) to reach the target duration.
    clips_per_short = max(1, int((duration / 15) * 2.0))
    total_peaks_needed = count * clips_per_short

    is_url = video_path.startswith("http://") or video_path.startswith("https://")
    temp_dir = None
    actual_video_path = video_path

    if is_url:
        temp_dir = tempfile.mkdtemp()
        actual_video_path = os.path.join(temp_dir, "downloaded_video.mp4")
        try:
            download_youtube_video(video_path, actual_video_path)
        except Exception as e:
            print(f"[ERROR] Failed to download video: {e}")
            if temp_dir and os.path.exists(temp_dir):
                shutil.rmtree(temp_dir)
            sys.exit(1)

        if not os.path.exists(actual_video_path):
            print("[ERROR] Downloaded video file not found.")
            if temp_dir and os.path.exists(temp_dir):
                shutil.rmtree(temp_dir)
            sys.exit(1)

    print(f"PROGRESS:Analyzing audio energy of [{os.path.basename(actual_video_path)}]...")
    peaks = analyze_video_audio(actual_video_path, num_peaks=total_peaks_needed)

    if len(peaks) < total_peaks_needed:
        print(f"PROGRESS:Warning: Found {len(peaks)} peaks (requested {total_peaks_needed}).")

    peaks.sort()
    timestamp = datetime.datetime.now().strftime("%H%M%S")

    for i in range(count):
        start_index = i * clips_per_short
        end_index = start_index + clips_per_short
        short_peaks = peaks[start_index:end_index]

        if not short_peaks:
            break

        output_clip_path = os.path.join(output_dir, f"short_{i + 1}_{timestamp}.mp4")
        print(f"PROGRESS:Generating Short {i + 1} ({len(short_peaks)} candidate segments)...")
        try:
            actual_duration = process_short(actual_video_path, short_peaks, output_clip_path, fit_mode, duration)
            print(f"PROGRESS:FINAL_DURATION:{actual_duration}")
            print(f"STATUS:SUCCESS:{output_clip_path}")
            print(f"SUCCESS: {output_clip_path}")
        except Exception as e:
            print(f"[ERROR] Error generating Short {i + 1}: {e}")

    if temp_dir and os.path.exists(temp_dir):
        shutil.rmtree(temp_dir)

    print("PROGRESS:All shorts generated successfully!")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Auto Shorts & Video Automation Engine")
    parser.add_argument("--video_path", required=True, help="Local video file path or YouTube URL")
    parser.add_argument("--output", required=True, help="Output directory path")
    parser.add_argument("--duration", type=int, default=60, help="Target duration in seconds")
    parser.add_argument("--count", type=int, default=6, help="Number of shorts to generate")
    parser.add_argument("--fit_mode", type=str, default="crop", choices=["crop", "blur"], help="9:16 aspect ratio fit mode")
    parsed_args = parser.parse_args()

    generate_shorts(
        parsed_args.video_path,
        parsed_args.output,
        parsed_args.duration,
        parsed_args.count,
        parsed_args.fit_mode
    )
