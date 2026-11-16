import os
import subprocess
import tempfile
import json
import shutil
import platform
import random
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


def get_video_encoder() -> str:
    """Detects available hardware-accelerated video encoder, falls back to libx264."""
    if platform.system() == "Darwin":
        return "h264_videotoolbox"
    return "libx264"


FFMPEG_CMD = get_ffmpeg_executable()


def process_long_video(video_path: str, analysis_json_str: str, output_path: str, sfx_name: str = None):
    """
    Trims silence/inactivity intervals based on analysis metadata and overlays transition sound effects (SFX).
    """
    data = json.loads(analysis_json_str)
    segments_to_keep = [segment for segment in data.get("segments", []) if segment.get("action") == "keep"]

    if not segments_to_keep:
        raise ValueError("No retainable scenes found in the analysis metadata.")

    sfx_file_path = None
    is_random_sfx = False

    if sfx_name and sfx_name.lower() != "none":
        normalized_sfx = sfx_name.lower().strip()
        if normalized_sfx in ["random", "mixed"]:
            is_random_sfx = True
            sfx_file_path = "random"
        else:
            candidate_path = os.path.join(os.path.dirname(__file__), "assets", "sfx", f"{normalized_sfx}.wav")
            if os.path.exists(candidate_path):
                sfx_file_path = candidate_path

    with tempfile.TemporaryDirectory() as temp_dir:
        # Step 1: Concat trim using single-pass FFmpeg filter_complex
        filter_complex_graph = []
        concat_input_tags = ""
        transition_timestamps = []
        current_timeline_time = 0.0

        for index, segment in enumerate(segments_to_keep):
            start = segment["start"]
            end = segment["end"]
            clip_duration = end - start

            filter_complex_graph.append(f"[0:v]trim=start={start}:end={end},setpts=PTS-STARTPTS[v{index}]")
            filter_complex_graph.append(f"[0:a]atrim=start={start}:end={end},asetpts=PTS-STARTPTS[a{index}]")
            concat_input_tags += f"[v{index}][a{index}]"

            current_timeline_time += clip_duration
            if index < len(segments_to_keep) - 1:
                transition_timestamps.append(current_timeline_time)

        filter_complex_graph.append(f"{concat_input_tags}concat=n={len(segments_to_keep)}:v=1:a=1[outv][outa]")

        temp_cut_video = os.path.join(temp_dir, "cut_video.mp4")
        video_encoder = get_video_encoder()
        ffmpeg_cut_command = [
            FFMPEG_CMD, "-threads", "4", "-i", video_path,
            "-filter_complex", ";".join(filter_complex_graph),
            "-map", "[outv]", "-map", "[outa]",
            "-c:v", video_encoder, "-b:v", "8M", "-c:a", "aac",
            "-y", temp_cut_video
        ]

        expected_duration = current_timeline_time
        print("PROGRESS:Trimming silence and rendering cuts (Step 1/2)...")

        process = subprocess.Popen(ffmpeg_cut_command, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, universal_newlines=True)
        time_regex = re.compile(r"time=(\d{2}):(\d{2}):(\d{2}\.\d{2})")

        for line in process.stderr:
            match = time_regex.search(line)
            if match:
                h = int(match.group(1))
                m = int(match.group(2))
                s = float(match.group(3))
                rendered_seconds = h * 3600 + m * 60 + s

                if expected_duration > 0:
                    percent = min(100, int((rendered_seconds / expected_duration) * 100))
                    print(f"PROGRESS:%{percent} Render: {int(rendered_seconds)}/{int(expected_duration)}s completed...")

        process.wait()
        if process.returncode != 0:
            raise RuntimeError("FFmpeg encountered an error during jump-cut rendering.")

        # Step 2: Overlay Transition Sound Effects (SFX)
        if sfx_file_path and transition_timestamps:
            print("PROGRESS:Adding transition sound effects (SFX) (Step 2/2)...")
            sfx_filters = []
            sfx_input_tags = []

            ffmpeg_sfx_command = [FFMPEG_CMD, "-i", temp_cut_video]

            for index, timestamp in enumerate(transition_timestamps):
                if is_random_sfx:
                    chosen_sound = random.choice(["pop", "whoosh"])
                    current_sfx_source = os.path.join(os.path.dirname(__file__), "assets", "sfx", f"{chosen_sound}.wav")
                else:
                    current_sfx_source = sfx_file_path

                ffmpeg_sfx_command.extend(["-i", current_sfx_source])
                delay_ms = int(timestamp * 1000)
                sfx_filters.append(f"[{index + 1}:a]adelay={delay_ms}|{delay_ms}[sfx{index}]")
                sfx_input_tags.append(f"[sfx{index}]")

            mix_sources = "[0:a]" + "".join(sfx_input_tags)
            total_audio_inputs = len(transition_timestamps) + 1

            amix_filter = f"{mix_sources}amix=inputs={total_audio_inputs}:duration=first:dropout_transition=0:normalize=0[aout]"
            sfx_filters.append(amix_filter)

            ffmpeg_sfx_command.extend([
                "-filter_complex", ";".join(sfx_filters),
                "-map", "0:v", "-map", "[aout]",
                "-c:v", "copy", "-c:a", "aac",
                "-y", output_path
            ])
            subprocess.run(ffmpeg_sfx_command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        else:
            subprocess.run(["cp", temp_cut_video, output_path], check=True)

    print(f"STATUS:SUCCESS:{output_path}")


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 3:
        input_video = sys.argv[1]
        analysis_json = sys.argv[2]
        output_file = sys.argv[3]
        sfx_selection = sys.argv[4] if len(sys.argv) > 4 else None
        process_long_video(input_video, analysis_json, output_file, sfx_selection)
