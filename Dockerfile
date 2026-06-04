# syntax=docker/dockerfile:1.7
FROM ghcr.io/wojtacz/docker-dev-embedded-base:latest

USER root

# RISC-V cross toolchain (g++, newlib) — prebuilt binary from AUR, fast to install
# Covers: WCH CH32V003, CH32V203, CH32V303, CH32X033
RUN su aurbuild -c "paru -S --noconfirm --needed riscv-none-elf-gcc-bin"

# ch32v003fun — community bare-metal scaffolding for WCH CH32V
# Header + minimal startup, no MounRiver / no vendor HAL.
# Provides a working build system for CH32V003 and compatible devices.
RUN git clone --depth=1 https://github.com/cnlohr/ch32v003fun /opt/ch32v003fun
ENV CH32V_FUN=/opt/ch32v003fun

# Default MCU profile (copied to workspace by /scaffold-mcu-project wch)
COPY profile.json /opt/embedded/profile.json

USER dev

# Stack WCH-specific Claude config on top of the embedded-base layer.
COPY --chown=dev:dev claude-embedded-wch/skills/      /home/dev/.claude/skills/
COPY --chown=dev:dev claude-embedded-wch/settings.json /home/dev/.claude/settings.json

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
