#!/usr/bin/env bash
# ==============================================================================
# Uncharted PC - macOS Native Runner Script
# Metal-Optimized Launcher for Apple Silicon
# ==============================================================================
set -euo pipefail

PORT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PORT"

# Configure Homebrew paths if available
if [[ -f "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -f "/usr/local/bin/brew" ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

HOMEBREW_PREFIX="$(brew --prefix 2>/dev/null || echo '/opt/homebrew')"

# Configure Metal optimizations
export MVK_CONFIG_FAST_MATH_ENABLED=1
export MVK_CONFIG_RESUME_LOST_DEVICE=1
export MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS=1
export MVK_CONFIG_PRECOMPILE_SHADERS=1
export MVK_CONFIG_ACTIVITY_PERFORMANCE_LOGGING_STYLE=0

# Locate MoltenVK ICD driver
if [[ -z "${VK_ICD_FILENAMES:-}" ]]; then
    if [[ -f "$HOMEBREW_PREFIX/share/vulkan/icd.d/MoltenVK_icd.json" ]]; then
        export VK_ICD_FILENAMES="$HOMEBREW_PREFIX/share/vulkan/icd.d/MoltenVK_icd.json"
        export VK_DRIVER_FILES="$HOMEBREW_PREFIX/share/vulkan/icd.d/MoltenVK_icd.json"
    elif [[ -f "$PORT/out/MoltenVK_icd.json" ]]; then
        export VK_ICD_FILENAMES="$PORT/out/MoltenVK_icd.json"
        export VK_DRIVER_FILES="$PORT/out/MoltenVK_icd.json"
    fi
fi

export DYLD_LIBRARY_PATH="$PORT/out:$PORT/out/gpu:$HOMEBREW_PREFIX/lib:${DYLD_LIBRARY_PATH:-}"
export DYLD_FALLBACK_LIBRARY_PATH="$PORT/out:$HOMEBREW_PREFIX/lib:${DYLD_FALLBACK_LIBRARY_PATH:-}"

GAME="${BB_GAME_DIR:-}"
if [[ -z "$GAME" ]]; then
    echo "=================================================================="
    echo "  Uncharted PC - macOS Runner"
    echo "=================================================================="
    echo "Please specify BB_GAME_DIR with the folder containing your decrypted game files"
    echo "Example:"
    echo "  BB_GAME_DIR=/path/to/CUSA02343 ./run_mac.sh"
    echo "  BB_GAME_DIR=/path/to/CUSA02343 BB_EXE=u2 ./run_mac.sh"
    echo "=================================================================="
    exit 1
fi

EXE_NAME="${BB_EXE:-u1}"
case "$EXE_NAME" in
    u1) EXE="eboot.bin" ;;
    u2) EXE="big2-ps4_Shipping.elf" ;;
    u3) EXE="big3-ps4_Shipping.elf" ;;
    *)  EXE="$EXE_NAME" ;;
esac

USER_DIR="${BB_USER_DIR:-$PORT/user}"
OUT_ROOT="$PORT/out"
OUT="$OUT_ROOT/${EXE%.*}"
PROBE="$PORT/out/bb-probe"

if [[ ! -f "$GAME/eboot.bin" ]]; then
    echo "ERROR: Could not find eboot.bin in $GAME" >&2
    exit 1
fi

if [[ ! -x "$PROBE" ]]; then
    echo "ERROR: bb-probe binary not found at $PROBE" >&2
    echo "Please run ./build_mac.sh first to compile the project." >&2
    exit 1
fi

mkdir -p "$OUT" "$USER_DIR"

export PYTHONUTF8=1
export PYTHONIOENCODING=utf-8
export BB_CONFIG="${BB_CONFIG:-$PORT/bbport.ini}"
export BB_INPUT_CONFIG="${BB_INPUT_CONFIG:-$PORT/input.ini}"
export BB_GPU_USER_DIR="$USER_DIR"
export BB_VBLANK_HZ="${BB_VBLANK_HZ:-60}"
export BB_VELOCITY_PS="${BB_VELOCITY_PS:-f4b18264}"
export BB_UPSCALE_BEFORE_CS="${BB_UPSCALE_BEFORE_CS:-aec539f0}"
export BB_HUDLESS_PS="${BB_HUDLESS_PS:-484cdbf5}"
export BB_LOADEXEC_FILE="$OUT_ROOT/loadexec.txt"

prepare_all() {
    echo "Preparing $EXE for macOS Metal execution..."
    python3 "$PORT/scripts/prepare.py" "$GAME" --out "$OUT" --exe "$EXE"
    python3 "$PORT/scripts/link_modules.py" "$GAME" --out "$OUT" --exe "$EXE"
    python3 "$PORT/scripts/content_profile.py" "$GAME" --out "$OUT" --sku "${BB_CONTENT_SKU:-full}"
}

prepare_all

while true; do
    rm -f "$BB_LOADEXEC_FILE"
    echo "Launching $PROBE..."
    "$PROBE" "$OUT/boot-linked.bin" \
        --content-profile "$OUT/content.bin" \
        --app0 "$GAME" \
        --user "$USER_DIR" \
        --timeout "${BB_TIMEOUT:-0}" \
        "$@" || code=$?

    code="${code:-0}"
    if [[ "$code" -ne 101 ]] || [[ ! -f "$BB_LOADEXEC_FILE" ]]; then
        exit "$code"
    fi

    NEW_EXE=$(basename "$(head -n 1 "$BB_LOADEXEC_FILE" | tr -d '\r')")
    if [[ -z "$NEW_EXE" ]]; then
        echo "ERROR: loadexec.txt is empty" >&2
        exit 1
    fi
    echo ">>> Switching executable to $NEW_EXE"
    EXE="$NEW_EXE"
    OUT="$OUT_ROOT/${EXE%.*}"
    mkdir -p "$OUT"
    prepare_all
done

