"""Makes the game's music and sound effects from scratch (self-made, no third-party audio).

Run from the project folder:  python3 tools/make_sounds.py
Writes WAV files to assets/audio/. Needs numpy.

Every sound is built from sine waves and filtered noise. A fixed random seed
makes the files identical on every run.
"""
import os
import wave

import numpy as np

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
rng = np.random.default_rng(19)


def note(name):
    """Frequency of a note name such as 'C4' or 'F#5'."""
    names = {"C": 0, "C#": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "G": 7,
             "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}
    pitch, octave = name[:-1], int(name[-1])
    midi = 12 * (octave + 1) + names[pitch]
    return 440.0 * 2 ** ((midi - 69) / 12)


def t_axis(seconds):
    return np.arange(int(seconds * RATE)) / RATE


def pluck(freq, seconds, decay=3.0, bright=0.25):
    """A soft plucked/bell tone: a sine with a quieter octave, fading out."""
    t = t_axis(seconds)
    tone = np.sin(2 * np.pi * freq * t) + bright * np.sin(2 * np.pi * 2 * freq * t)
    env = np.exp(-decay * t) * np.minimum(t / 0.01, 1.0)
    return tone * env


def pad(freqs, seconds, attack=1.2, release=1.5):
    """A warm held chord: two slightly detuned sines per note, slow in and out."""
    t = t_axis(seconds)
    out = np.zeros_like(t)
    for f in freqs:
        out += np.sin(2 * np.pi * f * t) + np.sin(2 * np.pi * f * 1.003 * t + 1.0)
    env = np.minimum(t / attack, 1.0) * np.minimum((seconds - t) / release, 1.0)
    return out * np.clip(env, 0, 1) / (2 * len(freqs))


def add(track, sound, at):
    """Mixes a sound into a track at a time in seconds, wrapping round the end (for loops)."""
    start = int(at * RATE)
    idx = (start + np.arange(len(sound))) % len(track)
    np.add.at(track, idx, sound)


def circular_reverb(track, seconds=2.2, mix=0.35):
    """A soft room echo. Circular, so a looping track stays seamless."""
    t = t_axis(seconds)
    impulse = rng.standard_normal(len(t)) * np.exp(-3.0 * t)
    impulse[0] = 0
    n = len(track)
    kernel = np.zeros(n)
    kernel[: len(impulse)] = impulse[:n]
    wet = np.real(np.fft.ifft(np.fft.fft(track) * np.fft.fft(kernel)))
    wet *= np.max(np.abs(track)) / (np.max(np.abs(wet)) + 1e-9)
    return track * (1 - mix) + wet * mix


def lowpass_noise(seconds, cutoff):
    """Noise with everything above the cutoff removed (circular, so it loops)."""
    n = int(seconds * RATE)
    spectrum = np.fft.rfft(rng.standard_normal(n))
    freqs = np.fft.rfftfreq(n, 1 / RATE)
    spectrum *= 1 / (1 + (freqs / cutoff) ** 2)
    return np.fft.irfft(spectrum, n)


def save(name, data, peak=0.8):
    data = data / (np.max(np.abs(data)) + 1e-9) * peak
    pcm = (data * 32767).astype(np.int16)
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(pcm.tobytes())
    print(f"{name}: {len(data) / RATE:.1f} s")


def fade(data, out_seconds=0.3):
    n = int(out_seconds * RATE)
    data[-n:] *= np.linspace(1, 0, n)
    return data


# ------------------------------------------------------------ Calm music (loops)
BAR = 4.0
CHORDS = [  # Eight bars, then it repeats.
    ["C3", "G3", "E4", "B4"], ["A2", "E3", "C4", "G4"], ["F2", "C3", "A3", "E4"], ["G2", "D3", "B3", "D4"],
    ["C3", "G3", "E4", "G4"], ["E2", "B2", "G3", "D4"], ["F2", "C3", "A3", "C4"], ["G2", "D3", "B3", "F4"],
]
SCALE = ["C5", "D5", "E5", "G5", "A5", "C6"]   # Pentatonic, so every note sounds calm.
length = BAR * len(CHORDS)
music = np.zeros(int(length * RATE))
for bar, chord in enumerate(CHORDS):
    add(music, pad([note(n) for n in chord], BAR + 1.5), bar * BAR)         # Overlaps into the next bar.
    add(music, 0.35 * pluck(note(chord[0]) / 2, 3.5, decay=1.2, bright=0.1), bar * BAR)   # Soft bass.
    for beat in sorted(rng.choice(8, size=3, replace=False)):              # A few melody notes per bar.
        add(music, 0.22 * pluck(note(SCALE[rng.integers(len(SCALE))]), 2.5, decay=2.2), bar * BAR + beat * 0.5)
music = circular_reverb(music)
save("music_calm.wav", music, peak=0.55)

# Gentle sea waves: slow swells of soft noise (loops every 32 s).
t = t_axis(length)
swell = 0.55 + 0.45 * np.sin(2 * np.pi * t / 8.0) * np.sin(2 * np.pi * t / 32.0 + 0.7)
waves = lowpass_noise(length, 500) * swell + 0.3 * lowpass_noise(length, 2500) * swell ** 3
save("ambience_waves.wav", waves, peak=0.5)

# ------------------------------------------------------------ Effects
# Win: a rising, bright arpeggio and a held major chord.
win = np.zeros(int(3.2 * RATE))
for i, n in enumerate(["C5", "E5", "G5", "C6", "E6"]):
    add(win, 0.5 * pluck(note(n), 2.0, decay=2.0, bright=0.35), i * 0.12)
add(win, 0.6 * pad([note(n) for n in ["C4", "E4", "G4", "C5"]], 2.6, attack=0.15, release=1.2), 0.6)
save("win.wav", fade(circular_reverb(win, 1.2, 0.25)), peak=0.85)

# Lose: three slow falling notes in a minor key, over a low chord.
lose = np.zeros(int(3.4 * RATE))
for i, n in enumerate(["G4", "Eb4", "C4"]):
    add(lose, 0.5 * pluck(note(n), 2.2, decay=1.6, bright=0.15), i * 0.45)
add(lose, 0.5 * pad([note(n) for n in ["C3", "Eb3", "G3"]], 3.0, attack=0.4, release=1.5), 0.2)
save("lose.wav", fade(circular_reverb(lose, 1.5, 0.3)), peak=0.8)

# Build: two wooden knocks and a small sparkle.
build = np.zeros(int(0.9 * RATE))
for i, f in enumerate([180.0, 240.0]):
    knock = pluck(f, 0.25, decay=28.0, bright=0.6) + 0.4 * lowpass_noise(0.25, 1800) * np.exp(-40 * t_axis(0.25))
    add(build, knock, i * 0.12)
add(build, 0.35 * pluck(note("G5"), 0.6, decay=6.0, bright=0.4), 0.26)
add(build, 0.3 * pluck(note("C6"), 0.6, decay=6.0, bright=0.4), 0.33)
save("build.wav", fade(build, 0.1), peak=0.8)

# Event: a two-note bell, so the player looks up.
event = np.zeros(int(2.0 * RATE))
add(event, 0.6 * pluck(note("E5"), 1.8, decay=2.5, bright=0.5), 0.0)
add(event, 0.6 * pluck(note("B5"), 1.6, decay=2.5, bright=0.5), 0.22)
save("event.wav", fade(circular_reverb(event, 1.0, 0.2)), peak=0.75)

# Danger: a low, short double warning tone.
danger = np.zeros(int(1.0 * RATE))
for i in range(2):
    add(danger, pluck(note("A3"), 0.35, decay=6.0, bright=0.6) + 0.5 * pluck(note("Bb3"), 0.35, decay=6.0), i * 0.3)
save("danger.wav", fade(danger, 0.1), peak=0.7)

# Click: a tiny soft tick for menu choices.
save("click.wav", fade(pluck(note("A5"), 0.12, decay=40.0, bright=0.3), 0.03), peak=0.5)
