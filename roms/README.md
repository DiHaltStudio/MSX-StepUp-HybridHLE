# User-provided ROM

This directory contains the redistributable C-BIOS MSX1 EU image and the
project's high-RAM initial state. During development, copy your Step Up
cartridge dump into this directory as `stepup.rom`. The loader accepts 8, 16,
and 32 KiB catalogue layouts and locates the relevant 8 KiB bank. In a packaged
game, the in-app selector is the preferred way to import it.

The fully tested normalized dump has this SHA-256:

`d62c19f7023841e1f74953df58626c350e8549861576749ab1e01a6f1214406a`

The Step Up ROM is not part of this project and cartridge ROMs are ignored by
Git. Desktop exports also accept `roms/stepup.rom` beside the executable (or
beside the `.app` on macOS).

Five known catalogue entries are listed at:

https://download.file-hunter.com/Games/MSX1/ROM/

This third-party link is included for identification only. The project does
not mirror or distribute the original game, and users are responsible for
obtaining and using ROM data lawfully.

You can also pass an explicit path on the command line:

```text
--rom=<rom-file>
```
