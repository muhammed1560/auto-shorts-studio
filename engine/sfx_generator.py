import numpy as np
from scipy.io import wavfile
import os


def generate_pop(filename: str = "pop.wav", sample_rate: int = 44100):
    """Generates a synthetic percussive 'pop' audio sample using an exponential decay sine sweep."""
    duration = 0.1
    time_array = np.linspace(0, duration, int(sample_rate * duration), False)
    # Frequency sweep from 800Hz down to 200Hz
    frequencies = np.linspace(800, 200, len(time_array))
    wave = np.sin(2 * np.pi * frequencies * time_array)
    # Exponential decay envelope
    envelope = np.exp(-time_array * 30)
    audio = wave * envelope
    audio = np.int16(audio / np.max(np.abs(audio)) * 32767)
    wavfile.write(filename, sample_rate, audio)


def generate_whoosh(filename: str = "whoosh.wav", sample_rate: int = 44100):
    """Generates a synthetic cinematic 'whoosh' audio sample using bandpassed noise and a smooth parabolic envelope."""
    duration = 0.5
    time_array = np.linspace(0, duration, int(sample_rate * duration), False)
    # White noise distribution
    noise = np.random.normal(0, 1, len(time_array))
    # Bandpass filter effect using a moving average window
    window_size = 50
    filtered_noise = np.convolve(noise, np.ones(window_size) / window_size, mode='same')
    # Envelope: smooth rise and fall
    envelope = np.sin(np.pi * time_array / duration) ** 2
    audio = filtered_noise * envelope
    audio = np.int16(audio / np.max(np.abs(audio)) * 32767)
    wavfile.write(filename, sample_rate, audio)


if __name__ == "__main__":
    sfx_directory = os.path.join(os.path.dirname(__file__), "assets", "sfx")
    os.makedirs(sfx_directory, exist_ok=True)

    generate_pop(os.path.join(sfx_directory, "pop.wav"))
    generate_whoosh(os.path.join(sfx_directory, "whoosh.wav"))
    print("Transition SFX generated successfully.")
