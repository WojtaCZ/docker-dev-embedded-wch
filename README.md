# docker-dev-embedded-wch

WCH CH32V development container for bare-metal C++. Targets **CH32V003**, **CH32V203**, **CH32V303**, and compatible WCH RISC-V devices (RV32EC ISA, QingKe core). Uses `ch32v003fun` as minimal bare-metal scaffolding.

Inherits from `docker-dev-embedded-base` which provides all probe tools.

## What this image adds

- `riscv-none-elf-g++` (C++20, bare metal, newlib, RV32EC)
- `ch32v003fun` scaffolding at `/opt/ch32v003fun` (`$CH32V_FUN`)
- `wlink` CLI for WCH-Link flashing and debugging
- 3 WCH-specific Claude skills (low power, C++ template, RISC-V CSR cheatsheet)

## Quick start

```bash
# 1. One-time host setup (first time only)
sudo ./scripts/install-host-udev-rules.sh   # from docker-dev-embedded-base
sudo usermod -aG dialout,plugdev $USER       # log out and back in

# 2. Plug in your WCH-Link probe

# 3. Build and start the container
./scripts/dev-up.sh /path/to/your/firmware

# 4. Inside the container, scaffold a new project
/scaffold-mcu-project wch

# 5. Build
/opt/embedded/run-profile-task.sh build

# 6. Flash
/opt/embedded/run-profile-task.sh flash
```

## WCH-Link probe

WCH-Link enumerates as a USB device (`0x1a86:0x8010` or `0x8012`). Verify:
```bash
/probe-detect
wlink info
```

Flash a binary:
```bash
wlink flash build/firmware.bin
```

Start openocd for debug:
```bash
openocd -f interface/wlink-rs.cfg -f target/wch-riscv.cfg
# Then in another terminal:
riscv-none-elf-gdb build/firmware.elf -ex "target extended-remote :3333"
```

## ch32v003fun

The scaffolding at `/opt/ch32v003fun` provides:
- `ch32v003fun.h` — peripheral register definitions, SysTick, GPIO, UART, SPI, I2C
- `ch32v003fun.c` — startup code, `SystemInit()`, `Delay_Ms()`
- Example projects in `examples/`

Copy an example to start:
```bash
cp -r $CH32V_FUN/examples/blink /workspace/my_project
cd /workspace/my_project
make -j$(nproc)
wlink flash blink.bin
```

See the `ch32fun-cpp-template` Claude skill for adding C++ to a ch32v003fun project.

## Template update propagation

This image tracks `ghcr.io/wojtacz/docker-dev-embedded-base:latest`. `dev-up.sh` passes `--pull` by default. CI rebuilds automatically via `repository_dispatch` from the base image.
