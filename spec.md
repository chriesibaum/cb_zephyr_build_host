# Chriesibaum's Zephyr Build Host — Container Specification

## Purpose

A **tools-only** container image for building and flashing Zephyr RTOS firmware.
The Zephyr west workspace is mounted from the host at runtime; no source code lives
inside the image.

---

## Base Image

| Property | Value |
|---|---|
| Base OS | `ubuntu:24.04` |
| Container runtime | Podman (rootless) |
| Image format | Docker (`--format=docker`, required for `SHELL` instruction) |

---

## Installed Software

### System packages (apt)

| Category | Packages |
|---|---|
| Build tools | `build-essential`, `cmake`, `ninja-build`, `ccache`, `gcc-multilib`, `g++-multilib`, `libc6-dev-i386` |
| Python | `python3`, `python3-venv`, `python3-dev`, `python3-pip`, `python3-setuptools`, `python3-wheel` |
| Zephyr build deps | `device-tree-compiler`, `dfu-util`, `libsdl2-dev`, `libmagic1` |
| Debugging / flashing | `openocd`, `gdb-multiarch` |
| USB / serial | `libusb-1.0-0`, `libusb-dev`, `udev`, `libudev-dev`, `usbutils` (`lsusb`) |
| Utilities | `git`, `wget`, `curl`, `xz-utils`, `unzip`, `file`, `ca-certificates`, `openssh-client`, `bash-completion` |
| Locale | `locales` → `en_US.UTF-8` |

### Zephyr SDK

| Property | Value |
|---|---|
| Version | `1.0.1` (ARG `ZEPHYR_SDK_VERSION`) |
| Install path | `/opt/zephyr-sdk-1.0.1` |
| Toolchains | Configurable via ARG `ZEPHYR_SDK_TOOLCHAINS` (default: `all`); space-separated list passed as `-t <name>` to `setup.sh` |
| Host tools | QEMU, OpenOCD, BOSSA, DTC (`setup.sh -h`) |
| CMake registration | `~/.cmake/packages/ZephyrSDK/zephyr-sdk` |
| Archive verified | SHA-256 checksum against upstream `sha256.sum` |

### Python virtual environment

| Property | Value |
|---|---|
| Path | `~/.venv` |
| Activated in | `~/.bashrc` (interactive shells) |
| `PATH` | Prepended via `ENV PATH` |
| Contents | `west`, all five Zephyr requirements files from `zephyrproject-rtos/zephyr @ v4.4.0` (`requirements-base`, `-build-test`, `-run-test`, `-extras`, `-compliance`), `pyocd` |

### pyOCD CMSIS target-support packs

Packs are installed at build time into `CMSIS_PACK_ROOT` (`/pyocd-packs`) so
flashing works without a network connection.  Controlled by ARG `PYOCD_PACKS`
(default: empty — no packs baked in).  Example:

```bash
PYOCD_PACKS="stm32u385rgtxq" ./build.sh
PYOCD_PACKS="stm32u385rgtxq stm32f429zitx" ./build.sh
```

### SEGGER tools (optional)

Installed only when both conditions are met at build time:

1. One or more `.deb` packages are present in `segger_tools/`.
2. `build.sh` detects them and passes `--build-arg INSTALL_SEGGER_TOOLS=1`.

Supported packages (place in `segger_tools/`):

| File pattern | Tool |
|---|---|
| `JLink_Linux_V*_x86_64.deb` | J-Link suite |
| `Ozone_Linux_V*_x86_64.deb` | Ozone debugger (requires X server) |
| `SystemView_Linux_V*_x86_64.deb` | SystemView |

`udevadm` is stubbed to `/bin/true` during `dpkg` post-install (udevd is not
running in a container) and the stub is removed afterwards.

---

## Build Arguments (ARGs)

| ARG | Default | Description |
|---|---|---|
| `UBUNTU_VERSION` | `24.04` | Ubuntu base image tag |
| `ZEPHYR_SDK_VERSION` | `1.0.1` | Zephyr SDK release to download |
| `ZEPHYR_VERSION` | `v4.4.0` | Zephyr tag/branch for Python requirements |
| `USER_UID` | `1000` | UID of the container user |
| `USER_GID` | `1000` | GID of the container user |
| `USERNAME` | `calvin` | Username inside the container |
| `ZEPHYR_SDK_TOOLCHAINS` | `all` | Space-separated list of SDK toolchains to install |
| `PYOCD_PACKS` | *(empty)* | Space-separated list of pyOCD CMSIS packs to bake in |
| `INSTALL_SEGGER_TOOLS` | `0` | Set to `1` to install SEGGER .deb packages |

If UID/GID 1000 already exists (Ubuntu 24.04 ships a built-in `ubuntu` user),
the existing user/group is renamed instead of failing.

The container user is added to the `dialout` and `plugdev` groups.

---

## Environment Variables (baked into image)

| Variable | Value | Purpose |
|---|---|---|
| `CCACHE_DIR` | `/ccache` | Fixed ccache path; `run.sh` mounts the host cache here |
| `CMSIS_PACK_ROOT` | `/pyocd-packs` | pyOCD pack root; packs baked in at build time |
| `ZEPHYR_SDK_INSTALL_DIR` | `/opt/zephyr-sdk-<ver>` | Picked up by west / CMake |
| `ZEPHYR_TOOLCHAIN_VARIANT` | `zephyr` | Selects the Zephyr SDK toolchain |
| `VENV` | `~/.venv` | Python venv path |

---

## Image Labels (OCI)

| Label | Value |
|---|---|
| `org.opencontainers.image.title` | `Zephyr RTOS Build Host` |
| `org.opencontainers.image.description` | `Ubuntu <ver> build environment for Zephyr RTOS (SDK <ver>, …)` |
| `org.opencontainers.image.version` | SDK version |
| `org.opencontainers.image.base.name` | `ubuntu:<ver>` |
| `org.opencontainers.image.source` | `https://github.com/chriesibaum/cb_zephyr_build_host` |
| `io.zephyr.sdk.version` | SDK version |
| `io.zephyr.version` | Zephyr version |

Inspect with:
```bash
podman image inspect zephyr-build-host:v4.4.0_sdk-1.0.1 --format '{{json .Labels}}' | python3 -m json.tool
```

---

## Image Tag

After a successful `./build.sh` the image is tagged as:

```
zephyr-build-host:v4.4.0_sdk-1.0.1
```

i.e. `${IMAGE_NAME}:${ZEPHYR_VERSION}_sdk-${SDK_VER}`.

---

## Runtime Layout

| Path (inside container) | Content |
|---|---|
| `/workspace` | Bind-mount of the host west workspace (WORKDIR) |
| `/opt/zephyr-sdk-1.0.1` | Zephyr SDK |
| `~/.venv` | Python virtual environment |
| `~/.cmake/packages/ZephyrSDK/` | SDK CMake registration |
| `/ccache` | Bind-mount of host ccache directory |
| `/pyocd-packs` | pyOCD CMSIS pack root (baked-in or host-mounted override) |

---

## `build.sh`

Wrapper around `podman build`. Key behaviour:

- Passes host `UID`/`GID` as build args so file ownership matches the host user.
- Detects `segger_tools/*.deb` and enables SEGGER tools installation automatically.
- Forwards `SDK_TOOLCHAINS` and `PYOCD_PACKS` as build args.

Environment overrides:

```bash
IMAGE_NAME=zephyr-build-host          # image name
SDK_VER=1.0.1                         # Zephyr SDK version
ZEPHYR_VERSION=v4.4.0                 # Zephyr Python requirements version
SDK_TOOLCHAINS="arm-zephyr-eabi"      # toolchains to install (default: all)
PYOCD_PACKS="stm32u385rgtxq"          # pyOCD packs to bake in (default: none)
```

---

## `run.sh`

Wrapper around `podman run`. Key behaviour:

| Feature | Detail |
|---|---|
| UID mapping | `--userns=keep-id` — container UID/GID matches the host user; bind-mounted files remain writable |
| Workspace | First positional argument (default: `$PWD`) mounted at `/workspace` |
| Working directory | `WORK_DIR` env var sets the initial directory inside `/workspace` (e.g. `WORK_DIR=./app`) |
| Hostname | Set to `<host-fqdn>/<image-name>` for easy identification in the shell prompt |
| ccache | Host `CCACHE_DIR` (default `~/.cache/ccache`) mounted at `/ccache`; `CCACHE_DIR=/ccache` is set in the image |
| pyOCD packs | `PYOCD_PACKS_DIR` — if set, mounts a host directory over `/pyocd-packs` to replace baked-in packs (opt-in) |
| Git config | `~/.gitconfig` forwarded read-only to the container user's home |
| SSH agent | `SSH_AUTH_SOCK` forwarded if set — enables private repo clones |
| USB passthrough | `--device=/dev/bus/usb` + `--group-add keep-groups` (preserves host supplementary groups such as `plugdev`); **enabled by default** (`FLASH=1`) |
| Disk devices | `/dev/disk` mounted read-only when `FLASH=1` — suppresses mbed-ls "disk devices by id" warnings in pyOCD |
| X11 forwarding | `$DISPLAY`, `/tmp/.X11-unix`, and `~/.Xauthority` forwarded when `DISPLAY` is set — enables GUI tools (Ozone, J-Link GDB Server) |
| First-run notice | Warns once per image ID that Podman is creating an ID-mapped layer copy (can take several minutes) |

Environment overrides:

```bash
IMAGE=zephyr-build-host:v4.4.0_sdk-1.0.1  # image to run
CCACHE_DIR=~/.cache/ccache                # host ccache directory
PYOCD_PACKS_DIR=/path/to/packs            # host pyOCD pack directory override (optional)
FLASH=1                                   # 0 to disable USB passthrough
WORK_DIR=./app/subdir                     # initial working directory (relative to workspace)
```

### USB / flashing prerequisites (host)

The host user must have access to `/dev/bus/usb`. This is typically provided by:

1. Membership in the `plugdev` group (`sudo usermod -aG plugdev $USER`).
2. Appropriate udev rules for the probe (J-Link, ST-Link, CMSIS-DAP, …).

---

## Repository Layout

```
Containerfile          Container image definition
build.sh               Build wrapper (Podman)
run.sh                 Run wrapper (Podman)
segger_tools/
  README.md            Instructions for downloading SEGGER .deb packages
  *.deb                SEGGER installers (not committed, see .gitignore)
.dockerignore          Excludes .git/ from build context
.gitignore             Excludes segger_tools/*.deb and *.rpm from git
spec.md                This document
```
