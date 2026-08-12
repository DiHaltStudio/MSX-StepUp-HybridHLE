# MSX StepUp HybridHLE

**MSX StepUp HybridHLE** is a cross-platform Godot 4 port of the 1983 MSX
platform game *Step Up*. The original Z80 program runs through a native
GDExtension, while Godot provides high-level video, input, audio, presentation,
and platform integration.

The original cartridge is **not included**. Each player must supply a legally
obtained dump of their own cartridge. The downloadable game contains C-BIOS,
the captured high-RAM state, and all native components needed to run; it never
downloads or distributes the original game ROM.

The illustrated user manual explains setup, controls, game rules, and the
Hybrid HLE architecture. It is available in
[English](docs/manual/manual-en.pdf) and [Spanish](docs/manual/manual.pdf),
with editable LaTeX sources in [`docs/manual`](docs/manual/).

## Download and play

Prebuilt applications are release assets, not files committed to the source
repository. Use these links after the first tagged GitHub release is published:

| Platform | Download |
| --- | --- |
| Windows 64-bit | [MSX-StepUp-HybridHLE-windows-x86_64.zip](../../releases/latest/download/MSX-StepUp-HybridHLE-windows-x86_64.zip) |
| Linux x86-64 | [MSX-StepUp-HybridHLE-linux-x86_64.zip](../../releases/latest/download/MSX-StepUp-HybridHLE-linux-x86_64.zip) |
| macOS Universal | [MSX-StepUp-HybridHLE-macOS-universal.zip](../../releases/latest/download/MSX-StepUp-HybridHLE-macOS-universal.zip) |
| Android ARM64 | [MSX-StepUp-HybridHLE-android-arm64.apk](../../releases/latest/download/MSX-StepUp-HybridHLE-android-arm64.apk) |

If a link returns 404, no tagged release containing that asset has been
published yet. Maintainers create all four downloads by pushing a tag whose
name starts with `v`; the release workflow is described below.

Start the game and select your ROM when prompted. If it was supplied in a ZIP
archive, extract the `.rom` file first. The game checks the file and stores a
private copy for later runs. The accepted input format is:

| Property | Required value |
| --- | --- |
| Filename | Any filename is accepted by the selector |
| Accepted dump sizes | 8, 16, or 32 KiB |
| Recognition | Step Up cartridge header and entry point in an 8 KiB bank |
| Tested normalized SHA-256 | `d62c19f7023841e1f74953df58626c350e8549861576749ab1e01a6f1214406a` |

Padded and overdumped images are reduced to the recognized 8 KiB cartridge
bank before they are stored. The hash above is the variant used throughout
development and verified in the current port. Other recognized variants are
accepted, but should currently be considered compatibility candidates until a
complete playthrough has been reported.

On desktop systems, the alternative manual layout below is also supported:

```text
MSX-StepUp-HybridHLE/
├── MSX-StepUp-HybridHLE executable or .app
└── roms/
	└── stepup.rom
```

On macOS, place `roms` beside the `.app`, not inside it. A ROM can also be
selected explicitly at launch with the user argument `--rom=<rom-file>`.

### Known dump catalogue entries

The third-party [File-Hunter MSX1 ROM index](https://download.file-hunter.com/Games/MSX1/ROM/)
currently lists five Step Up dumps:

- `Step Up - Marvel Soft-Takara (1983) [2186]`
- `Step Up - Marvel Soft-Takara (1983) [2985]`
- `Step Up - Marvel Soft-Takara (1983) [a1] [GoodMSX] [2182]`
- `Step Up - Marvel Soft-Takara (1983) [GoodMSX] [2183]`
- `Step Up - Marvel Soft-Takara (1983) [o] [2185]`

The index exposes archive names and compressed sizes but not the internal ROM
hashes, so the tested hash cannot yet be assigned reliably to one of those five
identifiers. Compatibility reports should include the normalized SHA-256.

This link is provided as a catalogue reference because it documents the five
known layouts. It is operated by a third party and is not affiliated with this
project. Users are responsible for ensuring that their ROM was obtained and is
used lawfully in their jurisdiction. No ROM from that archive is mirrored or
distributed by this repository.

### Platform notes

- **Windows:** extract the whole ZIP before opening the executable. An unsigned
  community build may trigger Microsoft SmartScreen.
- **Linux:** extract the ZIP. If the executable bit was lost during download,
  run `chmod +x MSX-StepUp-HybridHLE.x86_64` once.
- **macOS:** extract the ZIP and open the app. An unnotarized community build
  may require Control-clicking the app and choosing **Open**.
- **Android:** install the APK, open it, and use Android's document picker to
  choose the ROM. The APK includes touch controls and does not require storage
  permission because selection is handled by the system picker.

## How to play

You control a stranded alien trying to reach its spaceship on the roof of a
building. Climb the ladders and work upward while avoiding mice, bats, cats,
spiders, and other moving hazards. Contact with an enemy costs a life.

| Control | Keyboard | Android |
| --- | --- | --- |
| Move left/right | Left/Right arrows | LEFT/RIGHT buttons |
| Climb | Up/Down arrows | UP/DOWN buttons |
| Jump/action | Space | ACTION button |
| Skip opening image | Space | ACTION button |

The game is intentionally demanding. Learn enemy routes, wait for a safe gap,
and avoid entering a ladder while an enemy is about to cross it.

## What Hybrid HLE means here

This project is neither a full MSX emulator nor a rewrite of the game's rules.
It runs the original Z80 instructions but implements only the surrounding MSX
services that this game needs. At startup it assembles the 64 KiB address space
seen by the CPU:

```text
0000-3FFF  C-BIOS MSX1 EU
4000-5FFF  player-provided Step Up cartridge
6000-7FFF  cartridge mirror
8000-FFFF  captured high-RAM state at the game entry point
```

Godot then supplies the TMS9918A-facing video path, MSX keyboard matrix,
event-driven sound replacement, touch input, and modern window/application
integration. This focused design keeps the original game logic while allowing
the presentation layer to evolve independently.

## Build from source

Requirements:

- Godot 4.6.x with export templates
- CMake 3.22 or newer
- Ninja or another CMake-supported build tool
- A C++17 compiler
- Git with submodule support

Clone the repository including `godot-cpp`:

```bash
git clone --recurse-submodules <repository-url>
cd MSX-StepUp-HybridHLE
```

If the repository was cloned without submodules, initialize them with:

```bash
git submodule update --init --recursive
```

### Linux

The convenience script builds the release GDExtension and exports the game:

```bash
./export.sh
```

The equivalent native-extension build is:

```bash
cmake -S . -B build/linux -DCMAKE_BUILD_TYPE=Release -DGODOTCPP_TARGET=template_release
cmake --build build/linux --parallel
```

### Windows

Run from a Visual Studio developer terminal or another terminal with a C++
toolchain and Ninja available:

```powershell
cmake -S . -B build/windows -G Ninja -DCMAKE_BUILD_TYPE=Release -DGODOTCPP_TARGET=template_release
cmake --build build/windows --parallel
godot --headless --path . --export-release Windows build/export/MSX-StepUp-HybridHLE.exe
```

### macOS Universal

An Apple Silicon or Intel Mac with Xcode command-line tools can create a single
binary for both architectures:

```bash
cmake -S . -B build/macos -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DGODOTCPP_TARGET=template_release \
  '-DCMAKE_OSX_ARCHITECTURES=x86_64;arm64'
cmake --build build/macos --parallel
godot --headless --path . --export-release macOS build/export/MSX-StepUp-HybridHLE-macOS.zip
```

### Android ARM64

Install OpenJDK 17, Android SDK platform 35, and Android NDK r28b as described
by the Godot Android export documentation. With the standard Android SDK
environment variables configured:

```bash
cmake -S . -B build/android -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DGODOTCPP_TARGET=template_release \
  -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-24
cmake --build build/android --parallel
godot --headless --path . --export-release Android build/export/MSX-StepUp-HybridHLE.apk
```

Android release exports require a signing key. Keep that key private and use
the same key for every release so installed copies can be upgraded.

## Automated releases

`.github/workflows/build.yml` builds and packages all four platforms. Every
push and pull request produces downloadable workflow artifacts. Pushing a tag
whose name starts with `v` also creates a GitHub Release and attaches the four
finished packages.

Before the first public Android release, configure these GitHub repository
secrets:

- `ANDROID_KEYSTORE_BASE64`: the release keystore encoded as Base64
- `ANDROID_KEYSTORE_USER`: key alias
- `ANDROID_KEYSTORE_PASSWORD`: store/key password

Without those secrets the workflow generates a temporary development signing
key. The resulting APK is installable for testing, but it cannot reliably
upgrade an APK made by another workflow run.

The ROM is excluded explicitly by both `.gitignore` and every export preset.
Release packages contain a `roms` directory only as an empty convenience
folder; they never contain `stepup.rom`.

## Repository layout

```text
assets/                 Project graphics and replacement audio
doc_classes/            Z80Node Godot API documentation
roms/                   Redistributable C-BIOS and initial RAM image
scenes/                  Godot scene, HLE integration, and rendering
src/                     Native GDExtension source
thirdparty/chips/        Andre Weissflog's z80.h
thirdparty/godot-cpp/    godot-cpp Git submodule
tools/                   Build-support scripts
LICENSE                  GPL-3.0 licence text
ASSET-LICENSE.md         CC BY-SA terms and asset qualifications
THIRD_PARTY_NOTICES.md   Required attribution and third-party notices
```

Generated `.godot`, `build`, `bin`, and export directories are ignored. Local
editor, assistant, and machine-specific configuration is also ignored.

## Licensing

### Project credits

**DiHalt** is formed by Fernando García and Clemente Tiñena. On this project:

- **Fernando García:** Hybrid HLE implementation, integration, and project
  artwork.
- **Clemente Tiñena:** sound and replacement audio.

Copyright © 2026 DiHalt (Fernando García and Clemente Tiñena), according to
their respective contributions.

Unless a file says otherwise, the original source code in this repository is
licensed under **GNU GPL-3.0-or-later**; see [LICENSE](LICENSE). Original
project artwork and replacement audio are licensed separately under **CC BY-SA
4.0**; see [ASSET-LICENSE.md](ASSET-LICENSE.md). The licence grant only covers
rights held by the project contributors and does not override rights in
third-party source material. Consolidated attribution is provided in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Third-party components retain their own licences:

- `chips/z80.h` by Andre Weissflog — zlib/libpng license. The original header
  and attribution notice are preserved.
- `godot-cpp` by the Godot Engine contributors — MIT license.
- C-BIOS 0.29 — 2-clause BSD license. The complete notice is included in
  `roms/README.cbios` and must accompany binary redistributions.

*Step Up* and its original materials belong to their respective rights
holders. This is an independent preservation and porting project and is not
affiliated with or endorsed by them.

## Sources for the game description

The gameplay summary was checked against the contemporary MSX listing and
catalogue descriptions linked below:

- [MobyGames: Step Up overview and description](https://www.mobygames.com/game/19749/step-up/)
- [Generation MSX: Step Up technical entry](https://www.generation-msx.nl/software/takara-marvel-soft/step-up/42/)
- [Games Database: Step Up](https://www.gamesdatabase.org/game/msx/step-up)
