#!/usr/bin/env python3
"""
vibes — sentiment-driven musical phrases for Claude Code events.

Hooks: Stop, Notification
Moods: triumphant, oops, contemplative, neutral
Synthesis: sine + octave harmonic + 5th harmonic, exponential decay, WAV output
Playback: afplay (macOS), non-blocking
"""

import json
import math
import os
import random
import struct
import subprocess
import sys
import tempfile
import wave

# ---------------------------------------------------------------------------
# Phrase library — notes as (frequency_hz, duration_s)
# ---------------------------------------------------------------------------

NOTE = {
    "B3":  246.94,
    "C4":  261.63,
    "D4":  293.66,
    "E4":  329.63,
    "F4":  349.23,
    "G3":  196.00,
    "G4":  392.00,
    "A3":  220.00,
    "A4":  440.00,
    "C5":  523.25,
    "E5":  659.25,
    "G5":  783.99,
}

PHRASES = {
    "triumphant": [
        # 1 — Clean rising resolution
        [(NOTE["C4"], 0.2), (NOTE["E4"], 0.2), (NOTE["G4"], 0.2), (NOTE["C5"], 0.6)],
        # 2 — Full ascending fanfare
        [(NOTE["G3"], 0.15), (NOTE["C4"], 0.15), (NOTE["E4"], 0.15), (NOTE["G4"], 0.15), (NOTE["C5"], 0.4), (NOTE["E5"], 0.5)],
        # 3 — Joyful skip
        [(NOTE["E4"], 0.2), (NOTE["G4"], 0.2), (NOTE["C5"], 0.2), (NOTE["G4"], 0.15), (NOTE["E5"], 0.5)],
        # 4 — Victory!
        [(NOTE["C4"], 0.1), (NOTE["E4"], 0.1), (NOTE["G4"], 0.1), (NOTE["C5"], 0.15), (NOTE["E5"], 0.15), (NOTE["G5"], 0.4)],
    ],
    "oops": [
        # 1 — Gentle descend
        [(NOTE["E4"], 0.25), (NOTE["D4"], 0.25), (NOTE["C4"], 0.25), (NOTE["B3"], 0.5)],
        # 2 — Sad with tiny lift
        [(NOTE["C4"], 0.2), (NOTE["B3"], 0.2), (NOTE["A3"], 0.2), (NOTE["G3"], 0.4), (NOTE["A3"], 0.3)],
        # 3 — Minor-feeling fall
        [(NOTE["G4"], 0.2), (NOTE["E4"], 0.3), (NOTE["C4"], 0.2), (NOTE["A3"], 0.4)],
    ],
    "contemplative": [
        # 1 — Ends on 6th — unresolved
        [(NOTE["C4"], 0.3), (NOTE["E4"], 0.3), (NOTE["G4"], 0.3), (NOTE["A4"], 0.5)],
        # 2 — Gentle question mark
        [(NOTE["G4"], 0.25), (NOTE["A4"], 0.25), (NOTE["G4"], 0.25), (NOTE["E4"], 0.4)],
        # 3 — Curious ascending
        [(NOTE["E4"], 0.2), (NOTE["F4"], 0.2), (NOTE["G4"], 0.3), (NOTE["A4"], 0.4)],
    ],
    "neutral": [
        # 1 — Balanced, settled
        [(NOTE["C4"], 0.2), (NOTE["G4"], 0.2), (NOTE["E4"], 0.2), (NOTE["C4"], 0.4)],
        # 2 — Calm resolution
        [(NOTE["E4"], 0.25), (NOTE["G4"], 0.25), (NOTE["E4"], 0.25), (NOTE["C4"], 0.4)],
        # 3 — Gentle arch
        [(NOTE["G3"], 0.2), (NOTE["C4"], 0.2), (NOTE["E4"], 0.2), (NOTE["G4"], 0.3), (NOTE["C4"], 0.3)],
    ],
}

# ---------------------------------------------------------------------------
# Mood detection
# ---------------------------------------------------------------------------

def detect_mood(input_data: dict) -> str:
    if input_data.get("hook_event_name") == "Notification":
        return "contemplative"

    transcript_path = input_data.get("transcript_path", "")
    try:
        with open(transcript_path) as f:
            recent = f.read()[-4000:].lower()
        errors  = sum(recent.count(w) for w in ["error", "failed", "traceback", "exception", "cannot"])
        success = sum(recent.count(w) for w in ["complete", "success", "passed", "done", "implemented", "fixed"])
        if errors  > 3:
            return "oops"
        if success > 2:
            return "triumphant"
    except Exception:
        pass
    return "neutral"

# ---------------------------------------------------------------------------
# Synthesis
# ---------------------------------------------------------------------------

SAMPLE_RATE = 44100
AMPLITUDE   = 0.6      # master volume (0–1)
DECAY_RATE  = 4.0      # exponential decay constant per second
LEGATO      = 0.08     # overlap between notes (seconds)


def synthesize_note(freq: float, duration: float) -> list[float]:
    """
    Generate samples for one note.
    Timbre: fundamental + 0.5× octave + 0.25× perfect 5th.
    Envelope: exponential decay.
    """
    n_samples = int(SAMPLE_RATE * duration)
    fifth_freq = freq * 1.5  # perfect 5th above
    samples = []
    for i in range(n_samples):
        t = i / SAMPLE_RATE
        envelope = math.exp(-DECAY_RATE * t / duration)
        wave_val = (
            math.sin(2 * math.pi * freq * t)
            + 0.5 * math.sin(2 * math.pi * freq * 2 * t)   # octave
            + 0.25 * math.sin(2 * math.pi * fifth_freq * t) # 5th harmonic
        )
        samples.append(AMPLITUDE * envelope * wave_val / 1.75)  # normalise
    return samples


def synthesize_phrase(phrase: list[tuple[float, float]]) -> list[float]:
    """Concatenate notes with gentle legato overlap."""
    buffer: list[float] = []
    overlap_samples = int(SAMPLE_RATE * LEGATO)

    for freq, duration in phrase:
        note_samples = synthesize_note(freq, duration)
        if buffer and overlap_samples > 0:
            # Blend last `overlap_samples` of buffer with start of new note
            blend = min(overlap_samples, len(buffer), len(note_samples))
            for j in range(blend):
                buffer[-(blend - j)] += note_samples[j]
            buffer.extend(note_samples[blend:])
        else:
            buffer.extend(note_samples)

    return buffer


def write_wav(samples: list[float], path: str) -> None:
    """Write 16-bit mono WAV file."""
    with wave.open(path, "w") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        packed = struct.pack(f"<{len(samples)}h",
                             *[max(-32767, min(32767, int(s * 32767))) for s in samples])
        wf.writeframes(packed)

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    try:
        input_data = json.load(sys.stdin)
    except Exception:
        input_data = {}

    mood   = detect_mood(input_data)
    phrase = random.choice(PHRASES[mood])

    samples = synthesize_phrase(phrase)

    tmp_path = tempfile.mktemp(suffix=".wav")
    write_wav(samples, tmp_path)

    # Non-blocking playback — never stall Claude
    subprocess.Popen(
        ["afplay", tmp_path],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    sys.exit(0)


if __name__ == "__main__":
    main()
