#!/usr/bin/env python3
"""
rhythm_daemon.py — continuous 4/4 rhythmic music engine for vibes plugin.

Runs as a background daemon (spawned by vibes.sh).
Generates and plays music bar-by-bar, switching modes based on ~/.claude/vibes.json.

Modes: flow | focus | drive | waiting | success | error
Synthesis: pure Python stdlib (wave, struct, math, random) — no external deps.
Playback: afplay (macOS), one bar at a time.
"""

import json
import math
import os
import random
import struct
import subprocess
import sys
import tempfile
import time
import wave

# ---------------------------------------------------------------------------
# State file
# ---------------------------------------------------------------------------

STATE_FILE = os.path.expanduser("~/.claude/vibes.json")
SAMPLE_RATE = 44100


def read_state() -> dict:
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except Exception:
        return {}


def write_pid(pid: int) -> None:
    state = read_state()
    state["daemon_pid"] = pid
    try:
        with open(STATE_FILE, "w") as f:
            json.dump(state, f)
    except Exception:
        pass


def update_mode(mode: str) -> None:
    state = read_state()
    state["mode"] = mode
    state["updated_at"] = int(time.time())
    try:
        with open(STATE_FILE, "w") as f:
            json.dump(state, f)
    except Exception:
        pass


# ---------------------------------------------------------------------------
# Musical constants
# ---------------------------------------------------------------------------

# Note frequencies (Hz)
NOTE_FREQ = {
    "A2": 110.00, "B2": 123.47, "C3": 130.81, "D3": 146.83, "E3": 164.81,
    "F3": 174.61, "G3": 196.00, "A3": 220.00, "B3": 246.94, "C4": 261.63,
    "D4": 293.66, "E4": 329.63, "F4": 349.23, "G4": 392.00, "A4": 440.00,
    "B4": 493.88, "C5": 523.25, "D5": 587.33, "E5": 659.25, "F5": 698.46,
    "G5": 783.99, "A5": 880.00,
}

# Chord definitions: root + third + fifth (frequencies in Hz)
CHORDS = {
    "Am": [NOTE_FREQ["A3"], NOTE_FREQ["C4"], NOTE_FREQ["E4"]],
    "F":  [NOTE_FREQ["F3"], NOTE_FREQ["A3"], NOTE_FREQ["C4"]],
    "C":  [NOTE_FREQ["C4"], NOTE_FREQ["E4"], NOTE_FREQ["G4"]],
    "G":  [NOTE_FREQ["G3"], NOTE_FREQ["B3"], NOTE_FREQ["D4"]],
    "Em": [NOTE_FREQ["E3"], NOTE_FREQ["G3"], NOTE_FREQ["B3"]],
    "D":  [NOTE_FREQ["D3"], NOTE_FREQ["F3"], NOTE_FREQ["A3"]],
    "Dm": [NOTE_FREQ["D3"], NOTE_FREQ["F3"], NOTE_FREQ["A3"]],
    "Bb": [NOTE_FREQ["A3"]*1.0595, NOTE_FREQ["D4"], NOTE_FREQ["F4"]],
}

# Bass note (root) for each chord
BASS_NOTE = {
    "Am": NOTE_FREQ["A2"],
    "F":  NOTE_FREQ["F3"] / 2,
    "C":  NOTE_FREQ["C3"],
    "G":  NOTE_FREQ["G2"] if "G2" in NOTE_FREQ else NOTE_FREQ["G3"] / 2,
    "Em": NOTE_FREQ["E3"] / 2,
    "D":  NOTE_FREQ["D3"] / 2,
    "Dm": NOTE_FREQ["D3"] / 2,
    "Bb": NOTE_FREQ["A3"] * 1.0595 / 2,
}
# Fill in G2 manually
BASS_NOTE["G"] = 98.00  # G2

# Mode configurations
MODES = {
    "flow":    {"bpm": 72,  "chords": ["Am", "F",  "C",  "G"]},
    "focus":   {"bpm": 84,  "chords": ["C",  "G",  "Am", "F"]},
    "drive":   {"bpm": 90,  "chords": ["Em", "C",  "G",  "D"]},
    "waiting": {"bpm": 60,  "chords": ["Dm", "Am", "Dm", "Am"]},
    "success": {"bpm": 90,  "chords": ["C",  "G",  "Am", "F"]},
    "error":   {"bpm": 66,  "chords": ["Am", "F",  "Dm", "Am"]},
}

# Drum patterns: 16 steps per bar (16th notes)
# Each entry: (pattern, base_volume)
DRUM_PATTERNS = {
    "flow": {
        "kick":  ([1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0], 0.60),
        "snare": ([0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0], 0.35),
        "hihat": ([1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0], 0.15),
    },
    "focus": {
        "kick":  ([1,0,0,0,0,0,1,0,1,0,0,0,0,0,0,0], 0.60),
        "snare": ([0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0], 0.45),
        "hihat": ([1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0], 0.15),
    },
    "drive": {
        "kick":  ([1,0,1,0,0,0,1,0,1,0,1,0,0,0,1,0], 0.60),
        "snare": ([0,0,0,0,1,0,0,0,0,0,0,0,1,0,1,0], 0.45),
        "hihat": ([1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1], 0.15),
    },
    "waiting": {
        "kick":  ([1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], 0.55),
        "snare": ([0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], 0.00),
        "hihat": ([1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0], 0.10),
    },
    "success": {
        "kick":  ([1,0,0,0,0,0,1,0,1,0,0,0,0,0,1,0], 0.65),
        "snare": ([0,0,0,0,1,0,0,0,0,0,0,0,1,0,1,0], 0.50),
        "hihat": ([1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0], 0.18),
    },
    "error": {
        "kick":  ([1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0], 0.50),
        "snare": ([0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0], 0.30),
        "hihat": ([1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0], 0.10),
    },
}

# 8th-note swing: positions (0-indexed) that get a slight push forward
SWING_POSITIONS = {2, 6, 10, 14}
SWING_OFFSET_S = 0.004  # +4ms

# Melodic sequences: (note_name_or_None, duration_beats)
# None = rest. 1 beat = 1 quarter note.
MELODIES = {
    "flow": [  # A minor pentatonic: A C D E G
        ("A4", 0.5), ("C5", 0.25), ("D5", 0.25),  # bar 1
        ("E5", 0.25), (None, 0.25), ("C5", 0.5),   # bar 2
        (None, 0.5), ("A4", 0.5),                  # bar 3
        ("E4", 1.0),                               # bar 4
    ],
    "focus": [  # C major pentatonic: C D E G A
        ("E5", 0.25), ("G5", 0.25), ("A5", 0.5),   # bar 1
        ("G5", 0.25), ("E5", 0.25), ("D5", 0.5),   # bar 2
        ("C5", 0.25), ("E5", 0.25), ("G5", 0.25), ("A5", 0.25),  # bar 3
        ("G5", 0.5), ("E5", 0.5),                  # bar 4
    ],
    "drive": [  # E minor pentatonic: E G A B D
        ("B4", 0.125), ("D5", 0.125), ("E5", 0.25), ("B4", 0.5),  # bar 1
        ("G4", 0.125), ("A4", 0.125), ("B4", 0.75),               # bar 2
        ("E5", 0.125), ("D5", 0.125), ("B4", 0.25), ("A4", 0.25), ("G4", 0.25),  # bar 3
        ("B4", 1.0),                                               # bar 4
    ],
    "waiting": [  # D minor pentatonic: D F A
        ("F5", 0.5), (None, 0.5),   # bar 1
        (None, 1.0),                # bar 2
        ("A4", 0.5), (None, 0.5),   # bar 3
        ("D5", 1.5),                # bar 4 (extends into silence)
    ],
    "success": [  # Bright major: C D E G A
        ("C5", 0.25), ("E5", 0.25), ("G5", 0.25), ("A5", 0.25),
        ("G5", 0.5), ("E5", 0.5),
        ("C5", 0.25), ("G5", 0.25), ("A5", 0.5),
        ("G5", 1.0),
    ],
    "error": [  # Minor, slow walk
        ("A4", 0.5), (None, 0.5),
        ("G4", 0.5), (None, 0.5),
        ("F4", 0.5), (None, 0.5),
        ("E4", 1.0),
    ],
}


# ---------------------------------------------------------------------------
# Synthesis helpers
# ---------------------------------------------------------------------------

def mix(a: list, b: list) -> list:
    """Mix two sample buffers (zero-pad shorter)."""
    n = max(len(a), len(b))
    result = [0.0] * n
    for i in range(len(a)):
        result[i] += a[i]
    for i in range(len(b)):
        result[i] += b[i]
    return result


def scale(samples: list, vol: float) -> list:
    return [s * vol for s in samples]


def silence(n_samples: int) -> list:
    return [0.0] * n_samples


def apply_reverb(samples: list) -> list:
    """3-tap delay reverb."""
    taps = [
        (int(0.030 * SAMPLE_RATE), 0.35),
        (int(0.070 * SAMPLE_RATE), 0.20),
        (int(0.120 * SAMPLE_RATE), 0.10),
    ]
    result = list(samples)
    for delay, level in taps:
        for i in range(delay, len(result)):
            result[i] += samples[i - delay] * level
    return result


def normalize(samples: list, peak: float = 0.85) -> list:
    """Normalize to avoid clipping."""
    mx = max(abs(s) for s in samples) if samples else 1.0
    if mx < 1e-9:
        return samples
    factor = peak / mx
    return [s * factor for s in samples]


def fade_in(samples: list, duration: float = 0.30) -> list:
    """Apply a linear fade-in to avoid hard entry after a mode switch."""
    n = min(int(SAMPLE_RATE * duration), len(samples))
    result = list(samples)
    for i in range(n):
        result[i] *= i / n
    return result


def write_wav(samples: list, path: str) -> None:
    clipped = [max(-32767, min(32767, int(s * 32767))) for s in samples]
    with wave.open(path, "w") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(struct.pack(f"<{len(clipped)}h", *clipped))


# ---------------------------------------------------------------------------
# Instrument synthesis
# ---------------------------------------------------------------------------

def synth_kick(duration: float = 0.15) -> list:
    """Sine sweep 80→40 Hz with exponential decay."""
    n = int(SAMPLE_RATE * duration)
    samples = []
    phase = 0.0
    for i in range(n):
        t = i / SAMPLE_RATE
        env = math.exp(-20 * t / duration)
        freq = 80 * math.exp(-math.log(2) * t / duration)  # 80→40 Hz
        phase += 2 * math.pi * freq / SAMPLE_RATE
        samples.append(env * math.sin(phase))
    return samples


def synth_snare(duration: float = 0.12) -> list:
    """White noise + 200 Hz sine with fast decay."""
    n = int(SAMPLE_RATE * duration)
    samples = []
    for i in range(n):
        t = i / SAMPLE_RATE
        env = math.exp(-30 * t / duration)
        noise = random.uniform(-1, 1)
        tone = math.sin(2 * math.pi * 200 * t)
        samples.append(env * (0.7 * noise + 0.3 * tone))
    return samples


def synth_hihat(duration: float = 0.03) -> list:
    """White noise burst with exponential decay."""
    n = int(SAMPLE_RATE * duration)
    return [math.exp(-60 * i / n) * random.uniform(-1, 1) for i in range(n)]


def synth_bass(freq: float, duration: float) -> list:
    """Sine + octave harmonic, slow release."""
    n = int(SAMPLE_RATE * duration)
    attack = int(0.01 * SAMPLE_RATE)
    release = int(min(0.3 * SAMPLE_RATE, n * 0.4))
    samples = []
    for i in range(n):
        t = i / SAMPLE_RATE
        if i < attack:
            env = i / attack
        elif i > n - release:
            env = (n - i) / release
        else:
            env = 1.0
        wave_val = math.sin(2 * math.pi * freq * t) + 0.5 * math.sin(2 * math.pi * freq * 2 * t)
        samples.append(env * wave_val / 1.5)
    return samples


def synth_piano_note(freq: float, duration: float) -> list:
    """Rhodes-style electric piano: harmonic partials with punchy attack + sustain decay."""
    n = int(SAMPLE_RATE * duration)
    # Partials: strong fundamental, bright 2nd, tapering higher harmonics
    partials = [(1, 1.0), (2, 0.60), (3, 0.25), (4, 0.10), (5, 0.05)]
    total_amp = sum(a for _, a in partials)
    attack_n = max(1, int(0.001 * SAMPLE_RATE))  # 1ms punchy attack
    tau_fast = 0.04                               # 40ms initial bark
    tau_slow = max(duration * 0.5, 0.20)          # sustain tail
    samples = []
    for i in range(n):
        t = i / SAMPLE_RATE
        if i < attack_n:
            env = i / attack_n
        else:
            t2 = t - attack_n / SAMPLE_RATE
            env = 0.5 * math.exp(-t2 / tau_fast) + 0.5 * math.exp(-t2 / tau_slow)
        wave_val = sum(amp * math.sin(2 * math.pi * freq * k * t) for k, amp in partials)
        samples.append(env * wave_val / total_amp)
    return samples


def synth_piano_chord(freqs: list, duration: float) -> list:
    """Funky chord stab: staggered piano-style voicing, punchy and short."""
    n = int(SAMPLE_RATE * duration)
    buffer = [0.0] * n
    stagger = int(0.012 * SAMPLE_RATE)  # 12ms stagger between chord notes
    stab_dur = min(duration, 0.50)      # chord stab caps at 0.5s regardless of bar length
    for idx, freq in enumerate(freqs):
        note = synth_piano_note(freq, stab_dur)
        onset = idx * stagger
        for i, s in enumerate(note):
            pos = onset + i
            if pos < n:
                buffer[pos] += s / len(freqs)
    return buffer


# ---------------------------------------------------------------------------
# Bar generation
# ---------------------------------------------------------------------------

def seconds_per_beat(bpm: float) -> float:
    return 60.0 / bpm


def generate_bar(mode: str, bar_index: int) -> list:
    """Generate one bar of audio samples."""
    cfg = MODES[mode]
    bpm = cfg["bpm"]
    chords = cfg["chords"]
    chord_name = chords[bar_index % len(chords)]

    spb = seconds_per_beat(bpm)            # seconds per beat (quarter note)
    step_dur = spb / 4                     # 16th note duration
    bar_dur = spb * 4                      # total bar duration
    bar_samples = int(SAMPLE_RATE * bar_dur)

    buffer = silence(bar_samples)

    # --- Drums ---
    pattern_key = mode if mode in DRUM_PATTERNS else "flow"
    drum_cfg = DRUM_PATTERNS[pattern_key]

    for drum_type, (pattern, base_vol) in drum_cfg.items():
        if base_vol == 0.0:
            continue
        for step, hit in enumerate(pattern):
            if not hit:
                continue

            # Timing jitter ±2ms (tight, professional)
            jitter = random.uniform(-0.002, 0.002)
            # Swing offset
            swing = SWING_OFFSET_S if step in SWING_POSITIONS else 0.0
            # Velocity variation ±5% (consistent dynamics)
            vel = base_vol * random.uniform(0.95, 1.05)

            onset = step * step_dur + jitter + swing
            onset_sample = max(0, int(onset * SAMPLE_RATE))

            if drum_type == "kick":
                hit_samples = scale(synth_kick(), vel)
            elif drum_type == "snare":
                hit_samples = scale(synth_snare(), vel)
            else:  # hihat
                hit_samples = scale(synth_hihat(), vel)

            # Mix into buffer
            end = min(len(buffer), onset_sample + len(hit_samples))
            for i, s in enumerate(hit_samples[:end - onset_sample]):
                buffer[onset_sample + i] += s

    # --- Bass ---
    bass_freq = BASS_NOTE.get(chord_name, 110.0)
    bass = scale(synth_bass(bass_freq, bar_dur * 0.9), 0.35)
    buffer = mix(buffer, bass)

    # --- Chord stab ---
    chord_freqs = CHORDS.get(chord_name, [261.63, 329.63, 392.00])
    pad = scale(synth_piano_chord(chord_freqs, bar_dur), 0.18)
    buffer = mix(buffer, pad)

    # --- Melody (4-bar loop) ---
    melody_key = mode if mode in MELODIES else "flow"
    melody_sequence = MELODIES[melody_key]
    bars_per_loop = 4
    melody_bar = bar_index % bars_per_loop

    # Calculate which notes fall in this bar
    beats_per_bar = 4.0
    bar_start_beat = melody_bar * beats_per_bar
    bar_end_beat = bar_start_beat + beats_per_bar

    cursor = 0.0
    for note_name, note_beats in melody_sequence:
        note_start = cursor
        note_end = cursor + note_beats
        cursor = note_end

        if note_end <= bar_start_beat:
            continue
        if note_start >= bar_end_beat:
            break

        if note_name is None:
            continue

        freq = NOTE_FREQ.get(note_name)
        if freq is None:
            continue

        # Clip to this bar
        local_start = max(0.0, note_start - bar_start_beat)
        local_end = min(beats_per_bar, note_end - bar_start_beat)
        local_dur = (local_end - local_start) * spb

        if local_dur < 0.01:
            continue

        mel = scale(synth_piano_note(freq, local_dur), 0.25)
        onset_sample = int(local_start * spb * SAMPLE_RATE)
        end = min(len(buffer), onset_sample + len(mel))
        for i, s in enumerate(mel[:end - onset_sample]):
            buffer[onset_sample + i] += s

    # --- Reverb + normalize ---
    buffer = apply_reverb(buffer)
    buffer = normalize(buffer, peak=0.50)

    return buffer


def generate_fade_out(duration: float = 0.50) -> list:
    """Soft chord that fades to silence — played on vibes off to avoid a hard cut."""
    n = int(SAMPLE_RATE * duration)
    freqs = [220.0, 330.0, 440.0]  # A minor chord
    return [
        0.10 * sum(math.sin(2 * math.pi * f * i / SAMPLE_RATE) for f in freqs)
        * (1.0 - i / n)
        for i in range(n)
    ]


# ---------------------------------------------------------------------------
# Daemon main loop
# ---------------------------------------------------------------------------

def main() -> None:
    pid = os.getpid()
    write_pid(pid)

    bar_index = 0
    transient_bars = 0   # bars remaining in a transient mode (success/error)
    base_mode = "flow"   # mode to return to after transient
    TRANSIENT_MODES = {"success", "error"}
    TRANSIENT_DURATION = 8  # bars
    prev_play_mode = None  # track previous bar's mode for fade-in on transitions

    tmp_path = None

    try:
        while True:
            # Read state
            state = read_state()
            if not state.get("enabled", False):
                break

            current_mode = state.get("mode", "flow")

            # Handle transient mode logic
            if current_mode in TRANSIENT_MODES:
                if transient_bars == 0:
                    base_mode = base_mode  # keep current base
                    transient_bars = TRANSIENT_DURATION
            else:
                base_mode = current_mode
                transient_bars = 0

            if transient_bars > 0:
                play_mode = current_mode
                transient_bars -= 1
                if transient_bars == 0:
                    update_mode(base_mode)
            else:
                play_mode = current_mode

            # Generate bar
            samples = generate_bar(play_mode, bar_index)
            bar_index += 1

            # Fade in on startup and mode transitions so music never blasts in hard
            if prev_play_mode is None or play_mode != prev_play_mode:
                samples = fade_in(samples)
            prev_play_mode = play_mode

            # Write to temp WAV
            fd, tmp_path = tempfile.mkstemp(suffix=".wav")
            os.close(fd)
            write_wav(samples, tmp_path)

            # Start afplay
            proc = subprocess.Popen(
                ["afplay", tmp_path],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )

            # Poll while playing — let current bar finish on mode change (no hard cut)
            while proc.poll() is None:
                time.sleep(0.1)
                new_state = read_state()
                if not new_state.get("enabled", False):
                    proc.terminate()
                    proc.wait()
                    # Play a short fade-out chord so the stop isn't a hard cut
                    fd2, fade_path = tempfile.mkstemp(suffix=".wav")
                    os.close(fd2)
                    write_wav(generate_fade_out(), fade_path)
                    fade_proc = subprocess.Popen(
                        ["afplay", fade_path],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                    )
                    fade_proc.wait()
                    try:
                        os.unlink(fade_path)
                    except OSError:
                        pass
                    break

            # Clean up temp file
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
            tmp_path = None

            # Check if we should exit (disabled during polling)
            if not read_state().get("enabled", False):
                break

    except KeyboardInterrupt:
        pass
    finally:
        if tmp_path and os.path.exists(tmp_path):
            try:
                os.unlink(tmp_path)
            except OSError:
                pass


if __name__ == "__main__":
    main()
