#!/usr/bin/env bash
# Build the Zephyr build-host container image with Podman.
#
# Usage:
#   ./build.sh
#
# Environment overrides:
#   IMAGE_NAME       image name                          (default: zephyr-build-host)
#   SDK_VER          Zephyr SDK version                  (default: 1.0.1)
#   ZEPHYR_VERSION   Zephyr tag/branch for requirements  (default: v4.4.0)
#   SDK_TOOLCHAINS   space-separated list of SDK toolchains to install
#                    (default: all)  e.g. SDK_TOOLCHAINS="arm-zephyr-eabi"
#   PYOCD_PACKS      space-separated list of pyOCD CMSIS packs to bake in
#                    (default: none)  e.g. PYOCD_PACKS="stm32u385rgtxq stm32f4"
#
# SEGGER tools support:
#   Place one or more SEGGER .deb packages in  segger_tools/  (J-Link, Ozone, …).
#   The script detects them automatically and enables installation inside the image.

set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-zephyr-build-host}"
SDK_VER="${SDK_VER:-1.0.1}"
ZEPHYR_VERSION="${ZEPHYR_VERSION:-v4.4.0}"

# Match container UID/GID to the current host user to avoid bind-mount
# permission issues.
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

BUILD_ARGS=(
    # Docker format is required for the SHELL instruction used in the Containerfile
    --format=docker
    --build-arg "ZEPHYR_SDK_VERSION=${SDK_VER}"
    --build-arg "ZEPHYR_VERSION=${ZEPHYR_VERSION}"
    --build-arg "USER_UID=${HOST_UID}"
    --build-arg "USER_GID=${HOST_GID}"
    --build-arg "ZEPHYR_SDK_TOOLCHAINS=${SDK_TOOLCHAINS:-all}"
    --build-arg "PYOCD_PACKS=${PYOCD_PACKS:-}"
    --tag "${IMAGE_NAME}:${ZEPHYR_VERSION}_sdk-${SDK_VER}"
    --file Containerfile
)

if ls segger_tools/*.deb &>/dev/null 2>&1; then
    echo "SEGGER .deb package(s) detected → enabling SEGGER tools installation."
    BUILD_ARGS+=(--build-arg INSTALL_SEGGER_TOOLS=1)
fi

echo "┌─────────────────────────────────────────────"
echo "│ Building image : ${IMAGE_NAME}:${ZEPHYR_VERSION}_sdk-${SDK_VER}"
echo "│ Zephyr SDK     : ${SDK_VER}"
echo "│ SDK toolchains : ${SDK_TOOLCHAINS:-all}"
echo "│ pyOCD packs    : ${PYOCD_PACKS:-(none)}"
echo "│ Container user : UID=${HOST_UID}  GID=${HOST_GID}"
echo "└─────────────────────────────────────────────"

podman build "${BUILD_ARGS[@]}" .

echo ""
echo "Build complete."
echo "  Start a build shell : ./run.sh [/path/to/zephyr-workspace]"
