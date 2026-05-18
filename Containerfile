# ──────────────────────────────────────────────────────────────────────────────
# Zephyr RTOS Build Host
#
# Base OS : Ubuntu 24.04
# SDK     : Zephyr SDK 1.0.1  (selected toolchains + host tools / QEMU)
# Extras  : west · OpenOCD · pyOCD · J-Link (optional, see below)
#
# ── Toolchain selection ────────────────────────────────────────────────────────
# Edit ZEPHYR_SDK_TOOLCHAINS below (space-separated).  Use  all  for everything
# or pick individual toolchains to reduce image size:
#
#   arm-zephyr-eabi                      ARM Cortex-M / Cortex-R  (most common)
#   aarch64-zephyr-elf                   ARM Cortex-A / 64-bit
#   riscv64-zephyr-elf                   RISC-V (32 and 64-bit)
#   x86_64-zephyr-elf                    x86 / x86_64
#   xtensa-espressif_esp32_zephyr-elf    ESP32
#   xtensa-espressif_esp32s2_zephyr-elf  ESP32-S2
#   xtensa-espressif_esp32s3_zephyr-elf  ESP32-S3
#   arc-zephyr-elf                       ARC (32-bit)
#   arc64-zephyr-elf                     ARC (64-bit)
#   mips-zephyr-elf                      MIPS
#   nios2-zephyr-elf                     Nios II
#   sparc-zephyr-elf                     SPARC / LEON
#   xtensa-dc233c_zephyr-elf             Xtensa DC233C
#   xtensa-intel_ace15_mtpm_zephyr-elf   Intel ADSP ACE 1.5
#   xtensa-intel_tgl_adsp_zephyr-elf     Intel TGL ADSP
#   xtensa-sample_controller_zephyr-elf  Xtensa sample controller
#
# ── SEGGER tools (optional) ───────────────────────────────────────────────────
#   Place one or more SEGGER .deb packages in  segger_tools/  (beside this file):
#     JLink_Linux_V<ver>_x86_64.deb    J-Link suite
#     Ozone_Linux_V<ver>_x86_64.deb    Ozone debugger (requires X server)
#     SystemView_Linux_V<ver>_x86_64.deb
#   All .deb files found there are installed automatically by  ./build.sh
#
# Build:
#   ./build.sh
# ──────────────────────────────────────────────────────────────────────────────

ARG UBUNTU_VERSION=24.04
FROM ubuntu:${UBUNTU_VERSION}

# Re-declare after FROM so they are available in this build stage
ARG UBUNTU_VERSION
# Zephyr and SDK version used to fetch Python requirements (tag or branch name)
ARG ZEPHYR_VERSION=v4.4.0
ARG ZEPHYR_SDK_VERSION=1.0.1

# Match host UID/GID so bind-mounted workspace files are owned by the right user
ARG USER_UID=1000
ARG USER_GID=1000
ARG USERNAME=calvin

# Space-separated list of SDK toolchains to install.
# Use  all  to install every toolchain, or list specific ones (see header above).
ARG ZEPHYR_SDK_TOOLCHAINS=all

LABEL org.opencontainers.image.title="Zephyr RTOS Build Host" \
      org.opencontainers.image.description="Ubuntu ${UBUNTU_VERSION} build environment for Zephyr RTOS (SDK ${ZEPHYR_SDK_VERSION}, west, OpenOCD, pyOCD)" \
      org.opencontainers.image.version="${ZEPHYR_SDK_VERSION}" \
      org.opencontainers.image.base.name="ubuntu:${UBUNTU_VERSION}" \
      org.opencontainers.image.source="https://github.com/chriesibaum/cb_zephyr_build_host" \
      io.zephyr.sdk.version="${ZEPHYR_SDK_VERSION}" \
      io.zephyr.version="${ZEPHYR_VERSION}"

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    LANG=en_US.UTF-8 \
    ZEPHYR_SDK_INSTALL_DIR=/opt/zephyr-sdk-${ZEPHYR_SDK_VERSION} \
    ZEPHYR_TOOLCHAIN_VARIANT=zephyr

# ── System packages ────────────────────────────────────────────────────────────
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      # Build tools
      build-essential \
      cmake \
      ninja-build \
      ccache \
        # 32-bit development support for native_sim / -m32 builds
        gcc-multilib \
        g++-multilib \
        libc6-dev-i386 \
      # Python
      python3 \
      python3-pip \
      python3-venv \
      python3-dev \
      python3-setuptools \
      python3-wheel \
      # Zephyr build dependencies
      device-tree-compiler \
      dfu-util \
      libsdl2-dev \
      libmagic1 \
      # Debugging & flashing
      openocd \
      gdb-multiarch \
      # USB / serial access (pyOCD, J-Link, OpenOCD)
      libusb-1.0-0 \
      libusb-dev \
      usbutils \
      udev \
      libudev-dev \
      # Utilities
      git \
      wget \
      curl \
      xz-utils \
      unzip \
      file \
      locales \
      ca-certificates \
      openssh-client \
      bash-completion \
 && locale-gen en_US.UTF-8 \
 && rm -rf /var/lib/apt/lists/*

# ── Non-root builder user ──────────────────────────────────────────────────────
# Ubuntu 24.04 ships a default 'ubuntu' user/group at UID/GID 1000.
# If the requested UID/GID already exists we rename it instead of failing.
RUN \
    if getent group "${USER_GID}" > /dev/null 2>&1; then \
        OLD_GROUP="$(getent group "${USER_GID}" | cut -d: -f1)"; \
        [ "${OLD_GROUP}" != "${USERNAME}" ] && groupmod -n "${USERNAME}" "${OLD_GROUP}"; \
    else \
        groupadd --gid "${USER_GID}" "${USERNAME}"; \
    fi \
 && if getent passwd "${USER_UID}" > /dev/null 2>&1; then \
        OLD_USER="$(getent passwd "${USER_UID}" | cut -d: -f1)"; \
        if [ "${OLD_USER}" != "${USERNAME}" ]; then \
            usermod --login "${USERNAME}" \
                    --home "/home/${USERNAME}" --move-home \
                    --shell /bin/bash "${OLD_USER}"; \
        fi; \
    else \
        useradd --uid "${USER_UID}" --gid "${USER_GID}" -m -s /bin/bash "${USERNAME}"; \
    fi \
 && usermod  -aG dialout "${USERNAME}" \
 && (usermod -aG plugdev "${USERNAME}" 2>/dev/null || true)

# ── Zephyr SDK ─────────────────────────────────────────────────────────────────
# Downloads the minimal bundle and uses setup.sh to install selected toolchains.
#   -t <name>  repeated for each entry in ZEPHYR_SDK_TOOLCHAINS (or  all )
#   -h         host tools: patched QEMU, OpenOCD, BOSSA, DTC
RUN set -eux; \
    BASE_URL="https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v${ZEPHYR_SDK_VERSION}"; \
    ARCHIVE="zephyr-sdk-${ZEPHYR_SDK_VERSION}_linux-x86_64_minimal.tar.xz"; \
    wget -nv "${BASE_URL}/${ARCHIVE}"  -O "/tmp/${ARCHIVE}"; \
    wget -nv "${BASE_URL}/sha256.sum"  -O /tmp/sha256.sum; \
    ( cd /tmp && sha256sum --check --ignore-missing sha256.sum ); \
    tar -xf "/tmp/${ARCHIVE}" -C /opt; \
    rm "/tmp/${ARCHIVE}" /tmp/sha256.sum; \
    TC_ARGS=(); \
    for tc in ${ZEPHYR_SDK_TOOLCHAINS}; do TC_ARGS+=(-t "${tc}"); done; \
    "/opt/zephyr-sdk-${ZEPHYR_SDK_VERSION}/setup.sh" "${TC_ARGS[@]}" -h; \
    chown -R "${USERNAME}:${USERNAME}" "/opt/zephyr-sdk-${ZEPHYR_SDK_VERSION}"

# Register the Zephyr SDK CMake package for the builder user so that
# 'west build' can locate the SDK without extra environment tweaks.
USER ${USERNAME}
RUN mkdir -p "/home/${USERNAME}/.cmake/packages/ZephyrSDK" \
 && printf '/opt/zephyr-sdk-%s\n' "${ZEPHYR_SDK_VERSION}" \
      > "/home/${USERNAME}/.cmake/packages/ZephyrSDK/zephyr-sdk"

# ── Python virtual environment: west + Zephyr Python requirements ─────────────
ENV VENV=/home/${USERNAME}/.venv

RUN python3 -m venv "${VENV}" \
 && "${VENV}/bin/pip" install --upgrade pip setuptools wheel \
    \
    # ── Download all Zephyr requirements files into one temp directory so
    #    the cross-file  -r requirements-base.txt  references resolve correctly.
 && REQDIR="$(mktemp -d)" \
 && BASE="https://raw.githubusercontent.com/zephyrproject-rtos/zephyr/${ZEPHYR_VERSION}/scripts" \
 && for f in \
        requirements-base.txt \
        requirements-build-test.txt \
        requirements-run-test.txt \
        requirements-extras.txt \
        requirements-compliance.txt; \
    do \
        wget -nv -O "${REQDIR}/${f}" "${BASE}/${f}" 2>/dev/null || true; \
    done \
    \
    # Install in dependency order: base first, then the rest
 && "${VENV}/bin/pip" install -r "${REQDIR}/requirements-base.txt" \
 && "${VENV}/bin/pip" install \
        -r "${REQDIR}/requirements-build-test.txt" \
        -r "${REQDIR}/requirements-run-test.txt" \
        -r "${REQDIR}/requirements-extras.txt" \
        -r "${REQDIR}/requirements-compliance.txt" \
 && rm -rf "${REQDIR}" \
    \
    # Tools not covered by the requirements files
 && "${VENV}/bin/pip" install pyocd

# Activate the venv and enable bash completion in interactive shells
RUN printf '\n# Zephyr venv\nsource %s/bin/activate\n\n# Bash tab completion\n[ -f /usr/share/bash-completion/bash_completion ] && source /usr/share/bash-completion/bash_completion\n\n# Aliases\nalias mm='"'"'make all'"'"'\nalias mc='"'"'make clean'"'"'\nalias mf='"'"'make flash'"'"'\n' "${VENV}" \
      >> "/home/${USERNAME}/.bashrc"

# Fixed paths for host-mounted persistent caches (avoids depending on USERNAME at run time).
# run.sh mounts the host directories here and sets these env vars for the container.
ENV CCACHE_DIR=/ccache \
    CMSIS_PACK_ROOT=/pyocd-packs

ENV PATH="${VENV}/bin:${PATH}"

# ── pyOCD CMSIS target-support packs ─────────────────────────────────────────
# Packs are installed into CMSIS_PACK_ROOT (/pyocd-packs) at build time so
# flashing works without a network connection or manual pack installation.
# Override the list at build time:
#   --build-arg PYOCD_PACKS="stm32u385rgtxq stm32f429zitx"
ARG PYOCD_PACKS=""
RUN if [[ -n "${PYOCD_PACKS}" ]]; then \
        "${VENV}/bin/pyocd" pack update \
     && for pack in ${PYOCD_PACKS}; do \
            "${VENV}/bin/pyocd" pack install "${pack}"; \
        done; \
    fi

# ── Optional SEGGER tools installation ───────────────────────────────────────
# The segger_tools/ directory is always copied (it may contain only README.md).
# Set --build-arg INSTALL_SEGGER_TOOLS=1 *and* supply at least one .deb to install.
# udevadm is stubbed during install because udevd is not running in a container.
USER root
ARG INSTALL_SEGGER_TOOLS=0
COPY segger_tools/ /tmp/segger_tools/
RUN mapfile -t SEGGER_DEBS < <(find /tmp/segger_tools -maxdepth 1 -name '*.deb' 2>/dev/null | sort); \
    if [[ "${INSTALL_SEGGER_TOOLS}" == "1" && "${#SEGGER_DEBS[@]}" -gt 0 ]]; then \
        apt-get update \
     && ln -sf /bin/true /usr/bin/udevadm \
     && apt-get install -y --no-install-recommends "${SEGGER_DEBS[@]}" \
     && rm -f /usr/bin/udevadm \
     && rm -rf /var/lib/apt/lists/*; \
    fi \
 && rm -rf /tmp/segger_tools

# ── Final image setup ─────────────────────────────────────────────────────────
USER ${USERNAME}
WORKDIR /workspace

LABEL org.opencontainers.image.title="Zephyr Build Host" \
      org.opencontainers.image.description="Zephyr RTOS build environment – SDK ${ZEPHYR_SDK_VERSION} on Ubuntu ${UBUNTU_VERSION}" \
      org.opencontainers.image.version="${ZEPHYR_SDK_VERSION}" \
      org.opencontainers.image.source="https://github.com/chriesibaum/cb_zephyr_build_host"

CMD ["/bin/bash"]
