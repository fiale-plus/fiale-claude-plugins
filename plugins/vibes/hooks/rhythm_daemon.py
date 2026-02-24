#!/usr/bin/env python3
"""
rhythm_daemon.py — Three-mode FluidSynth music engine for vibes plugin.

Direct noteon/noteoff with sleep_until for bar-accurate MIDI timing.
No sequencer API (pyfluidsynth 1.3.4 sequencer doesn't fire events on macOS).
Single-threaded bar loop — state checked between bars.

Modes:
  jazzy  — 63 BPM Chet Baker cool jazz  (16-bar Autumn Leaves cycle, Bb major)
  cafe   — 72 BPM Jobim minor bossa nova (16-bar Corcovado cycle, A minor)
  synth  — 100 BPM retro 80s synthwave  (16-bar E minor cycle, 3 synth channels)
"""

import json
import os
import random
import sys
import time

try:
    import fluidsynth
except ImportError:
    print("pyfluidsynth not installed — run plugins/vibes/bin/install.sh", file=sys.stderr)
    sys.exit(1)

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

STATE_FILE = os.path.expanduser("~/.claude/vibes.json")

SF2_SEARCH = [
    os.path.expanduser("~/.claude/vibes/GeneralUser_GS.sf2"),
    os.path.expanduser("~/.claude/vibes/MuseScore_General.sf2"),
    "/opt/homebrew/share/fluid-synth/sf2/VintageDreamsWaves-v2.sf2",
    "/usr/local/share/fluid-synth/sf2/VintageDreamsWaves-v2.sf2",
    "/usr/share/sounds/sf2/FluidR3_GM.sf2",
    "/usr/share/soundfonts/FluidR3_GM.sf2",
]

# ---------------------------------------------------------------------------
# Channels and GM programs
#
#   Jazzy: CH_0 = Acoustic Grand Piano  CH_1 = Acoustic Bass   CH_DRUMS
#   Cafe:  CH_0 = Acoustic Grand Piano  CH_1 = Acoustic Bass   CH_DRUMS
#   Synth: CH_0 = Lead Sawtooth  CH_1 = Synth Bass  CH_2 = Pad Sweep  CH_DRUMS
# ---------------------------------------------------------------------------

CH_0     = 0
CH_1     = 1
CH_2     = 2
CH_DRUMS = 9   # pyfluidsynth is zero-indexed; GM channel 10 = index 9

GM_ACOUSTIC_GRAND = 0
GM_ELECTRIC_PIANO = 4
GM_VIBRAPHONE     = 11   # clean, airy — cafe piano
GM_ACOUSTIC_BASS  = 32
GM_FINGER_BASS    = 33
GM_CHOIR_PAD      = 91   # Pad 4: Choir
GM_WARM_PAD       = 89   # Pad 2: Warm — stable, less lo-fi
GM_LEAD_SAWTOOTH  = 81   # Lead 2 (Sawtooth) — classic 80s buzz
GM_SYNTH_BASS_1   = 37   # Synth Bass 1 — punchy electronic bass
GM_PAD_SWEEP      = 95   # Pad 8 (Sweep) — lush evolving pad

DRUM_KICK         = 35   # Bass Drum 1
DRUM_BRUSH_SNARE  = 40   # Electric Snare (GM brush snare)
DRUM_CLOSED_HIHAT = 42   # Closed Hi-Hat
DRUM_PEDAL_HIHAT  = 44   # Pedal Hi-Hat ("chick" on 2 & 4)
DRUM_RIDE         = 51   # Ride Cymbal 1
DRUM_RIDE_BELL    = 53   # Ride Bell (brighter, section accent)
DRUM_SIDE_STICK   = 37   # Side Stick — bossa "toc" on beat 2
DRUM_KICK_HARD    = 36   # Bass Drum 1 — punchier 4-on-the-floor kick
DRUM_CLAP         = 39   # Hand Clap — layered with snare on 2 & 4
DRUM_COWBELL      = 56   # Cowbell — occasional 80s accent

# ---------------------------------------------------------------------------
# Timing helpers
# ---------------------------------------------------------------------------

JAZZY_BPM = 63
CAFE_BPM  = 72
SYNTH_BPM = 100   # 0.60 s/beat — energetic but not frantic


def sleep_until(t: float) -> None:
    """Sleep until time.perf_counter() reaches t."""
    remaining = t - time.perf_counter()
    if remaining > 0.0005:
        time.sleep(remaining)


# ---------------------------------------------------------------------------
# Velocity — Gaussian humanization
# ---------------------------------------------------------------------------

def _vel(base: int, spread: float = 0.12) -> int:
    """Gaussian velocity clamped to [1, 127]."""
    return max(1, min(127, int(random.gauss(base, base * spread))))


def _jazzy_roll() -> dict:
    r = random.random
    return {
        'piano_silent': r() < 0.08,   # 8%: entire bar is drums+bass only — a breath
        'skip_beat4':   r() < 0.20,   # 20%: no chord stab on beat 4
        'high_note':    r() < 0.22,   # 22%: float melody note (top+12) above comping
        'shell':        r() < 0.25,   # 25%: 3-note shell instead of 4-note close
    }


def _cafe_roll() -> dict:
    r = random.random
    return {
        'piano_silent': r() < 0.10,   # 10%: drums+bass only
        'sparse':       r() < 0.28,   # 28%: skip "and of 2" and "and of 4" stabs
        'high_float':   r() < 0.18,   # 18%: sustain a high chord tone from beat 2 to bar end
        'shell':        r() < 0.30,   # 30%: top 2 notes only (chord_notes[2:])
    }


def _synth_roll() -> dict:
    r = random.random
    return {
        'arp_silent':    r() < 0.06,  # 6%: pad+bass+drums only — atmospheric breath
        'arp_reverse':   r() < 0.18,  # 18%: descending arp instead of ascending
        'arp_octave_up': r() < 0.20,  # 20%: arp plays an octave higher
        'pad_drop':      r() < 0.12,  # 12%: no pad — stripped, driving feel
        'cowbell':       r() < 0.12,  # 12%: cowbell on beat 2 (very 80s)
        'half_time':     r() < 0.15,  # 15%: arp at quarter notes (spacious, floats)
        'arp_stutter':   r() < 0.15,  # 15%: repeat arp[0] on 'and of 1' (stutter)
    }


# ---------------------------------------------------------------------------
# Jazzy mode — 16-bar cycle, 4 sections × 4 bars (Chet Baker / Autumn Leaves)
#
# Key: Bb major — Bb2=46  C3=48  D3=50  Eb3=51  F2=41  G2=43  A2=45
#
# Chord voicings in 3rd-4th octave range (intimate, not booming):
#   Cm7    = [60,63,67,70]   C4 Eb4 G4  Bb4
#   F7     = [53,57,60,63]   F3 A3  C4  Eb4
#   Bbmaj7 = [58,62,65,69]   Bb3 D4 F4  A4
#   Ebmaj7 = [63,67,70,74]   Eb4 G4 Bb4 D5
#   Am7b5  = [57,60,63,67]   A3  C4 Eb4 G4
#   D7     = [62,66,69,72]   D4  F#4 A4 C5
#   Gm7    = [55,58,62,65]   G3  Bb3 D4 F4
#   G7     = [55,59,62,65]   G3  B3  D4 F4
#   Ebm7   = [63,66,70,73]   Eb4 Gb4 Bb4 Db5  ← borrowed minor iv colour
#
# Walking bass: root on beat 1, fifth (or 3rd) as passing tone on beat 3.
# ---------------------------------------------------------------------------

JAZZY_BARS = [
    # (chord_notes, bass_root, bass_fifth)

    # --- Section A: Autumn Leaves opening — ii-V-I-IV in Bb ---
    ([60, 63, 67, 70], 48, 55),   # Cm7    C4 Eb4 G4 Bb4  | C3→G3
    ([53, 57, 60, 63], 41, 48),   # F7     F3 A3  C4 Eb4  | F2→C3
    ([58, 62, 65, 69], 46, 53),   # Bbmaj7 Bb3 D4 F4 A4   | Bb2→F3
    ([63, 67, 70, 74], 51, 58),   # Ebmaj7 Eb4 G4 Bb4 D5  | Eb3→Bb3

    # --- Section B: Minor ii-V-I (borrowed) ---
    ([57, 60, 63, 67], 45, 51),   # Am7b5  A3 C4 Eb4 G4   | A2→Eb3
    ([62, 66, 69, 72], 50, 57),   # D7     D4 F#4 A4 C5   | D3→A3
    ([55, 58, 62, 65], 43, 50),   # Gm7    G3 Bb3 D4 F4   | G2→D3
    ([55, 58, 62, 65], 43, 50),   # Gm7    G3 Bb3 D4 F4   | G2→D3 (held)

    # --- Section C: I-VI-ii-V turnaround ---
    ([58, 62, 65, 69], 46, 53),   # Bbmaj7 Bb3 D4 F4 A4   | Bb2→F3
    ([55, 59, 62, 65], 43, 50),   # G7     G3 B3  D4 F4   | G2→D3
    ([60, 63, 67, 70], 48, 55),   # Cm7    C4 Eb4 G4 Bb4  | C3→G3
    ([53, 57, 60, 63], 41, 48),   # F7     F3 A3  C4 Eb4  | F2→C3

    # --- Section D: Chromatic landing (borrowed minor iv) ---
    ([58, 62, 65, 69], 46, 53),   # Bbmaj7 Bb3 D4 F4 A4   | Bb2→F3
    ([63, 67, 70, 74], 51, 58),   # Ebmaj7 Eb4 G4 Bb4 D5  | Eb3→Bb3
    ([63, 66, 70, 73], 51, 58),   # Ebm7   Eb4 Gb4 Bb4 Db5| Eb3→Bb3 ← chromatic colour
    ([58, 62, 65, 69], 46, 53),   # Bbmaj7 Bb3 D4 F4 A4   | Bb2→F3
]


def play_jazzy_bar(synth, bar_index: int, bar_start: float) -> None:
    """
    Block until all note events for one jazzy bar have fired.

    Drum layout (Chet Baker brush-kit swing):
      t=0.00 : kick + ride (+ ride bell on section start) + bass root
      t=0.50 : ride offbeat (swing "and" of 1)
      t=1.00 : chord + pedal hi-hat + snare + ride
      t=1.50 : ride offbeat (swing "and" of 2)
      t=1.85 : chord OFF + bass root OFF
      t=2.00 : ride + bass fifth
      t=2.50 : ride offbeat (swing "and" of 3)
      t=3.00 : chord + pedal hi-hat + snare + ride
      t=3.50 : ride offbeat (swing "and" of 4)
      t=3.85 : chord OFF + bass fifth OFF

    Piano vel 22–30 (barely-there Chet Baker style).
    """
    spb = 60.0 / JAZZY_BPM   # ≈ 0.952 s per beat

    chord_notes, bass_root, bass_fifth = JAZZY_BARS[bar_index % 16]
    section_start = (bar_index % 4 == 0)

    roll = _jazzy_roll()
    notes = chord_notes[:3] if roll['shell'] else chord_notes
    melody = chord_notes[-1] + 12  # top chord tone up an octave into ~octave 5

    # t=0 — kick + ride + bass root (ride bell accent on section starts)
    sleep_until(bar_start)
    synth.noteon(CH_DRUMS, DRUM_KICK, _vel(40 if section_start else 35))
    synth.noteon(CH_DRUMS, DRUM_RIDE, _vel(40 if section_start else 34))
    if section_start:
        synth.noteon(CH_DRUMS, DRUM_RIDE_BELL, _vel(44))
    synth.noteon(CH_1, bass_root, _vel(57))

    # t=0.5 SPB — ride offbeat ("and" of beat 1)
    sleep_until(bar_start + spb * 0.5)
    synth.noteon(CH_DRUMS, DRUM_RIDE, _vel(22))

    # t=1 SPB — chord + pedal hi-hat chick + snare + ride
    sleep_until(bar_start + spb)
    if not roll['piano_silent']:
        cv = _vel(26)
        for n in notes:
            synth.noteon(CH_0, n, cv)
        if roll['high_note']:
            synth.noteon(CH_0, melody, _vel(28))  # floats above comping, sustains to 3.85
    synth.noteon(CH_DRUMS, DRUM_PEDAL_HIHAT,  _vel(28))
    synth.noteon(CH_DRUMS, DRUM_BRUSH_SNARE,  _vel(36))
    synth.noteon(CH_DRUMS, DRUM_RIDE,         _vel(34))

    # t=1.5 SPB — ride offbeat ("and" of beat 2)
    sleep_until(bar_start + spb * 1.5)
    synth.noteon(CH_DRUMS, DRUM_RIDE, _vel(22))

    # t=1.85 SPB — release chord + bass root
    sleep_until(bar_start + spb * 1.85)
    for n in chord_notes:
        synth.noteoff(CH_0, n)
    synth.noteoff(CH_1, bass_root)

    # t=2 SPB — ride + bass fifth
    sleep_until(bar_start + spb * 2.0)
    synth.noteon(CH_DRUMS, DRUM_RIDE,  _vel(32))
    synth.noteon(CH_1,     bass_fifth, _vel(52))

    # t=2.5 SPB — ride offbeat ("and" of beat 3)
    sleep_until(bar_start + spb * 2.5)
    synth.noteon(CH_DRUMS, DRUM_RIDE, _vel(22))

    # t=3 SPB — chord + pedal hi-hat chick + snare + ride
    sleep_until(bar_start + spb * 3.0)
    if not roll['piano_silent'] and not roll['skip_beat4']:
        cv = _vel(24)
        for n in notes:
            synth.noteon(CH_0, n, cv)
    synth.noteon(CH_DRUMS, DRUM_PEDAL_HIHAT,  _vel(26))
    synth.noteon(CH_DRUMS, DRUM_BRUSH_SNARE,  _vel(34))
    synth.noteon(CH_DRUMS, DRUM_RIDE,         _vel(32))

    # t=3.5 SPB — ride offbeat ("and" of beat 4)
    sleep_until(bar_start + spb * 3.5)
    synth.noteon(CH_DRUMS, DRUM_RIDE, _vel(22))

    # t=3.85 SPB — release chord + bass fifth
    sleep_until(bar_start + spb * 3.85)
    for n in chord_notes:
        synth.noteoff(CH_0, n)
    if roll['high_note']:
        synth.noteoff(CH_0, melody)
    synth.noteoff(CH_1, bass_fifth)


# ---------------------------------------------------------------------------
# Cafe mode — 16-bar cycle, 4 sections × 4 bars (Jobim / Corcovado)
#
# Key: A minor — A2=45  B2=47  D2=38  E2=40  F2=41  G2=43  F#2=42
#
# Chord voicings:
#   Am7    = [57,60,64,67]  A3  C4  E4  G4
#   D7     = [62,66,69,72]  D4  F#4 A4  C5
#   Gmaj7  = [55,59,62,66]  G3  B3  D4  F#4
#   Cmaj7  = [60,64,67,71]  C4  E4  G4  B4
#   F#m7b5 = [54,57,60,64]  F#3 A3  C4  E4
#   B7     = [59,63,66,69]  B3  D#4 F#4 A4
#   Em7    = [52,55,59,62]  E3  G3  B3  D4
#   E7     = [52,56,59,62]  E3  G#3 B3  D4
#   Fmaj7  = [53,57,60,64]  F3  A3  C4  E4
#   Dm7    = [50,53,57,60]  D3  F3  A3  C4
#   Bm7b5  = [47,50,53,57]  B2  D3  F3  A3
#
# Bass: root on beat 1, walking/passing note on beat 3 (t=2.00 SPB).
# ---------------------------------------------------------------------------

CAFE_CHORD_SEQ = [
    # (chord_notes, bass_root, bass_walk)

    # --- Section A: Corcovado feel — i-IV7-bVII-bIII ---
    ([57, 60, 64, 67], 45, 52),   # Am7    A2→E3
    ([62, 66, 69, 72], 38, 45),   # D7     D2→A2
    ([55, 59, 62, 66], 43, 50),   # Gmaj7  G2→D3
    ([60, 64, 67, 71], 48, 55),   # Cmaj7  C3→G3

    # --- Section B: Minor ii-V-i (Jobim chromatic descent) ---
    ([54, 57, 60, 64], 42, 47),   # F#m7b5 F#2→B2
    ([59, 63, 66, 69], 47, 54),   # B7     B2→F#3
    ([52, 55, 59, 62], 40, 47),   # Em7    E2→B2
    ([52, 56, 59, 62], 40, 47),   # E7     E2→B2  ← V7, tension before return

    # --- Section C: Descending bass / Black Orpheus ---
    ([57, 60, 64, 67], 45, 52),   # Am7    A2→E3
    ([57, 60, 64, 67], 43, 41),   # Am7/G  G2→F2  ← same chord, bass drops to G
    ([53, 57, 60, 64], 41, 40),   # Fmaj7  F2→E2  (chromatic approach)
    ([52, 56, 59, 62], 40, 47),   # E7     E2→B2

    # --- Section D: Resolution cadence ---
    ([57, 60, 64, 67], 45, 52),   # Am7    A2→E3
    ([50, 53, 57, 60], 38, 45),   # Dm7    D2→A2
    ([47, 50, 53, 57], 47, 54),   # Bm7b5  B2→F#3
    ([52, 56, 59, 62], 40, 47),   # E7     E2→B2  ← unresolved V7, loops to Am7
]


def play_cafe_bar(synth, bar_index: int, bar_start: float) -> None:
    """
    Block until all note events for one cafe (bossa nova) bar have fired.

    Bossa nova rhythm pattern (Jobim / "Corcovado" feel):
      t=0.00 SPB : kick + hihat + bass root + chord (beat 1)
      t=0.50 SPB : chord hit (and of 1) ← characteristic bossa offbeat
      t=1.00 SPB : side stick + hihat + chord (beat 2)
      t=1.50 SPB : chord hit (and of 2) ← very characteristic
      t=2.00 SPB : hihat + bass passing note — chord off
      t=2.50 SPB : chord hit (and of 3)
      t=3.00 SPB : hihat + chord (beat 4)
      t=3.50 SPB : chord hit (and of 4)
      t=3.85 SPB : all notes off

    Chord vel 22–35 (bossa piano is subtle). Hihat vel 15–20.
    Side stick vel 32–38. Kick vel 20–25.
    """
    spb = 60.0 / CAFE_BPM   # ≈ 0.833 s per beat

    chord_notes, bass_root, bass_walk = CAFE_CHORD_SEQ[bar_index % 16]

    roll = _cafe_roll()
    notes = chord_notes[2:] if roll['shell'] else chord_notes
    melody = chord_notes[-1] + 12  # top chord tone up an octave, floats above comping

    # t=0.00 — kick + hihat + bass root + chord beat 1
    sleep_until(bar_start)
    synth.noteon(CH_DRUMS, DRUM_KICK,         _vel(22))
    synth.noteon(CH_DRUMS, DRUM_CLOSED_HIHAT, _vel(18))
    synth.noteon(CH_1, bass_root, _vel(48))
    if not roll['piano_silent']:
        cv = _vel(30)
        for n in notes:
            synth.noteon(CH_0, n, cv)

    # t=0.50 — chord hit (and of 1)
    sleep_until(bar_start + spb * 0.5)
    if not roll['piano_silent']:
        for n in chord_notes:
            synth.noteoff(CH_0, n)
        cv = _vel(26)
        for n in notes:
            synth.noteon(CH_0, n, cv)

    # t=1.00 — side stick + hihat + chord beat 2
    sleep_until(bar_start + spb)
    synth.noteon(CH_DRUMS, DRUM_SIDE_STICK,   _vel(35))
    synth.noteon(CH_DRUMS, DRUM_CLOSED_HIHAT, _vel(17))
    if not roll['piano_silent']:
        for n in chord_notes:
            synth.noteoff(CH_0, n)
        cv = _vel(28)
        for n in notes:
            synth.noteon(CH_0, n, cv)
        if roll['high_float']:
            synth.noteon(CH_0, melody, _vel(26))  # sustains to bar end

    # t=1.50 — chord hit (and of 2)
    sleep_until(bar_start + spb * 1.5)
    synth.noteoff(CH_1, bass_root)
    if not roll['piano_silent'] and not roll['sparse']:
        for n in chord_notes:
            synth.noteoff(CH_0, n)
        cv = _vel(24)
        for n in notes:
            synth.noteon(CH_0, n, cv)

    # t=2.00 — hihat + bass passing note; chord off
    sleep_until(bar_start + spb * 2.0)
    synth.noteon(CH_DRUMS, DRUM_CLOSED_HIHAT, _vel(16))
    synth.noteon(CH_1, bass_walk, _vel(42))
    for n in chord_notes:
        synth.noteoff(CH_0, n)

    # t=2.50 — chord hit (and of 3)
    sleep_until(bar_start + spb * 2.5)
    if not roll['piano_silent']:
        cv = _vel(26)
        for n in notes:
            synth.noteon(CH_0, n, cv)

    # t=3.00 — hihat + chord beat 4
    sleep_until(bar_start + spb * 3.0)
    synth.noteon(CH_DRUMS, DRUM_CLOSED_HIHAT, _vel(17))
    for n in chord_notes:
        synth.noteoff(CH_0, n)
    if not roll['piano_silent']:
        cv = _vel(28)
        for n in notes:
            synth.noteon(CH_0, n, cv)

    # t=3.50 — chord hit (and of 4)
    sleep_until(bar_start + spb * 3.5)
    if not roll['piano_silent'] and not roll['sparse']:
        for n in chord_notes:
            synth.noteoff(CH_0, n)
        cv = _vel(24)
        for n in notes:
            synth.noteon(CH_0, n, cv)

    # t=3.85 — all notes off
    sleep_until(bar_start + spb * 3.85)
    for n in chord_notes:
        synth.noteoff(CH_0, n)
    if roll['high_float']:
        synth.noteoff(CH_0, melody)
    synth.noteoff(CH_1, bass_walk)


# ---------------------------------------------------------------------------
# Synth mode — 16-bar cycle, 4 sections × 4 bars (retro 80s synthwave)
#
# Key: E minor (Aeolian) — E2=40  B2=47  D2=38  G2=43  A2=45  F#2=42  C2=36
#
# Style: Kavinsky / Drive OST feel — 8th-note sawtooth arp over lush pad
#
# Chord voicings — arp in mid-high register, pad wide-spread below:
#   Em7    arp=[64,67,71,74]  E4 G4 B4 D5   pad=[52,59,64,71]  E3 B3 E4 B4
#   Cmaj7  arp=[60,64,67,71]  C4 E4 G4 B4   pad=[48,55,60,67]  C3 G3 C4 G4
#   G      arp=[62,67,71,74]  D4 G4 B4 D5   pad=[55,62,67,74]  G3 D4 G4 D5
#   D      arp=[62,66,69,74]  D4 F#4 A4 D5  pad=[50,57,62,69]  D3 A3 D4 A4
#   Am7    arp=[57,60,64,67]  A3 C4 E4 G4   pad=[45,52,57,64]  A2 E3 A3 E4
#   F      arp=[60,65,69,72]  C4 F4 A4 C5   pad=[53,60,65,72]  F3 C4 F4 C5  ← borrowed bVI
#   C      arp=[60,64,67,72]  C4 E4 G4 C5   pad=[48,55,60,67]  C3 G3 C4 G4
#   B7     arp=[59,63,66,71]  B3 D#4 F#4 B4 pad=[47,59,63,71]  B2 B3 D#4 B4 ← V7
#   Gmaj7  arp=[62,67,71,74]  D4 G4 B4 D5   pad=[55,62,67,71]  G3 D4 G4 B4  ← maj7 colour
#   D/F#   arp=[62,66,69,74]  D4 F#4 A4 D5  pad=[50,57,62,69]  D3 A3 D4 A4  ← chromatic bass
#
# Three channels:
#   CH_0 = Lead Sawtooth — 8th-note arpeggio (mid-high register)
#   CH_1 = Synth Bass 1  — root on beat 1, passing note on beat 3
#   CH_2 = Pad Sweep     — wide-spread voicing, held through bar
# ---------------------------------------------------------------------------

SYNTH_BARS = [
    # (arp_notes, pad_notes, bass_root, bass_pass)

    # --- Section A: i-VI-III-VII (the iconic synthwave loop) ---
    ([64, 67, 71, 74], [52, 59, 64, 71], 40, 47),   # Em7    E2→B2
    ([60, 64, 67, 71], [48, 55, 60, 67], 36, 43),   # Cmaj7  C2→G2
    ([62, 67, 71, 74], [55, 62, 67, 74], 43, 50),   # G      G2→D3
    ([62, 66, 69, 74], [50, 57, 62, 69], 38, 45),   # D      D2→A2

    # --- Section B: iv-bVI-I-V7 (borrowed chords — darker, more cinematic) ---
    ([57, 60, 64, 67], [45, 52, 57, 64], 45, 52),   # Am7    A2→E3
    ([60, 65, 69, 72], [53, 60, 65, 72], 41, 48),   # F      F2→C3  ← borrowed
    ([60, 64, 67, 72], [48, 55, 60, 67], 36, 43),   # C      C2→G2
    ([59, 63, 66, 71], [47, 59, 63, 71], 47, 54),   # B7     B2→F#3 ← V7 tension

    # --- Section C: i-VI-IIImaj7-VII/III (evolved A, bass movement) ---
    ([64, 67, 71, 74], [52, 59, 64, 71], 40, 47),   # Em7    E2→B2
    ([60, 64, 67, 71], [48, 55, 60, 67], 36, 43),   # Cmaj7  C2→G2
    ([62, 67, 71, 74], [55, 62, 67, 71], 43, 47),   # Gmaj7  G2→B2  ← maj7, walks to B
    ([62, 66, 69, 74], [50, 57, 62, 69], 42, 45),   # D/F#   F#2→A2 ← bass pedal shift

    # --- Section D: iv-III-VII-i (resolution home) ---
    ([57, 60, 64, 67], [45, 52, 57, 64], 45, 52),   # Am7    A2→E3
    ([62, 67, 71, 74], [55, 62, 67, 74], 43, 50),   # G      G2→D3
    ([62, 66, 69, 74], [50, 57, 62, 69], 38, 45),   # D      D2→A2
    ([64, 67, 71, 74], [52, 59, 64, 71], 40, 47),   # Em7    E2→B2  ← home
]


def play_synth_bar(synth, bar_index: int, bar_start: float) -> None:
    """
    Block until all note events for one synthwave bar have fired.

    4-on-the-floor drums + 8th-note lead arp + sweep pad + synth bass.
    Bar = 2.4 s at 100 BPM (SPB = 0.60 s), 9 sleep_until calls.

      t=0.00 : Kick + HiHat + bass_root ON + pad ON + arp[0] ON
      t=0.50 : arp[0] OFF + HiHat + arp[1] ON
      t=1.00 : arp[1] OFF + Kick + Snare + Clap + HiHat [+Cowbell] + arp[2] ON
      t=1.50 : arp[2] OFF + HiHat + arp[3] ON + bass_root OFF + bass_pass ON
      t=2.00 : arp[3] OFF + Kick + HiHat + arp[0] ON (2nd pass)
      t=2.50 : arp[0] OFF + HiHat + arp[1] ON
      t=3.00 : arp[1] OFF + Kick + Snare + Clap + HiHat + arp[2] ON
      t=3.50 : arp[2] OFF + HiHat + arp[3] ON
      t=3.85 : arp[3] OFF + pad OFF + bass_pass OFF

    half_time overrides arp_stutter when both roll.
    """
    spb = 60.0 / SYNTH_BPM   # 0.60 s per beat; bar = 2.4 s

    arp_notes, pad_notes, bass_root, bass_pass = SYNTH_BARS[bar_index % 16]
    section_start = (bar_index % 4 == 0)
    roll = _synth_roll()

    arp = list(reversed(arp_notes)) if roll['arp_reverse'] else list(arp_notes)
    if roll['arp_octave_up']:
        arp = [n + 12 for n in arp]

    kick_v = 60 if section_start else 52
    pad_v  = 38 if section_start else 32

    # ---- t=0.00 : beat 1 ------------------------------------------------
    sleep_until(bar_start)
    synth.noteon(CH_DRUMS, DRUM_KICK_HARD,    _vel(kick_v))
    synth.noteon(CH_DRUMS, DRUM_CLOSED_HIHAT, _vel(24))
    synth.noteon(CH_1, bass_root, _vel(68))
    if not roll['pad_drop']:
        for n in pad_notes:
            synth.noteon(CH_2, n, _vel(pad_v, 0.08))
    if not roll['arp_silent']:
        synth.noteon(CH_0, arp[0], _vel(65))

    # ---- t=0.50 : "and" of 1 --------------------------------------------
    sleep_until(bar_start + spb * 0.5)
    synth.noteon(CH_DRUMS, DRUM_CLOSED_HIHAT, _vel(21))
    if not roll['arp_silent'] and not roll['half_time']:
        synth.noteoff(CH_0, arp[0])
        note_1e = arp[0] if roll['arp_stutter'] else arp[1]
        synth.noteon(CH_0, note_1e, _vel(60))

    # ---- t=1.00 : beat 2 ------------------------------------------------
    sleep_until(bar_start + spb * 1.0)
    synth.noteon(CH_DRUMS, DRUM_KICK_HARD,    _vel(52))
    synth.noteon(CH_DRUMS, DRUM_BRUSH_SNARE,  _vel(70))
    synth.noteon(CH_DRUMS, DRUM_CLAP,         _vel(60))
    synth.noteon(CH_DRUMS, DRUM_CLOSED_HIHAT, _vel(22))
    if roll['cowbell']:
        synth.noteon(CH_DRUMS, DRUM_COWBELL, _vel(42))
    if not roll['arp_silent']:
        if roll['half_time']:
            synth.noteoff(CH_0, arp[0])
            synth.noteon(CH_0, arp[1], _vel(62))
        else:
            prev = arp[0] if roll['arp_stutter'] else arp[1]
            synth.noteoff(CH_0, prev)
            synth.noteon(CH_0, arp[2], _vel(62))

    # ---- t=1.50 : "and" of 2 + bass swap --------------------------------
    sleep_until(bar_start + spb * 1.5)
    synth.noteon(CH_DRUMS, DRUM_CLOSED_HIHAT, _vel(20))
    synth.noteoff(CH_1, bass_root)
    synth.noteon(CH_1,  bass_pass, _vel(68))
    if not roll['arp_silent'] and not roll['half_time']:
        synth.noteoff(CH_0, arp[2])
        synth.noteon(CH_0, arp[3], _vel(58))

    # ---- t=2.00 : beat 3 (2nd arp pass) ---------------------------------
    sleep_until(bar_start + spb * 2.0)
    synth.noteon(CH_DRUMS, DRUM_KICK_HARD,    _vel(52))
    synth.noteon(CH_DRUMS, DRUM_CLOSED_HIHAT, _vel(23))
    if not roll['arp_silent']:
        if roll['half_time']:
            synth.noteoff(CH_0, arp[1])
            synth.noteon(CH_0, arp[2], _vel(64))
        else:
            synth.noteoff(CH_0, arp[3])
            synth.noteon(CH_0, arp[0], _vel(65))

    # ---- t=2.50 : "and" of 3 (2nd pass — no stutter) -------------------
    sleep_until(bar_start + spb * 2.5)
    synth.noteon(CH_DRUMS, DRUM_CLOSED_HIHAT, _vel(21))
    if not roll['arp_silent'] and not roll['half_time']:
        synth.noteoff(CH_0, arp[0])
        synth.noteon(CH_0, arp[1], _vel(60))

    # ---- t=3.00 : beat 4 ------------------------------------------------
    sleep_until(bar_start + spb * 3.0)
    synth.noteon(CH_DRUMS, DRUM_KICK_HARD,    _vel(52))
    synth.noteon(CH_DRUMS, DRUM_BRUSH_SNARE,  _vel(70))
    synth.noteon(CH_DRUMS, DRUM_CLAP,         _vel(60))
    synth.noteon(CH_DRUMS, DRUM_CLOSED_HIHAT, _vel(22))
    if not roll['arp_silent']:
        if roll['half_time']:
            synth.noteoff(CH_0, arp[2])
            synth.noteon(CH_0, arp[3], _vel(61))
        else:
            synth.noteoff(CH_0, arp[1])
            synth.noteon(CH_0, arp[2], _vel(62))

    # ---- t=3.50 : "and" of 4 --------------------------------------------
    sleep_until(bar_start + spb * 3.5)
    synth.noteon(CH_DRUMS, DRUM_CLOSED_HIHAT, _vel(20))
    if not roll['arp_silent'] and not roll['half_time']:
        synth.noteoff(CH_0, arp[2])
        synth.noteon(CH_0, arp[3], _vel(58))

    # ---- t=3.85 : cleanup -----------------------------------------------
    sleep_until(bar_start + spb * 3.85)
    if not roll['arp_silent']:
        for n in arp:
            synth.noteoff(CH_0, n)
    if not roll['pad_drop']:
        for n in pad_notes:
            synth.noteoff(CH_2, n)
    synth.noteoff(CH_1, bass_pass)


# ---------------------------------------------------------------------------
# One-shot bars — played once on Stop or AskUserQuestion events
#
# "stop"     — arpeggio UP on beat 2, DOWN on beat 4 (resolved, "I'm done")
# "question" — arpeggio UP on beat 2, top note echoes on beat 4 (unresolved)
#
# Drums and bass unchanged in both so they sit in the groove.
# ---------------------------------------------------------------------------

def play_jazzy_oneshot(synth, bar_index: int, bar_start: float, variant: str = "stop") -> None:
    spb = 60.0 / JAZZY_BPM
    chord_notes, bass_root, bass_fifth = JAZZY_BARS[bar_index % 16]

    # t=0 — kick + ride + bass root (no piano on beat 1)
    sleep_until(bar_start)
    synth.noteon(CH_DRUMS, DRUM_KICK, _vel(50))
    synth.noteon(CH_DRUMS, DRUM_RIDE, _vel(46))
    synth.noteon(CH_1, bass_root, _vel(57))

    # t=0.5 — ride offbeat
    sleep_until(bar_start + spb * 0.5)
    synth.noteon(CH_DRUMS, DRUM_RIDE, _vel(30))

    # t=1 — arpeggio UP: low→high, one note per ~100ms
    sleep_until(bar_start + spb)
    synth.noteon(CH_DRUMS, DRUM_BRUSH_SNARE, _vel(58))
    synth.noteon(CH_DRUMS, DRUM_RIDE,        _vel(54))
    for i, n in enumerate(chord_notes):
        sleep_until(bar_start + spb + i * 0.10)
        synth.noteon(CH_0, n, _vel(68 - i * 3))  # bold, slight taper as it rises

    # t=1.5 — ride offbeat
    sleep_until(bar_start + spb * 1.5)
    synth.noteon(CH_DRUMS, DRUM_RIDE, _vel(30))

    # t=1.85 — release arpeggio + bass root
    sleep_until(bar_start + spb * 1.85)
    for n in chord_notes:
        synth.noteoff(CH_0, n)
    synth.noteoff(CH_1, bass_root)

    # t=2 — ride + bass fifth
    sleep_until(bar_start + spb * 2.0)
    synth.noteon(CH_DRUMS, DRUM_RIDE, _vel(42))
    synth.noteon(CH_1, bass_fifth, _vel(52))

    # t=2.5 — ride offbeat
    sleep_until(bar_start + spb * 2.5)
    synth.noteon(CH_DRUMS, DRUM_RIDE, _vel(30))

    # t=3 — resolved: arpeggio DOWN  /  question: top note echo (unresolved)
    sleep_until(bar_start + spb * 3.0)
    synth.noteon(CH_DRUMS, DRUM_BRUSH_SNARE, _vel(55))
    synth.noteon(CH_DRUMS, DRUM_RIDE,        _vel(52))
    if variant == "question":
        # just the top note again, soft — leaves it hanging
        synth.noteon(CH_0, chord_notes[-1], _vel(48))
    else:
        for i, n in enumerate(reversed(chord_notes)):
            sleep_until(bar_start + spb * 3.0 + i * 0.10)
            synth.noteon(CH_0, n, _vel(62 - i * 3))

    # t=3.5 — ride offbeat
    sleep_until(bar_start + spb * 3.5)
    synth.noteon(CH_DRUMS, DRUM_RIDE, _vel(30))

    # t=3.85 — release + bass fifth off
    sleep_until(bar_start + spb * 3.85)
    for n in chord_notes:
        synth.noteoff(CH_0, n)
    synth.noteoff(CH_1, bass_fifth)


def play_cafe_oneshot(synth, bar_index: int, bar_start: float, variant: str = "stop") -> None:
    """
    One-shot cafe bar: same drums/bass as normal, piano arpeggios instead of stabs.
    """
    spb = 60.0 / CAFE_BPM
    chord_notes, bass_root, bass_walk = CAFE_CHORD_SEQ[bar_index % 16]
    # Play arpeggio one octave below so it cuts through instead of blending
    arp_notes = [n - 12 for n in chord_notes]

    # t=0 — kick + hihat + bass root; arpeggio UP in mid-range
    sleep_until(bar_start)
    synth.noteon(CH_DRUMS, DRUM_KICK,         _vel(22))
    synth.noteon(CH_DRUMS, DRUM_CLOSED_HIHAT, _vel(18))
    synth.noteon(CH_1, bass_root, _vel(48))
    for i, n in enumerate(arp_notes):
        sleep_until(bar_start + i * 0.09)
        synth.noteon(CH_0, n, _vel(78 - i * 5))

    # t=0.6 — piano OFF
    sleep_until(bar_start + spb * 0.60)
    for n in arp_notes:
        synth.noteoff(CH_0, n)

    # t=0.95 — bass root OFF
    sleep_until(bar_start + spb * 0.95)
    synth.noteoff(CH_1, bass_root)

    # t=1 — hihat
    sleep_until(bar_start + spb)
    synth.noteon(CH_DRUMS, DRUM_CLOSED_HIHAT, _vel(17))

    # t=2 — hihat + bass walk
    sleep_until(bar_start + spb * 2.0)
    synth.noteon(CH_DRUMS, DRUM_CLOSED_HIHAT, _vel(16))
    synth.noteon(CH_1, bass_walk, _vel(42))

    # t=2.95 — bass walk OFF
    sleep_until(bar_start + spb * 2.95)
    synth.noteoff(CH_1, bass_walk)

    # t=3 — hihat; question: top note echo / stop: arpeggio DOWN
    sleep_until(bar_start + spb * 3.0)
    synth.noteon(CH_DRUMS, DRUM_CLOSED_HIHAT, _vel(16))
    if variant == "question":
        synth.noteon(CH_0, arp_notes[-1], _vel(72))
    else:
        for i, n in enumerate(reversed(arp_notes)):
            sleep_until(bar_start + spb * 3.0 + i * 0.09)
            synth.noteon(CH_0, n, _vel(70 - i * 5))

    # t=3.85 — piano OFF
    sleep_until(bar_start + spb * 3.85)
    for n in arp_notes:
        synth.noteoff(CH_0, n)


def play_synth_oneshot(synth, bar_index: int, bar_start: float, variant: str = "stop") -> None:
    """
    One-shot synth bar: pad held throughout, arp sweeps on beats 2 and 4.

    "stop"     — sweep UP on beat 2, sweep DOWN on beat 4 (resolved)
    "question" — sweep UP on beat 2, top note only on beat 4 (unresolved)
    """
    spb = 60.0 / SYNTH_BPM
    arp_notes, pad_notes, bass_root, bass_pass = SYNTH_BARS[bar_index % 16]

    # t=0 — kick + hihat + bass + pad (no arp on beat 1)
    sleep_until(bar_start)
    synth.noteon(CH_DRUMS, DRUM_KICK_HARD,    _vel(60))
    synth.noteon(CH_DRUMS, DRUM_CLOSED_HIHAT, _vel(24))
    synth.noteon(CH_1, bass_root, _vel(68))
    for n in pad_notes:
        synth.noteon(CH_2, n, _vel(38, 0.08))

    # t=0.5 — hihat
    sleep_until(bar_start + spb * 0.5)
    synth.noteon(CH_DRUMS, DRUM_CLOSED_HIHAT, _vel(21))

    # t=1.0 — beat 2: snare + clap + arp sweep UP
    sleep_until(bar_start + spb * 1.0)
    synth.noteon(CH_DRUMS, DRUM_KICK_HARD,    _vel(52))
    synth.noteon(CH_DRUMS, DRUM_BRUSH_SNARE,  _vel(70))
    synth.noteon(CH_DRUMS, DRUM_CLAP,         _vel(60))
    synth.noteon(CH_DRUMS, DRUM_CLOSED_HIHAT, _vel(22))
    for i, n in enumerate(arp_notes):
        sleep_until(bar_start + spb + i * 0.10)
        synth.noteon(CH_0, n, _vel(70 - i * 3))

    # t=1.85 — arp off + bass root off
    sleep_until(bar_start + spb * 1.85)
    for n in arp_notes:
        synth.noteoff(CH_0, n)
    synth.noteoff(CH_1, bass_root)

    # t=2.0 — beat 3: kick + hihat + bass pass
    sleep_until(bar_start + spb * 2.0)
    synth.noteon(CH_DRUMS, DRUM_KICK_HARD,    _vel(52))
    synth.noteon(CH_DRUMS, DRUM_CLOSED_HIHAT, _vel(23))
    synth.noteon(CH_1, bass_pass, _vel(68))

    # t=2.5 — hihat
    sleep_until(bar_start + spb * 2.5)
    synth.noteon(CH_DRUMS, DRUM_CLOSED_HIHAT, _vel(21))

    # t=3.0 — beat 4: snare + clap + arp (down or question)
    sleep_until(bar_start + spb * 3.0)
    synth.noteon(CH_DRUMS, DRUM_KICK_HARD,    _vel(52))
    synth.noteon(CH_DRUMS, DRUM_BRUSH_SNARE,  _vel(70))
    synth.noteon(CH_DRUMS, DRUM_CLAP,         _vel(60))
    synth.noteon(CH_DRUMS, DRUM_CLOSED_HIHAT, _vel(22))
    if variant == "question":
        synth.noteon(CH_0, arp_notes[-1], _vel(52))  # top note only, soft — hanging
    else:
        for i, n in enumerate(reversed(arp_notes)):
            sleep_until(bar_start + spb * 3.0 + i * 0.10)
            synth.noteon(CH_0, n, _vel(68 - i * 3))

    # t=3.5 — hihat
    sleep_until(bar_start + spb * 3.5)
    synth.noteon(CH_DRUMS, DRUM_CLOSED_HIHAT, _vel(20))

    # t=3.85 — all off
    sleep_until(bar_start + spb * 3.85)
    for n in arp_notes:
        synth.noteoff(CH_0, n)
    for n in pad_notes:
        synth.noteoff(CH_2, n)
    synth.noteoff(CH_1, bass_pass)


# ---------------------------------------------------------------------------
# Mode setup
# ---------------------------------------------------------------------------

def setup_jazzy(synth, sfid: int) -> None:
    synth.program_select(CH_0,     sfid,   0, GM_ACOUSTIC_GRAND)
    synth.program_select(CH_1,     sfid,   0, GM_ACOUSTIC_BASS)
    synth.program_select(CH_DRUMS, sfid, 128, 0)
    synth.setting("synth.reverb.active", "yes")
    synth.set_reverb(roomsize=0.25, damping=0.55, width=0.4, level=0.22)


def setup_cafe(synth, sfid: int) -> None:
    synth.program_select(CH_0,     sfid,   0, GM_ACOUSTIC_GRAND)
    synth.program_select(CH_1,     sfid,   0, GM_ACOUSTIC_BASS)
    synth.program_select(CH_DRUMS, sfid, 128, 0)
    synth.setting("synth.reverb.active", "yes")
    synth.set_reverb(roomsize=0.25, damping=0.55, width=0.4, level=0.22)


def setup_synth(synth, sfid: int) -> None:
    synth.program_select(CH_0,     sfid,   0, GM_LEAD_SAWTOOTH)
    synth.program_select(CH_1,     sfid,   0, GM_SYNTH_BASS_1)
    synth.program_select(CH_2,     sfid,   0, GM_PAD_SWEEP)
    synth.program_select(CH_DRUMS, sfid, 128, 0)
    synth.setting("synth.reverb.active", "yes")
    synth.set_reverb(roomsize=0.45, damping=0.35, width=0.65, level=0.30)


def all_notes_off(synth) -> None:
    for ch in [CH_0, CH_1, CH_2, CH_DRUMS]:
        for note in range(128):
            synth.noteoff(ch, note)


# ---------------------------------------------------------------------------
# State helpers
# ---------------------------------------------------------------------------

def read_state() -> dict:
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except Exception:
        return {}


def write_state_fields(**fields) -> None:
    try:
        state = read_state()
        state.update(fields)
        with open(STATE_FILE, "w") as f:
            json.dump(state, f)
    except Exception:
        pass


# ---------------------------------------------------------------------------
# Fade out
# ---------------------------------------------------------------------------

def fade_out(synth, duration: float = 0.5, steps: int = 20) -> None:
    initial = 0.6
    for i in range(steps):
        try:
            synth.setting("synth.gain", max(0.0, initial * (1.0 - (i + 1) / steps)))
        except Exception:
            pass
        time.sleep(duration / steps)
    all_notes_off(synth)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    state = read_state()
    if not state.get("enabled", False):
        return

    # --- Audio ---
    synth = fluidsynth.Synth(gain=0.6)
    synth.start(driver="coreaudio")

    sfid = -1
    for p in SF2_SEARCH:
        if not os.path.exists(p):
            continue
        sfid = synth.sfload(p)
        if sfid != -1:
            break

    if sfid == -1:
        print("No SoundFont found. Run plugins/vibes/bin/install.sh", file=sys.stderr)
        synth.delete()
        sys.exit(1)

    # --- Initial mode ---
    current_mode = state.get("mode", "jazzy")
    if current_mode not in ("jazzy", "cafe", "synth"):
        current_mode = "jazzy"

    if current_mode == "jazzy":
        setup_jazzy(synth, sfid)
    elif current_mode == "cafe":
        setup_cafe(synth, sfid)
    else:
        setup_synth(synth, sfid)

    write_state_fields(daemon_pid=os.getpid())

    bar_index = 0

    try:
        while True:
            state = read_state()
            if not state.get("enabled", False):
                break

            new_mode = state.get("mode", "jazzy")
            if new_mode not in ("jazzy", "cafe", "synth"):
                new_mode = "jazzy"

            # Mode transition — silence, reconfigure, reset bar counter
            if new_mode != current_mode:
                all_notes_off(synth)
                current_mode = new_mode
                if current_mode == "jazzy":
                    setup_jazzy(synth, sfid)
                elif current_mode == "cafe":
                    setup_cafe(synth, sfid)
                else:
                    setup_synth(synth, sfid)
                bar_index = 0

            one_shot = state.get("one_shot", False)
            if one_shot:
                write_state_fields(one_shot=False)

            if current_mode == "jazzy":
                bpm = JAZZY_BPM
            elif current_mode == "cafe":
                bpm = CAFE_BPM
            else:
                bpm = SYNTH_BPM
            bar_dur   = 4.0 * 60.0 / bpm
            bar_start = time.perf_counter()

            variant = one_shot if isinstance(one_shot, str) else "stop"
            if one_shot and current_mode == "jazzy":
                play_jazzy_oneshot(synth, bar_index, bar_start, variant)
            elif one_shot and current_mode == "cafe":
                play_cafe_oneshot(synth, bar_index, bar_start, variant)
            elif one_shot and current_mode == "synth":
                play_synth_oneshot(synth, bar_index, bar_start, variant)
            elif current_mode == "jazzy":
                play_jazzy_bar(synth, bar_index, bar_start)
            elif current_mode == "cafe":
                play_cafe_bar(synth, bar_index, bar_start)
            else:
                play_synth_bar(synth, bar_index, bar_start)

            # Sleep to exact bar boundary
            sleep_until(bar_start + bar_dur - 0.002)
            bar_index += 1

    except KeyboardInterrupt:
        pass
    finally:
        fade_out(synth)
        synth.delete()


if __name__ == "__main__":
    main()
