#!/usr/bin/env python3
"""
rhythm_daemon.py — Two-mode FluidSynth music engine for vibes plugin.

Direct noteon/noteoff with sleep_until for bar-accurate MIDI timing.
No sequencer API (pyfluidsynth 1.3.4 sequencer doesn't fire events on macOS).
Single-threaded bar loop — state checked between bars.

Modes:
  jazzy  — 62 BPM dinner jazz   (32-bar AABA cycle through 4 classic progressions)
  cafe   — 74 BPM Balearic chill (Am  → F  → C  → G,  16-bar cycle)
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
#   Cafe:  CH_0 = Electric Piano 1      CH_1 = Choir Pad       CH_2 = Finger Bass  CH_DRUMS
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

DRUM_KICK         = 35   # Bass Drum 1
DRUM_BRUSH_SNARE  = 40   # Electric Snare (GM brush snare)
DRUM_CLOSED_HIHAT = 42   # Closed Hi-Hat
DRUM_PEDAL_HIHAT  = 44   # Pedal Hi-Hat ("chick" on 2 & 4)
DRUM_RIDE         = 51   # Ride Cymbal 1
DRUM_RIDE_BELL    = 53   # Ride Bell (brighter, section accent)

# ---------------------------------------------------------------------------
# Timing helpers
# ---------------------------------------------------------------------------

JAZZY_BPM = 62
CAFE_BPM  = 74


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


# ---------------------------------------------------------------------------
# Jazzy mode — 32-bar cycle, 4 classic 8-bar sections (2 bars per chord)
#
# MIDI note reference (C4=60):
#   Bass octave : C2=36 D2=38 E2=40 F2=41 G2=43 A2=45 B2=47
#   3rd octave  : C3=48 D3=50 E3=52 F3=53 G3=55 A3=57 B3=59
#   4th octave  : C4=60 C#4=61 D4=62 F4=65 G4=67 A4=69 B4=71
#                 E3=52 F#3=54 G#3=56
#
# Sections:
#   Bars  1-8  : ii-V-I-vi         Dm7 → G7 → Cmaj7 → Am7
#   Bars  9-16 : I-VI-ii-V         Cmaj7 → A7 → Dm7 → G7
#   Bars 17-24 : iii-VI-ii-V       Em7 → A7 → Dm7 → G7
#   Bars 25-32 : III7-VI7-II7-V7   E7 → A7 → D7 → G7  (secondary dominants)
# ---------------------------------------------------------------------------

JAZZY_BARS = [
    # (chord_notes, bass_root, bass_fifth)

    # --- Section 1: ii-V-I-vi in C ---
    ([50, 53, 57, 60], 38, 45),   # Dm7   D3 F3 A3 C4  | D2→A2
    ([50, 53, 57, 60], 38, 45),
    ([55, 59, 62, 65], 43, 50),   # G7    G3 B3 D4 F4  | G2→D3
    ([55, 59, 62, 65], 43, 50),
    ([60, 64, 67, 71], 48, 55),   # Cmaj7 C4 E4 G4 B4  | C3→G3
    ([60, 64, 67, 71], 48, 55),
    ([57, 60, 64, 67], 45, 52),   # Am7   A3 C4 E4 G4  | A2→E3
    ([57, 60, 64, 67], 45, 52),

    # --- Section 2: I-VI-ii-V turnaround ---
    ([60, 64, 67, 71], 48, 55),   # Cmaj7 C4 E4 G4 B4  | C3→G3
    ([60, 64, 67, 71], 48, 55),
    ([57, 61, 64, 67], 45, 52),   # A7    A3 C#4 E4 G4 | A2→E3
    ([57, 61, 64, 67], 45, 52),
    ([50, 53, 57, 60], 38, 45),   # Dm7   D3 F3 A3 C4  | D2→A2
    ([50, 53, 57, 60], 38, 45),
    ([55, 59, 62, 65], 43, 50),   # G7    G3 B3 D4 F4  | G2→D3
    ([55, 59, 62, 65], 43, 50),

    # --- Section 3: iii-VI-ii-V ---
    ([52, 55, 59, 62], 40, 47),   # Em7   E3 G3 B3 D4  | E2→B2
    ([52, 55, 59, 62], 40, 47),
    ([57, 61, 64, 67], 45, 52),   # A7    A3 C#4 E4 G4 | A2→E3
    ([57, 61, 64, 67], 45, 52),
    ([50, 53, 57, 60], 38, 45),   # Dm7   D3 F3 A3 C4  | D2→A2
    ([50, 53, 57, 60], 38, 45),
    ([55, 59, 62, 65], 43, 50),   # G7    G3 B3 D4 F4  | G2→D3
    ([55, 59, 62, 65], 43, 50),

    # --- Section 4: III7-VI7-II7-V7 (secondary dominants) ---
    ([52, 56, 59, 62], 40, 47),   # E7    E3 G#3 B3 D4 | E2→B2
    ([52, 56, 59, 62], 40, 47),
    ([57, 61, 64, 67], 45, 52),   # A7    A3 C#4 E4 G4 | A2→E3
    ([57, 61, 64, 67], 45, 52),
    ([50, 54, 57, 60], 38, 45),   # D7    D3 F#3 A3 C4 | D2→A2
    ([50, 54, 57, 60], 38, 45),
    ([55, 59, 62, 65], 43, 50),   # G7    G3 B3 D4 F4  | G2→D3
    ([55, 59, 62, 65], 43, 50),
]


def play_jazzy_bar(synth, bar_index: int, bar_start: float) -> None:
    """
    Block until all note events for one jazzy bar have fired.

    Drum layout:
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
    """
    spb = 60.0 / JAZZY_BPM   # ≈ 0.968 s per beat

    chord_notes, bass_root, bass_fifth = JAZZY_BARS[bar_index % 32]
    section_start = (bar_index % 8 == 0)

    # t=0 — kick + ride + bass root (ride bell accent on section starts)
    sleep_until(bar_start)
    synth.noteon(CH_DRUMS, DRUM_KICK, _vel(55 if section_start else 50))
    synth.noteon(CH_DRUMS, DRUM_RIDE, _vel(52 if section_start else 46))
    if section_start:
        synth.noteon(CH_DRUMS, DRUM_RIDE_BELL, _vel(60))
    synth.noteon(CH_1, bass_root, _vel(62))

    # t=0.5 SPB — ride offbeat ("and" of beat 1)
    sleep_until(bar_start + spb * 0.5)
    synth.noteon(CH_DRUMS, DRUM_RIDE, _vel(32))

    # t=1 SPB — chord + pedal hi-hat chick + snare + ride
    sleep_until(bar_start + spb)
    cv = _vel(30)
    for n in chord_notes:
        synth.noteon(CH_0, n, cv)
    synth.noteon(CH_DRUMS, DRUM_PEDAL_HIHAT,  _vel(38))
    synth.noteon(CH_DRUMS, DRUM_BRUSH_SNARE,  _vel(48))
    synth.noteon(CH_DRUMS, DRUM_RIDE,         _vel(46))

    # t=1.5 SPB — ride offbeat ("and" of beat 2)
    sleep_until(bar_start + spb * 1.5)
    synth.noteon(CH_DRUMS, DRUM_RIDE, _vel(32))

    # t=1.85 SPB — release chord + bass root
    sleep_until(bar_start + spb * 1.85)
    for n in chord_notes:
        synth.noteoff(CH_0, n)
    synth.noteoff(CH_1, bass_root)

    # t=2 SPB — ride + bass fifth
    sleep_until(bar_start + spb * 2.0)
    synth.noteon(CH_DRUMS, DRUM_RIDE,  _vel(44))
    synth.noteon(CH_1,     bass_fifth, _vel(58))

    # t=2.5 SPB — ride offbeat ("and" of beat 3)
    sleep_until(bar_start + spb * 2.5)
    synth.noteon(CH_DRUMS, DRUM_RIDE, _vel(32))

    # t=3 SPB — chord + pedal hi-hat chick + snare + ride
    sleep_until(bar_start + spb * 3.0)
    cv = _vel(28)
    for n in chord_notes:
        synth.noteon(CH_0, n, cv)
    synth.noteon(CH_DRUMS, DRUM_PEDAL_HIHAT,  _vel(36))
    synth.noteon(CH_DRUMS, DRUM_BRUSH_SNARE,  _vel(46))
    synth.noteon(CH_DRUMS, DRUM_RIDE,         _vel(44))

    # t=3.5 SPB — ride offbeat ("and" of beat 4)
    sleep_until(bar_start + spb * 3.5)
    synth.noteon(CH_DRUMS, DRUM_RIDE, _vel(32))

    # t=3.85 SPB — release chord + bass fifth
    sleep_until(bar_start + spb * 3.85)
    for n in chord_notes:
        synth.noteoff(CH_0, n)
    synth.noteoff(CH_1, bass_fifth)


# ---------------------------------------------------------------------------
# Cafe mode — 16-bar cycle  (Am → F → C → G,  4 bars per chord)
#
# Bass low-octave MIDI:  A1=33  F1=29  C2=36  G1=31
# Bass root MIDI:        A2=45  F2=41  C3=48  G2=43
# ---------------------------------------------------------------------------

CAFE_CHORD_SEQ = [
    # (chord_notes, bass_root, bass_low)   — chords raised to octave 4-5 for air
    ([69, 72, 76], 45, 33),   # Am   A4 C5 E5  |  A2 → A1
    ([65, 69, 72], 41, 29),   # F    F4 A4 C5  |  F2 → F1
    ([72, 76, 79], 48, 36),   # C    C5 E5 G5  |  C3 → C2
    ([67, 71, 74], 43, 31),   # G    G4 B4 D5  |  G2 → G1
]

# Track pad notes across bars (mutable container to avoid nonlocal in nested fn)
_cafe_pad_notes: list = []


def play_cafe_bar(synth, bar_index: int, bar_start: float) -> None:
    """
    Block until all note events for one cafe bar have fired.

    Pad (CH_1) is sustained across 4 bars per chord:
      - noteOn  at bar_in_chord == 0, t=0
      - noteOff at bar_in_chord == 3, t=3.95 SPB (near bar end)

    Beat layout per bar (straight 4/4):
      t=0.00 SPB : piano stab ON + kick + hihat + bass_root ON (+ pad if chord onset)
      t=0.60 SPB : piano stab OFF
      t=0.95 SPB : bass_root OFF
      t=1.00 SPB : hihat
      t=2.00 SPB : hihat + bass_low ON
      t=2.95 SPB : bass_low OFF
      t=3.00 SPB : hihat
      t=3.95 SPB : pad OFF (last bar of chord only)
    """
    global _cafe_pad_notes
    spb = 60.0 / CAFE_BPM   # ≈ 0.811 s per beat

    chord_idx   = (bar_index % 16) // 4
    bar_in_chord = bar_index % 4
    chord_notes, bass_root, bass_low = CAFE_CHORD_SEQ[chord_idx]

    # t=0 — piano stab + kick + hihat + bass root (+ pad noteOn if chord onset)
    sleep_until(bar_start)

    if bar_in_chord == 0:
        # Release previous pad notes if any
        for n in _cafe_pad_notes:
            synth.noteoff(CH_1, n)
        # Start new pad
        pv = _vel(42)
        for n in chord_notes:
            synth.noteon(CH_1, n, pv)
        _cafe_pad_notes = list(chord_notes)

    ep = _vel(58)
    for n in chord_notes:
        synth.noteon(CH_0, n, ep)
    synth.noteon(CH_DRUMS, DRUM_KICK,         _vel(22))
    synth.noteon(CH_DRUMS, DRUM_CLOSED_HIHAT, _vel(22))
    synth.noteon(CH_2,     bass_root,         _vel(38))

    # t=0.6 — piano stab OFF
    sleep_until(bar_start + spb * 0.60)
    for n in chord_notes:
        synth.noteoff(CH_0, n)

    # t=0.95 — bass root OFF
    sleep_until(bar_start + spb * 0.95)
    synth.noteoff(CH_2, bass_root)

    # t=1 — hihat
    sleep_until(bar_start + spb)
    synth.noteon(CH_DRUMS, DRUM_CLOSED_HIHAT, _vel(20))

    # t=2 — hihat + bass low + beat-3 piano stab
    sleep_until(bar_start + spb * 2.0)
    synth.noteon(CH_DRUMS, DRUM_CLOSED_HIHAT, _vel(20))
    synth.noteon(CH_2,     bass_low,          _vel(35))
    ep3 = _vel(44)
    for n in chord_notes:
        synth.noteon(CH_0, n, ep3)

    # t=2.55 — beat-3 piano OFF
    sleep_until(bar_start + spb * 2.55)
    for n in chord_notes:
        synth.noteoff(CH_0, n)

    # t=2.95 — bass low OFF
    sleep_until(bar_start + spb * 2.95)
    synth.noteoff(CH_2, bass_low)

    # t=3 — hihat
    sleep_until(bar_start + spb * 3.0)
    synth.noteon(CH_DRUMS, DRUM_CLOSED_HIHAT, _vel(18))

    # t=3.95 — pad OFF (last bar of chord only)
    if bar_in_chord == 3:
        sleep_until(bar_start + spb * 3.95)
        for n in _cafe_pad_notes:
            synth.noteoff(CH_1, n)
        _cafe_pad_notes = []


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
    chord_notes, bass_root, bass_fifth = JAZZY_BARS[bar_index % 32]

    # t=0 — kick + ride + bass root (no piano on beat 1)
    sleep_until(bar_start)
    synth.noteon(CH_DRUMS, DRUM_KICK, _vel(50))
    synth.noteon(CH_DRUMS, DRUM_RIDE, _vel(46))
    synth.noteon(CH_1, bass_root, _vel(60))

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
    synth.noteon(CH_1, bass_fifth, _vel(56))

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
    One-shot cafe bar: same drums/bass as normal, piano arpeggios instead of stab.
    Pad left untouched — it sustains from whatever state it's already in.
    """
    spb = 60.0 / CAFE_BPM
    chord_idx   = (bar_index % 16) // 4
    chord_notes, bass_root, bass_low = CAFE_CHORD_SEQ[chord_idx]
    # Play arpeggio one octave below pad so it cuts through instead of blending
    arp_notes = [n - 12 for n in chord_notes]

    # t=0 — kick + hihat + bass root; arpeggio UP in mid-range
    sleep_until(bar_start)
    synth.noteon(CH_DRUMS, DRUM_KICK,         _vel(22))
    synth.noteon(CH_DRUMS, DRUM_CLOSED_HIHAT, _vel(22))
    synth.noteon(CH_2,     bass_root,         _vel(38))
    for i, n in enumerate(arp_notes):
        sleep_until(bar_start + i * 0.09)
        synth.noteon(CH_0, n, _vel(78 - i * 5))

    # t=0.6 — piano OFF
    sleep_until(bar_start + spb * 0.60)
    for n in arp_notes:
        synth.noteoff(CH_0, n)

    # t=0.95 — bass root OFF
    sleep_until(bar_start + spb * 0.95)
    synth.noteoff(CH_2, bass_root)

    # t=1 — hihat
    sleep_until(bar_start + spb)
    synth.noteon(CH_DRUMS, DRUM_CLOSED_HIHAT, _vel(20))

    # t=2 — hihat + bass low
    sleep_until(bar_start + spb * 2.0)
    synth.noteon(CH_DRUMS, DRUM_CLOSED_HIHAT, _vel(20))
    synth.noteon(CH_2, bass_low, _vel(35))

    # t=2.95 — bass low OFF
    sleep_until(bar_start + spb * 2.95)
    synth.noteoff(CH_2, bass_low)

    # t=3 — hihat; question: top note echo / stop: arpeggio DOWN
    sleep_until(bar_start + spb * 3.0)
    synth.noteon(CH_DRUMS, DRUM_CLOSED_HIHAT, _vel(18))
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


# ---------------------------------------------------------------------------
# Mode setup
# ---------------------------------------------------------------------------

def setup_jazzy(synth, sfid: int) -> None:
    synth.program_select(CH_0,     sfid,   0, GM_ACOUSTIC_GRAND)
    synth.program_select(CH_1,     sfid,   0, GM_ACOUSTIC_BASS)
    synth.program_select(CH_DRUMS, sfid, 128, 0)


def setup_cafe(synth, sfid: int) -> None:
    synth.program_select(CH_0,     sfid,   0, GM_VIBRAPHONE)
    synth.program_select(CH_1,     sfid,   0, GM_WARM_PAD)
    synth.program_select(CH_2,     sfid,   0, GM_FINGER_BASS)
    synth.program_select(CH_DRUMS, sfid, 128, 0)


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
    if current_mode not in ("jazzy", "cafe"):
        current_mode = "jazzy"

    if current_mode == "jazzy":
        setup_jazzy(synth, sfid)
    else:
        setup_cafe(synth, sfid)

    write_state_fields(daemon_pid=os.getpid())

    bar_index = 0

    try:
        while True:
            state = read_state()
            if not state.get("enabled", False):
                break

            new_mode = state.get("mode", "jazzy")
            if new_mode not in ("jazzy", "cafe"):
                new_mode = "jazzy"

            # Mode transition — silence, reconfigure, reset bar counter
            if new_mode != current_mode:
                all_notes_off(synth)
                current_mode = new_mode
                if current_mode == "jazzy":
                    setup_jazzy(synth, sfid)
                else:
                    setup_cafe(synth, sfid)
                bar_index = 0

            one_shot = state.get("one_shot", False)
            if one_shot:
                write_state_fields(one_shot=False)

            bpm     = JAZZY_BPM if current_mode == "jazzy" else CAFE_BPM
            bar_dur = 4.0 * 60.0 / bpm
            bar_start = time.perf_counter()

            variant = one_shot if isinstance(one_shot, str) else "stop"
            if one_shot and current_mode == "jazzy":
                play_jazzy_oneshot(synth, bar_index, bar_start, variant)
            elif one_shot and current_mode == "cafe":
                play_cafe_oneshot(synth, bar_index, bar_start, variant)
            elif current_mode == "jazzy":
                play_jazzy_bar(synth, bar_index, bar_start)
            else:
                play_cafe_bar(synth, bar_index, bar_start)

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
