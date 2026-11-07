#!/usr/bin/env bash
# ==============================================================================
# Uncharted PC - macOS Native Port Build Script
# Strictly ARM64 (Apple Silicon: M1 / M2 / M3 / M4) & Metal-Optimized
# ==============================================================================
set -euo pipefail

cd -- "$(dirname -- "$0")"
ROOT_DIR="$PWD"
mkdir -p out out/gpu

echo "=================================================================="
echo "  Uncharted PC - One-Click macOS Build (Apple Silicon / Metal)    "
echo "=================================================================="

# 1. Platform verification
OS="$(uname -s)"
if [[ "$OS" != "Darwin" ]]; then
    echo "ERROR: This script is intended for macOS (Darwin). Detected: $OS" >&2
    exit 1
fi

HOST_ARCH="$(uname -m)"
echo "Host OS: macOS ($OS), Architecture: $HOST_ARCH"

TARGET_ARCH="arm64"
BUILD_UNIVERSAL=0

for arg in "$@"; do
    case "$arg" in
        --universal)
            BUILD_UNIVERSAL=1
            TARGET_ARCH="arm64;x86_64"
            echo "Mode: Universal Binary (arm64 + x86_64 for Rosetta 2 compatibility)"
            ;;
        --x86_64)
            TARGET_ARCH="x86_64"
            echo "Mode: x86_64 slice (Rosetta 2 translation)"
            ;;
        --arm64)
            TARGET_ARCH="arm64"
            echo "Mode: Strictly ARM64 native"
            ;;
    esac
done

echo "Target Architecture: $TARGET_ARCH"

# 2. Check for Xcode Command Line Tools (Full Xcode is NOT needed!)
if ! xcode-select -p >/dev/null 2>&1; then
    echo "Xcode Command Line Tools not detected."
    echo "NOTE: You do NOT need the full Xcode app (~40 GB). Installing the lightweight Command Line Tools (~500 MB)..."
    xcode-select --install 2>/dev/null || true
    echo "Please accept any on-screen prompt if shown, waiting for installation to complete..."
    until xcode-select -p >/dev/null 2>&1; do
        sleep 5
    done
    echo "Xcode Command Line Tools installed successfully."
else
    echo "Xcode Command Line Tools: $(xcode-select -p)"
fi

# 3. Check / configure Rosetta 2 for running x86_64 PS4 guest code on Apple Silicon
if [[ "$HOST_ARCH" == "arm64" ]]; then
    if [[ ! -f "/Library/Apple/usr/libexec/oah/liboah.dylib" ]] && ! /usr/bin/pgrep oahd >/dev/null 2>&1; then
        echo "Installing Rosetta 2 for PS4 x86-64 execution..."
        softwareupdate --install-rosetta --agree-to-license 2>/dev/null || true
    fi
fi

# 4. Check and configure Homebrew environment on Apple Silicon (/opt/homebrew)
if [[ -f "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -f "/usr/local/bin/brew" ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew is not detected. Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [[ -f "/opt/homebrew/bin/brew" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f "/usr/local/bin/brew" ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
fi

# Ensure Homebrew paths are active
HOMEBREW_PREFIX="$(brew --prefix)"
export PATH="$HOMEBREW_PREFIX/bin:$PATH"
export PKG_CONFIG_PATH="$HOMEBREW_PREFIX/lib/pkgconfig:$HOMEBREW_PREFIX/share/pkgconfig:${PKG_CONFIG_PATH:-}"
export CMAKE_PREFIX_PATH="$HOMEBREW_PREFIX:${CMAKE_PREFIX_PATH:-}"

echo "Homebrew prefix: $HOMEBREW_PREFIX"

# 5. Check and install all dependencies automatically
echo "--- Checking dependencies ---"
DEPS=(
    cmake
    ninja
    pkg-config
    glslang
    molten-vk
    vulkan-headers
    sdl3
    ffmpeg
    boost
    nlohmann-json
    openssl@3
    protobuf
    miniupnpc
    libxxhash
    zydis
    python3
)

MISSING_DEPS=()
for dep in "${DEPS[@]}"; do
    dep_name="${dep%%@*}"
    if ! brew list "$dep" >/dev/null 2>&1 && ! brew list "$dep_name" >/dev/null 2>&1; then
        MISSING_DEPS+=("$dep")
    fi
done

if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
    echo "Installing missing dependencies via Homebrew: ${MISSING_DEPS[*]} ..."
    brew install "${MISSING_DEPS[@]}"
else
    echo "All Homebrew dependencies are satisfied."
fi

# Locate OpenSSL from Homebrew
OPENSSL_ROOT="$(brew --prefix openssl@3 2>/dev/null || brew --prefix openssl 2>/dev/null || true)"
if [[ -n "$OPENSSL_ROOT" ]]; then
    export PKG_CONFIG_PATH="$OPENSSL_ROOT/lib/pkgconfig:$PKG_CONFIG_PATH"
    export CMAKE_PREFIX_PATH="$OPENSSL_ROOT:$CMAKE_PREFIX_PATH"
fi

# Locate MoltenVK ICD (Metal driver for Vulkan)
MVK_ICD="$HOMEBREW_PREFIX/share/vulkan/icd.d/MoltenVK_icd.json"
if [[ -f "$MVK_ICD" ]]; then
    export VK_ICD_FILENAMES="$MVK_ICD"
    export VK_DRIVER_FILES="$MVK_ICD"
    echo "MoltenVK (Metal driver) found at: $MVK_ICD"
fi

# 6. Metal Performance Optimizations Environment
echo "--- Configuring Metal Optimizations ---"
export MVK_CONFIG_FAST_MATH_ENABLED=1             # Enable Metal fast math compiler pipeline
export MVK_CONFIG_RESUME_LOST_DEVICE=1            # Auto-recover device lost states
export MVK_CONFIG_ACTIVITY_PERFORMANCE_LOGGING_STYLE=0
export MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS=1    # Metal Tier 2 argument buffers
export MVK_CONFIG_PRECOMPILE_SHADERS=1           # Precompile shaders to Metal MSL pipeline

# 7. Initialize Git Submodules and apply patches
echo "--- Initializing submodules ---"
if [[ ! -f gpu/third_party/fsr-vulkan/CMakeLists.txt || ! -f gpu/third_party/imgui/imgui.h || ! -f gpu/third_party/xbyak/xbyak/xbyak.h ]]; then
    git submodule update --init --recursive
fi

for patch in gpu/patches/fsr-vulkan/*.patch; do
    if [[ -f "$patch" ]]; then
        if ! git -C gpu/third_party/fsr-vulkan apply --ignore-whitespace --reverse --check "$ROOT_DIR/$patch" 2>/dev/null; then
            echo "Applying patch: $patch"
            git -C gpu/third_party/fsr-vulkan apply --ignore-whitespace "$ROOT_DIR/$patch" || true
        fi
    fi
done

# 8. Configure and Build with CMake and Ninja
echo "--- Configuring CMake for bbgpu & native binaries ---"
CMAKE_EXTRA_FLAGS=(
    -G Ninja
    -DCMAKE_BUILD_TYPE=RelWithDebInfo
    -DCMAKE_OSX_ARCHITECTURES="$TARGET_ARCH"
    -DCMAKE_OSX_DEPLOYMENT_TARGET="13.0"
    -DBB_PGO=off
    -DBB_LTO="${BB_LTO:-ON}"
    -DVK_USE_PLATFORM_METAL_EXT=ON
)

if [[ -f third_party/Vulkan-Headers/include/vulkan/vulkan.h ]]; then
    CMAKE_EXTRA_FLAGS+=(-DVulkan_INCLUDE_DIR="$ROOT_DIR/third_party/Vulkan-Headers/include")
fi

cmake -S gpu -B out/gpu "${CMAKE_EXTRA_FLAGS[@]}"

echo "--- Compiling targets (bbgpu, bb-probe, bb-gpu-capabilities) ---"
ninja -C out/gpu bbgpu bb-probe bb-gpu-capabilities

# 9. Copy artifacts to out/
cp -f out/gpu/libbbgpu.dylib out/libbbgpu.dylib
cp -f out/gpu/bb-probe out/bb-probe
cp -f out/gpu/bb-gpu-capabilities out/bb-gpu-capabilities
chmod +x out/bb-probe out/bb-gpu-capabilities

# 10. Ad-hoc code signing for Apple Silicon gatekeeper / AMFI
echo "--- Ad-hoc code signing binaries for macOS ARM64 ---"
codesign --force --deep --sign - out/libbbgpu.dylib 2>/dev/null || true
codesign --force --deep --sign - out/gpu/libbbgpu.dylib 2>/dev/null || true
codesign --force --deep --sign - out/bb-probe 2>/dev/null || true
codesign --force --deep --sign - out/bb-gpu-capabilities 2>/dev/null || true

echo "=================================================================="
echo "  Build successful!                                               "
echo "  Binaries created:                                               "
echo "    - $ROOT_DIR/out/bb-probe                                      "
echo "    - $ROOT_DIR/out/libbbgpu.dylib                                "
echo "    - $ROOT_DIR/out/bb-gpu-capabilities                           "
echo "=================================================================="
echo "To run on Mac, execute: ./run_mac.sh"

