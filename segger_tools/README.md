# segger_tools/

Place SEGGER `.deb` packages next to this file before building the image.
All `.deb` files found in this directory are installed automatically.

## Supported packages

| Tool | Download |
|---|---|
| J-Link | https://www.segger.com/downloads/jlink/ → `JLink_Linux_V<ver>_x86_64.deb` |
| Ozone | https://www.segger.com/downloads/jlink/#Ozone → `Ozone_Linux_V<ver>_x86_64.deb` |
| SystemView | https://www.segger.com/downloads/systemview/ → `SystemView_Linux_V<ver>_x86_64.deb` |

## Usage

1. Download the desired `.deb` file(s) from segger.com and place them here.
2. Run `./build.sh` — the script detects any `.deb` in this directory and enables installation automatically.

Alternatively, build manually:
```bash
podman build --build-arg INSTALL_SEGGER_TOOLS=1 -t zephyr-build-host:1.0.1 .
```

> **Note:** The `.deb` files are excluded from version control (`.gitignore`) because
> they are license-restricted binaries. Accept the SEGGER license when downloading.
