# syntax=docker/dockerfile:1.7
ARG BASE_TAG=latest
FROM ghcr.io/wojtacz/docker-dev-embedded-base:${BASE_TAG}

USER root

# Pinned upstream versions. Everything here comes from an official prebuilt
# release tarball, so this image needs no AUR helper at all — the previous
# `paru` bootstrap (and its `wlink-bin` / `probe-rs-bin` packages, neither of
# which exists in the AUR) is gone.
ARG RISCV_GCC_VERSION=15.2.0-1
ARG WLINK_VERSION=v0.1.2
ARG WCHISP_VERSION=v0.3.0
ARG CH32FUN_REF=master

# ---------------------------------------------------------------------------
# RISC-V cross toolchain — xPack prebuilt (GCC + newlib, RV32EC through RV32IMAC).
# Covers WCH CH32V003 / V103 / V203 / V303 / X033 and compatible QingKe cores.
# ---------------------------------------------------------------------------
RUN mkdir -p /opt/riscv && \
    curl -fsSL -o /tmp/riscv.tar.gz \
      "https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v${RISCV_GCC_VERSION}/xpack-riscv-none-elf-gcc-${RISCV_GCC_VERSION}-linux-x64.tar.gz" && \
    tar -xzf /tmp/riscv.tar.gz -C /opt/riscv --strip-components=1 && \
    rm /tmp/riscv.tar.gz && \
    # Symlink onto the default PATH. launch.json and the shared skills expect
    # riscv-none-elf-* to resolve without a bespoke PATH entry.
    for b in /opt/riscv/bin/riscv-none-elf-*; do \
        ln -sf "$b" "/usr/local/bin/$(basename "$b")"; \
    done && \
    riscv-none-elf-gcc --version && \
    riscv-none-elf-gdb --version

# ---------------------------------------------------------------------------
# wlink — WCH-Link flashing and debugging (also provides a GDB server).
# ---------------------------------------------------------------------------
RUN curl -fsSL -o /tmp/wlink.tar.gz \
      "https://github.com/ch32-rs/wlink/releases/download/${WLINK_VERSION}/wlink-${WLINK_VERSION}-linux-x64.tar.gz" && \
    tar -xzf /tmp/wlink.tar.gz -C /tmp && \
    install -m0755 "$(find /tmp -name wlink -type f | head -1)" /usr/local/bin/wlink && \
    rm -rf /tmp/wlink* && \
    wlink --version

# ---------------------------------------------------------------------------
# wchisp — USB bootloader flashing. Works with NO probe at all: CH32V parts
# expose a factory USB ISP bootloader, which is the difference between "I need
# a WCH-Link" and "I need a USB cable".
# ---------------------------------------------------------------------------
RUN curl -fsSL -o /tmp/wchisp.tar.gz \
      "https://github.com/ch32-rs/wchisp/releases/download/${WCHISP_VERSION}/wchisp-${WCHISP_VERSION}-linux-x64.tar.gz" && \
    tar -xzf /tmp/wchisp.tar.gz -C /tmp && \
    install -m0755 "$(find /tmp -name wchisp -type f | head -1)" /usr/local/bin/wchisp && \
    rm -rf /tmp/wchisp* && \
    wchisp --version || true

# ---------------------------------------------------------------------------
# ch32fun (formerly ch32v003fun) — community bare-metal scaffolding.
# Header + minimal startup, no MounRiver, no vendor HAL. Now covers the whole
# CH32V/CH32X range, not just the V003.
# ---------------------------------------------------------------------------
RUN git clone --depth=1 --branch "${CH32FUN_REF}" \
        https://github.com/cnlohr/ch32fun /opt/ch32fun && \
    rm -rf /opt/ch32fun/.git && \
    ln -sfn /opt/ch32fun /opt/ch32v003fun
ENV CH32FUN=/opt/ch32fun \
    CH32V_FUN=/opt/ch32fun

# WCH-Link udev rules (host install only — udev does not run in a container)
COPY udev-rules/ /opt/embedded/udev-rules/
COPY scripts/install-host-udev-rules.sh /opt/embedded/install-host-udev-rules.sh
RUN chmod +x /opt/embedded/install-host-udev-rules.sh

# Default MCU profile and the RISC-V CMake toolchain file
COPY profile.json /opt/embedded/profile.json
COPY cmake/toolchains/ /opt/embedded/cmake/toolchains/

# dev-doctor checks contributed by this layer
COPY dev-doctor-checks/ /opt/dev-doctor/checks.d/
RUN chmod +x /opt/dev-doctor/checks.d/*.sh

USER dev

# Stack WCH-specific Claude config on top of the embedded-base layer.
COPY --chown=dev:dev claude-embedded-wch/skills/   /home/dev/.claude/skills/
COPY --chown=dev:dev claude-embedded-wch/commands/ /home/dev/.claude/commands/
COPY --chown=dev:dev claude-embedded-wch/settings.layer.json \
     /home/dev/.claude-layers/20-wch.json

# Memory layer: the RISC-V/WCH tool inventory, concatenated into
# ~/.claude/CLAUDE.md by entrypoint.sh.
COPY --chown=dev:dev claude-embedded-wch/CLAUDE.layer.md \
     /home/dev/.claude-memory-layers/20-wch.md

# Makes the inherited binutils-driven skills resolve to the RISC-V toolchain.
ENV CROSS_PREFIX=riscv-none-elf-

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
