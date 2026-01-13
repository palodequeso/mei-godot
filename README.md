# MEI-Godot

A **Godot 4 GDExtension plugin** for procedural galaxy generation using the [MEI (Matter, Energy, Information)](https://github.com/palodequeso/mei) core library. Explore entire galaxies in VR or desktop mode.

### Warning: This is a pre-alpha project and does not claim any sort of scientific accuracy.. but could hopefully be used as a simulation starting point some day.

## What is MEI?

MEI generates galaxies procedurally using density functions and deterministic hashing. The entire galaxy exists implicitly - stars are computed on-demand based on position, not stored. This means:

- **Infinite detail**: Zoom from galactic scale (100,000 ly) down to individual star systems
- **Zero storage**: A galaxy with billions of potential stars requires only a 64-bit seed
- **Perfect determinism**: Same seed + same position = same stars, always
- **Multi-client consistency**: Different viewers querying the same galaxy see identical data

For more details on the generation algorithm, see the [MEI core library](https://github.com/palodequeso/mei).

## Features

This plugin provides:

- **GDExtension bindings** (`mei-godot/`) - Rust FFI layer exposing MEI to GDScript
- **Complete Godot viewer** - Desktop, Mobile, and VR galaxy explorer

### Viewer Features

- **VR Support**: Full OpenXR integration for PCVR (Mobile should work with minor tweaks)
    - Barely working, needs lots of work on UI/Input, can fly around though with PCVR.
- **Desktop Support**: Full desktop support for Windows, Linux, and macOS (not built yet)
- **Mobile Support**: Full mobile support for Android and iOS (not built yet)
- **Dual view modes**:
  - Galaxy view: Explore 500k star point cloud
  - System view: Fly through planetary systems with realistic scales
- **Galaxy rendering**:
  - MultiMesh point clouds (galactic structure + nearby stars)
  - Screen-space picking with hash grid
  - Dynamic nearby star querying
  - Rotatable galaxy with spiral arms visible
- **System rendering**:
  - Orbital mechanics
  - Planet textures (procedurally assigned)
  - Moon systems with orbital paths
  - Asteroid belts
  - Background stars (queried nearby systems that we should make clickable)
  - Selection wireframes
- **UI panels**:
  - Seed input and random generation
  - Goto position
  - Nearest stars list
  - System objects list (clickable)
  - Selected star/planet details
  - Flight controls
- **VR 3D menu**: World-space UI panels in VR mode needs to be implemented


## Project Structure

```
mei-godot/
├── mei-godot/                  # GDExtension Rust crate
│   ├── src/lib.rs              # Godot FFI bindings
│   └── Cargo.toml              # Dependencies (mei core library)
├── mei.gdextension             # GDExtension configuration
├── main.gd                     # Main scene controller
├── galaxy.gd                   # Galaxy rendering (MultiMesh)
├── system.gd                   # Star system rendering
├── generator_config.toml       # Generator configuration
├── assets/                     # Planet textures, models
├── objects/                    # Scene files for planets, etc.
└── build.sh                    # Cross-platform build script
```

Planet textures from https://screamingbrainstudios.itch.io/planet-texture-pack-1

## Quick Start

### Prerequisites

```bash
# Rust toolchain
rustup default stable

# Android target (optional, for Android builds)
rustup target add aarch64-linux-android

# Windows cross-compile target (optional)
rustup target add x86_64-pc-windows-gnu

# Godot 4.3+
sudo apt install godot4  # or download from godotengine.org
```

### Build and Run

```bash
# Build the GDExtension
./build-all.sh

# Open in Godot
godot .
```

### Controls

- **Desktop**: WASD/QE movement, right-click mouse look, scroll to adjust speed
- **Both**: G (galactic view), N (nearby stars), M (system view)
- **VR**: Smooth locomotion (watch your tummy!)

## Configuration

Generator behavior is controlled by `generator_config.toml`:

```toml
# Cell size for spatial quantization (light-years)
cell_size = 0.25

# Star probability scale factor (controls density)
star_probability_scale = 0.002

# Block size for galactic structure sampling
structure_block_size = 100.0

# Samples per block for structure
structure_samples_per_block = 1

# Maximum radius for nearby star queries (light-years)
nearby_max_radius = 32.0

# Scramble stride for even distribution
scramble_stride = 2654435761
```

**Key parameters:**
- `cell_size`: Fundamental unit (0.25 ly = reasonable stellar spacing)
- `star_probability_scale`: Tuned for ~400 billion Milky Way stars
- `nearby_max_radius`: Clamps nearby queries (32 ly = good performance)
- `structure_block_size`: Larger = faster but coarser galactic structure

## Seed 0: The Milky Way

Seed 0 generates a Milky Way clone with parameters based on current astronomical estimates:

| Parameter | Value | Real MW |
|-----------|-------|---------|
| Disk radius | ~50,000 ly | ~50,000 ly |
| Bar length | 15,000 ly | ~13,500 ly |
| Bar angle | 25° | 25-30° |
| Spiral arms | 4 | 4 major |
| Thin disk height | 300 ly | 300-400 ly |
| Thick disk height | 1,000 ly | 1,000 ly |

## Known Issues & Limitations

### Viewer Issues

- **System view camera placement is arbitrary**: When entering system view, the camera is placed at a fixed offset from the star, not based on any realistic planetary orbit, sometimes you're spawned inside the star.
- **Planet textures are placeholder**: Textures are randomly assigned and NOT astrophysically accurate
- **VR controls incomplete**: VR mode works but lacks polish - hand interactions are basic, no menus, no UI, no controls.
- **No orbital motion**: Planets are static along their orbital paths
- **Asteroid belt rendering is basic**: Just a ring right now
- **Star selection is janky**: Picking stars in 3D is hit or miss with point rendering

### Performance

- **Nearby star queries can be slow**: 32 ly radius queries check ~4 million cells - debouncing helps
- **Galactic structure generation not cached**: Changing seeds regenerates 500k stars (1-2 seconds)
- **No LOD system**: All stars render as same-size points regardless of distance

### Not Implemented Yet

- **No persistence**: Can't save/load selected galaxies or favorite systems
- **Limited star types**: Only basic main sequence (O, B, A, F, G, K, M) - no exotic objects
- **No atmospheric effects**: Planets have no clouds, weather, or day/night cycles

## Cross-Platform Extension Builds

The `build-all.sh` script builds for multiple platforms:

```bash
./build-all.sh
```

This builds:
- Linux (debug + release)
- Windows (via mingw cross-compile)
- Android (aarch64, requires NDK)

Configure the Android NDK linker in `.cargo/config.toml` if needed.

## Godot Project

The Godot project is in the root directory. You can open it in Godot 4.3+.
Then you should be able to export to any platform we've built the extension for.
I've tested it on Linux, Windows, and Android, as well as Linux PCVR streamed to a Quest 2 with WiVRn.

## Related Projects

- [MEI Core Library](https://github.com/palodequeso/mei) - The procedural generation engine this plugin uses

## License

MIT
