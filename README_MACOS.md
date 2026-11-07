# Uncharted: The Nathan Drake Collection - macOS Port

Native macOS port and loader for **Uncharted 1, 2, and 3: The Nathan Drake Collection**, optimized for **Apple Silicon (ARM64: M1, M2, M3, M4)** and **Apple Metal**.

---

## Highlights

- **One-Click Build (`./build_mac.sh`)**: Automatically checks and installs all Homebrew dependencies, pulls submodules, applies patches, and compiles the binaries with Ninja and CMake.
- **Metal-Optimized Graphics Pipeline**:
  - Direct integration with Apple's Metal framework via `CAMetalLayer` and MoltenVK.
  - Enabled Metal Fast Math compiler pipelines (`MVK_CONFIG_FAST_MATH_ENABLED=1`).
  - Metal Tier 2 argument buffers and shader pre-compilation.
  - Unified memory detection for full resolution scaling and high-refresh gameplay on Apple Silicon.
- **Strictly ARM64 Native Toolchain & Universal Support**:
  - Full native compilation for Apple Silicon (`arm64`).
  - Supports building Universal or Rosetta execution slices to run the game's original PS4 x86-64 code directly on Apple Silicon.
- **Full Feature Parity**:
  - Remappable keyboard, mouse, and gamepads (DualSense, DualShock 4, Xbox).
  - Trophies, save games, in-game settings menu.
  - Full resolutions up to 4K and ultrawide support.

---

## Requirements

1. **Mac Hardware**: Apple Silicon Mac (M1, M2, M3, M4 or newer).
2. **OS**: macOS 13.0 (Ventura), macOS 14.0 (Sonoma), macOS 15.0 (Sequoia) or newer.
3. **Decrypted Game Dump**: Your own decrypted dump of the PS4 collection (with `eboot.bin`, `big2-ps4_Shipping.elf`, `big3-ps4_Shipping.elf`, etc.).
4. **Do I need Xcode?**
   - **NO!** You do **NOT** need the full Xcode app (~40 GB download).
   - Only the lightweight **Command Line Tools** (~500 MB) are needed for `clang` and SDK headers.
   - You don't even need to install it manually: `build_mac.sh` will auto-detect and trigger installation for both Command Line Tools and Rosetta 2 if they aren't already installed!

---

## One-Click Compilation

On your Mac, open Terminal in the repository directory and run:

```bash
chmod +x build_mac.sh run_mac.sh
./build_mac.sh
```

### What `build_mac.sh` does automatically:
1. Detects your Apple Silicon Mac architecture.
2. Checks for **Homebrew** and installs missing dependencies (`cmake`, `ninja`, `pkg-config`, `glslang`, `molten-vk`, `sdl3`, `ffmpeg`, `boost`, `openssl`, `protobuf`, `zydis`, etc.).
3. Initializes submodules and applies required renderer patches.
4. Configures Metal performance options.
5. Builds:
   - `out/libbbgpu.dylib` (Metal video core and shader recompiler)
   - `out/bb-probe` (Native loader)
   - `out/bb-gpu-capabilities` (GPU probe and resolution scaler)
6. Performs ad-hoc code signing required for execution on Apple Silicon.

### Build Flags (Optional)
- `./build_mac.sh --arm64` (Default: strictly ARM64 native)
- `./build_mac.sh --universal` (Builds Universal Mach-O binary containing both `arm64` and `x86_64` slices)
- `./build_mac.sh --x86_64` (Builds `x86_64` slice for Rosetta translation)

---

## Running the Game

Set `BB_GAME_DIR` to the folder containing your decrypted game files, then run `run_mac.sh`:

```bash
# Launch Uncharted 1: Drake's Fortune
BB_GAME_DIR="/path/to/game_dump" ./run_mac.sh

# Launch Uncharted 2: Among Thieves
BB_GAME_DIR="/path/to/game_dump" BB_EXE=u2 ./run_mac.sh

# Launch Uncharted 3: Drake's Deception
BB_GAME_DIR="/path/to/game_dump" BB_EXE=u3 ./run_mac.sh
```

---

## Architecture & How It Works on Apple Silicon

1. **CPU Code**:
   PlayStation 4 binaries are compiled for AMD Jaguar (x86-64). On Apple Silicon Macs, the loader binary interacts with macOS and Rosetta 2 to execute the game's original logic at near-native speeds.
2. **GPU & Shaders (Metal)**:
   PS4 GCN GPU command buffers are recompiled into SPIR-V shaders and translated into native Apple **Metal Shading Language (MSL)** and Metal render pipelines through MoltenVK and SDL3 Metal views (`CAMetalLayer`).
3. **Memory Management**:
   The loader maps guest physical memory pools using Darwin POSIX shared memory (`shm_open`) and shrinks the macOS default 4 GiB `PAGEZERO` to 4 KiB (`-Wl,-pagezero_size,0x1000`) so the game executable can map into its native low address ranges (e.g., `0x400000`).

---

## Troubleshooting

- **Permission Denied / Quarantine**:
  If macOS Gatekeeper blocks binaries, clear the quarantine attribute:
  ```bash
  xattr -dr com.apple.quarantine out/
  ```
- **Controller Setup**:
  DualSense and Xbox Wireless controllers connect via Bluetooth or USB and work natively out-of-the-box via SDL3.

