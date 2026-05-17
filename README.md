
# Chriesibaum's Zephyr Build Host

A rootless **Podman** container image for building and flashing [Zephyr RTOS](https://zephyrproject.org/) firmware.
Your west workspace lives on the host and is mounted in at runtime — nothing is baked into the image except the toolchain.

**What's inside the image**

- Ubuntu 24.04
- Zephyr SDK 1.0.1 (selectable toolchains + host tools / QEMU)
- west, all Zephyr Python requirements (v4.4.0), pyOCD
- OpenOCD, GDB multiarch
- ccache, git, bash-completion

---

## Requirements

- [Podman](https://podman.io/) (rootless, tested on Linux)

---

## Quick Start

```bash
# Build the image (ARM toolchain, STM32U385 pyOCD pack)
SDK_TOOLCHAINS="arm-zephyr-eabi" PYOCD_PACKS="stm32u385rgtxq" ./build.sh

SDK_TOOLCHAINS="arm-zephyr-eabi riscv64-zephyr-elf" PYOCD_PACKS="stm32u385rgtxq" ./build.sh

# Drop into a build shell with your workspace mounted
./run.sh /path/to/your/zephyr-workspace
```

---

## Building the Image

```bash
./build.sh
```

All options are controlled by environment variables:

| Variable | Default | Description |
|---|---|---|
| `IMAGE_NAME` | `zephyr-build-host` | Image name |
| `SDK_VER` | `1.0.1` | Zephyr SDK version |
| `ZEPHYR_VERSION` | `v4.4.0` | Zephyr tag for Python requirements |
| `SDK_TOOLCHAINS` | `all` | Space-separated list of toolchains to install |
| `PYOCD_PACKS` | *(none)* | Space-separated list of pyOCD CMSIS packs to bake in |

### Toolchain selection

Install only the toolchains you need to keep the image small:

```bash
# ARM Cortex-M only (most common)
SDK_TOOLCHAINS="arm-zephyr-eabi" ./build.sh

# ARM + RISC-V (e.g. for RP2040 / RP2350)
SDK_TOOLCHAINS="arm-zephyr-eabi riscv64-zephyr-elf" ./build.sh

# Everything
./build.sh
```

Available toolchains: `arm-zephyr-eabi`, `aarch64-zephyr-elf`, `riscv64-zephyr-elf`,
`x86_64-zephyr-elf`, `xtensa-espressif_esp32_zephyr-elf`, and more — see the header
of [`Containerfile`](Containerfile) for the full list.

### pyOCD CMSIS target packs

Pre-install target support packs so `pyocd flash` works offline:

```bash
PYOCD_PACKS="stm32u385rgtxq" ./build.sh
PYOCD_PACKS="stm32u385rgtxq stm32f429zitx" ./build.sh
```

Without this, packs can still be installed manually inside a running container with:

```bash
pyocd pack update
pyocd pack install stm32u385rgtxq
```

> **Note:** manually installed packs are lost when the container exits.
> Use `PYOCD_PACKS` at build time for permanent availability.

### SEGGER tools (J-Link, Ozone, SystemView)

Place the SEGGER `.deb` installers in `segger_tools/` before building.
`build.sh` detects them automatically and enables installation:

```
segger_tools/JLink_Linux_V<ver>_x86_64.deb
segger_tools/Ozone_Linux_V<ver>_x86_64.deb
segger_tools/SystemView_Linux_V<ver>_x86_64.deb
```

Download from [segger.com/downloads/jlink](https://www.segger.com/downloads/jlink/).
See [`segger_tools/README.md`](segger_tools/README.md) for details.
The `.deb` files are excluded from git (see `.gitignore`).

---

## Running the Container

```bash
./run.sh [/path/to/zephyr-workspace]   # default: current directory
```

| Variable | Default | Description |
|---|---|---|
| `IMAGE` | `zephyr-build-host:v4.4.0_sdk-1.0.1` | Image reference to run |
| `WORK_DIR` | *(workspace root)* | Initial directory inside the container, relative to the workspace mount |
| `CCACHE_DIR` | `~/.cache/ccache` | Host ccache directory |
| `PYOCD_PACKS_DIR` | *(unset)* | Mount a host directory over `/pyocd-packs` to replace baked-in packs |
| `FLASH` | `1` | Set to `0` to disable USB device passthrough |

### Examples

```bash
# Basic — mount current directory as workspace
./run.sh

# Specify a workspace and start inside a sub-project
WORK_DIR=./cb_black_box.fw/app ./run.sh ../cb_black_box.workspace/

# Use a specific image version
IMAGE="zephyr-build-host:v4.4.0_sdk-1.0.1" ./run.sh /path/to/workspace

# Disable USB passthrough (build only, no flashing)
FLASH=0 ./run.sh /path/to/workspace
```

### What run.sh sets up

| Feature | Detail |
|---|---|
| **UID mapping** | `--userns=keep-id` — files created inside the container are owned by your host user |
| **Workspace** | Mounted at `/workspace`; writable |
| **ccache** | Host cache mounted at `/ccache` — speeds up rebuilds across container restarts |
| **USB passthrough** | `--device=/dev/bus/usb` + `--group-add keep-groups` — preserves `plugdev` membership for probe access |
| **Git config** | `~/.gitconfig` forwarded read-only |
| **SSH agent** | `SSH_AUTH_SOCK` forwarded — private repo clones work |
| **X11** | `$DISPLAY` + `/tmp/.X11-unix` forwarded — GUI tools (Ozone, J-Link GDB Server) open on your desktop |
| **Hostname** | `<host-fqdn>/<image-name>` — visible in the shell prompt |

### USB / flashing prerequisites (host)

```bash
# Add yourself to the plugdev group (once)
sudo usermod -aG plugdev $USER
# Then log out and back in, or run:
newgrp plugdev
```

Probe-specific udev rules (J-Link, ST-Link, CMSIS-DAP) are also required on the host.

---

## First-Time West Workspace Setup

Inside the container:

```bash
# Initialise a new workspace
west init .
west update

# Build the hello_world sample
west build -b <board> zephyr/samples/hello_world
```

---

## Flashing

```bash
# pyOCD (CMSIS-DAP / ST-Link)
west flash -r pyocd

# OpenOCD
west flash -r openocd

# J-Link
west flash -r jlink
```

---

## Shell Aliases

The following aliases are defined in the container's `~/.bashrc`:

| Alias | Command |
|---|---|
| `mm` | `make all` |
| `mc` | `make clean` |
| `mf` | `make flash` |

---

## Repository Layout

```
Containerfile          Image definition
build.sh               Build wrapper
run.sh                 Run wrapper
segger_tools/
  README.md            Download instructions for SEGGER .deb packages
  *.deb                Not committed (see .gitignore)
.dockerignore          Excludes .git/ from build context
.gitignore             Excludes segger_tools/*.deb / *.rpm
spec.md                Full technical specification
README_podman.md       Podman quick-reference
LICENSE                Apache 2.0
```

---

## Podman Quick Reference

```bash
# List images
podman images

# Remove an image
podman rmi -f <ID>

# Remove all unused images / containers / volumes
podman system prune

# Remove everything including unused images
podman system prune --all
```

---

## License

[Apache 2.0](LICENSE)
