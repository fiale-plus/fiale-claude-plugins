#!/usr/bin/env bash
# install.sh — set up vibes plugin audio dependencies
#
# Installs:
#   1. fluidsynth    (via Homebrew)
#   2. pyfluidsynth  (via pip3)
#   3. GeneralUser GS SoundFont → ~/.claude/vibes/GeneralUser_GS.sf2

set -euo pipefail

VIBES_DIR="$HOME/.claude/vibes"
GUS_SF2="$VIBES_DIR/GeneralUser_GS.sf2"
GUS_URL="https://www.generaluser.us/files/generaluser-gs/GeneralUser-GS-1.471.tar.gz"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { printf "${GREEN}✓${NC} %s\n" "$*"; }
info() { printf "${YELLOW}→${NC} %s\n" "$*"; }
err()  { printf "${RED}✗${NC} %s\n" "$*" >&2; }

mkdir -p "$VIBES_DIR"

# ---------------------------------------------------------------------------
# 1. FluidSynth
# ---------------------------------------------------------------------------

if command -v fluidsynth &>/dev/null; then
    ok "fluidsynth already installed ($(fluidsynth --version 2>/dev/null | head -1 || echo 'version unknown'))"
else
    if ! command -v brew &>/dev/null; then
        err "Homebrew not found. Install it from https://brew.sh then re-run this script."
        exit 1
    fi
    info "Installing fluidsynth via Homebrew..."
    brew install fluidsynth
    ok "fluidsynth installed"
fi

# ---------------------------------------------------------------------------
# 2. pyfluidsynth
# ---------------------------------------------------------------------------

if python3 -c "import fluidsynth" 2>/dev/null; then
    ok "pyfluidsynth already installed"
else
    info "Installing pyfluidsynth..."
    pip3 install pyfluidsynth
    ok "pyfluidsynth installed"
fi

# ---------------------------------------------------------------------------
# 3. GeneralUser GS SoundFont
# ---------------------------------------------------------------------------

if [[ -f "$GUS_SF2" ]]; then
    ok "GeneralUser GS SF2 already present at $GUS_SF2"
else
    info "Downloading GeneralUser GS SoundFont (~29 MB)..."
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT

    if curl -fsSL "$GUS_URL" -o "$tmp/gu.tar.gz"; then
        tar -xf "$tmp/gu.tar.gz" -C "$tmp"
        # Find the .sf2 inside the extracted archive
        sf2=$(find "$tmp" -name "*.sf2" | head -1)
        if [[ -n "$sf2" ]]; then
            cp "$sf2" "$GUS_SF2"
            ok "GeneralUser GS installed at $GUS_SF2"
        else
            err "No .sf2 found in archive — download may have changed structure."
            _print_manual_instructions
        fi
    else
        err "Download failed (URL: $GUS_URL)"
        _print_manual_instructions
    fi
fi

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------

echo ""
echo "Verifying FluidSynth + SoundFont..."
python3 - <<'PYEOF'
import sys
try:
    import fluidsynth
except ImportError:
    print("ERROR: pyfluidsynth import failed — run: pip3 install pyfluidsynth")
    sys.exit(1)

import os
sf2_candidates = [
    os.path.expanduser("~/.claude/vibes/GeneralUser_GS.sf2"),
    "/opt/homebrew/share/fluid-synth/sf2/VintageDreamsWaves-v2.sf2",
    "/usr/local/share/fluid-synth/sf2/VintageDreamsWaves-v2.sf2",
]
found = next((p for p in sf2_candidates if os.path.exists(p)), None)
if found:
    print(f"SoundFont: {found}")
else:
    print("WARNING: No SoundFont found in expected locations — vibes may not play audio.")
    sys.exit(1)
print("All good — run 'vibes jazzy' or 'vibes cafe' to start music.")
PYEOF

_print_manual_instructions() {
    echo ""
    echo "Manual install:"
    echo "  1. Download GeneralUser GS from: https://www.generaluser.us/"
    echo "  2. Extract the .sf2 file"
    echo "  3. Copy it to: $GUS_SF2"
    echo ""
    echo "Alternative: the plugin will fall back to VintageDreamsWaves"
    echo "  (bundled with brew's fluidsynth at /opt/homebrew/share/fluid-synth/sf2/)"
}
