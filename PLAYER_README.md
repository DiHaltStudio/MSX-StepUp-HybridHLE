# MSX StepUp HybridHLE — Player setup

The original **Step Up** cartridge is not included. You must provide a legally
obtained dump of your own cartridge.

## Add the ROM

Start the game and choose **Select Step Up ROM**. If your dump is inside a ZIP
archive, extract the `.rom` file first. Select an 8, 16, or 32 KiB Step Up
dump. Padded and overdumped files are normalized automatically, and the game
keeps a private 8 KiB copy for future runs.

On Windows, Linux, and macOS you may instead create a `roms` folder beside the
game executable (beside the `.app` on macOS) and put the file there as:

```text
roms/stepup.rom
```

Tested dump after normalization:

- Accepted source sizes: 8, 16, or 32 KiB
- SHA-256: `d62c19f7023841e1f74953df58626c350e8549861576749ab1e01a6f1214406a`

Other files carrying the expected Step Up cartridge header are accepted as
compatibility candidates. See the main project README for the five catalogue
entries and their current verification status.

Catalogue reference:

https://download.file-hunter.com/Games/MSX1/ROM/

The linked archive is operated by a third party and is not affiliated with the
project. It is referenced to identify the five known dump layouts; no original
game ROM is included here. You are responsible for obtaining and using ROM
data lawfully in your jurisdiction.

## How to play

Guide the stranded alien up the building to the spaceship on the roof. Climb
the ladders and avoid mice, bats, cats, spiders, and the other hazards.

- Arrow keys: move and climb
- Space: jump/action; also skips the opening image
- Android: use the on-screen direction and action buttons

The game is deliberately difficult. Watch enemy routes, wait for a safe gap,
and do not rush onto a ladder when an enemy is approaching.

## Platform notes

- **Windows:** extract the complete ZIP before running the `.exe`.
- **Linux:** extract the ZIP, then allow the executable to run if required
  (`chmod +x MSX-StepUp-HybridHLE.x86_64`).
- **macOS:** extract the ZIP and open the `.app`. Unsigned development builds
  may require Control-clicking the app and choosing **Open**.
- **Android:** allow installation from your browser or file manager, install
  the APK, open it, and select the ROM with Android's document picker.

This project is by **DiHalt**, formed by Fernando García and Clemente Tiñena.
Fernando created the Hybrid HLE implementation, integration, and project
artwork; Clemente created the sound and replacement audio.

This independent project is not affiliated with or endorsed by the original
game's developers or publishers.
