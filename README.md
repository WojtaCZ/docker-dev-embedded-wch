# docker-dev-embedded-wch

WCH RISC-V development container for bare-metal C++. Targets **CH32V003**,
**CH32V103**, **CH32V203**, **CH32V303** and **CH32X033** (QingKe cores,
RV32EC through RV32IMAFC). Uses `ch32fun` as minimal bare-metal scaffolding —
no MounRiver, no vendor HAL.

Inherits `docker-dev-embedded-base`, which provides openocd, gdb, clang tooling,
the `mcu` task runner and the shared VSCode templates.

> Design rationale and verified issues: [`WRITEUP.md`](WRITEUP.md).

## What this image adds

| | |
| --- | --- |
| Toolchain | `riscv-none-elf-gcc/g++/gdb` — xPack prebuilt, GCC 15.x + newlib |
| `wlink` | WCH-Link flash / erase / reset / GDB server |
| `wchisp` | **Probe-free** flashing over the factory USB bootloader |
| `ch32fun` | `/opt/ch32fun` → `$CH32FUN` (whole CH32V/CH32X range, not just V003) |
| CMake | `/opt/embedded/cmake/toolchains/riscv-none-elf.cmake` |
| Claude | 5 skills, `/ch32-new-project` command |
| `CROSS_PREFIX` | `riscv-none-elf-`, so the inherited binutils skills work here |

Everything above comes from an **official prebuilt release tarball**, so this
image needs no AUR helper — the old `paru` bootstrap and its `wlink-bin` /
`probe-rs-bin` packages (neither of which exists in the AUR) are gone, along
with several minutes of CI time.

## Quick start

```bash
# 1. One-time host setup
sudo ./scripts/install-host-udev-rules.sh
sudo usermod -aG dialout,plugdev $USER      # log out and back in

# 2. Plug in the WCH-Link FIRST — /dev/bus/usb is bind-mounted at container start

# 3. Start the container
./scripts/dev-up.sh /path/to/your/firmware

# 4. Inside: create a project from a part number
/ch32-new-project CH32V003F4P6

# 5. Build, check size, flash
mcu build
mcu size
mcu flash
```

`dev-doctor` verifies the toolchain, multilibs, flash tools and probe visibility.

## Know your part before you build

The V003 is **not** representative of the range, and the two knobs that matter
cannot be guessed:

| Part | Core | `march` | `mabi` | Flash | SRAM |
| --- | --- | --- | --- | --- | --- |
| CH32V003 | QingKe V2A | `rv32ec_zicsr` | `ilp32e` | 16 KB | 2 KB |
| CH32V103 | QingKe V3A | `rv32imac_zicsr` | `ilp32` | 32–64 KB | 10–20 KB |
| CH32V203 | QingKe V4B | `rv32imac_zicsr` | `ilp32` | 32–64 KB | 10–20 KB |
| CH32V303 | QingKe V4F | `rv32imafc_zicsr` | `ilp32f` | 62–128 KB | 32 KB |
| CH32X033 | QingKe V4C | `rv32imac_zicsr` | `ilp32` | 62 KB | 20 KB |

`ilp32e` (RV32E, **16 registers**) and `ilp32` are not link-compatible, and
RV32EC has **no hardware multiply**. Build a V003 as `rv32imac` and it links
cleanly, then executes illegal instructions on the device. The CMake toolchain
file refuses to configure without both `RISCV_MARCH` and `RISCV_MABI`, and
rejects the rv32e/ilp32 mismatch outright.

The `ch32v-family-differences` skill has the full comparison, including the
interrupt controller (PFIC, not PLIC) and the HPE difference between V2A and V4
cores.

## Two ways to flash

```bash
# With a WCH-Link probe
wlink info
mcu flash                      # wlink flash build/firmware.bin

# With NO probe at all — the factory USB ISP bootloader in ROM.
# Hold BOOT0 (PD7 on the V003) while connecting USB.
wchisp probe
wchisp flash build/firmware.bin
```

`wchisp` is also the recovery path when SWIO stops responding. Swap the profile
to the `_wchisp_variant` command set to make it the default.

### When SWIO stops working

On the CH32V003 SWIO is **PD1**, which is also a GPIO. Firmware that configures
PD1 as an output disables the debug interface at the moment it starts running —
"I flashed once and now it will not connect". `wlink` can win the race by
holding reset:

```bash
wlink erase --method pin-rst
wlink --speed low erase chip
```

Failing that, use `wchisp` — the ROM bootloader cannot be disabled by firmware.
The `ch32v-flash-verify` skill walks the whole decision tree, and is worth
reading before you need it.

## Build systems

**ch32fun Makefile** (default) — the well-trodden path:

```bash
cp -r $CH32FUN/examples/blink/* .          # V003
cp -r $CH32FUN/examples_v20x/blink/* .     # V203 — the V003 examples do NOT build for it
make -j$(nproc)
```

**CMake** — same `tasks.json` / `launch.json` flow as the arm leaf. Take the
commands from `_cmake_variant` in `profile.json`:

```bash
cmake -S . -B build -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE=/opt/embedded/cmake/toolchains/riscv-none-elf.cmake \
  -DRISCV_MARCH=rv32ec_zicsr -DRISCV_MABI=ilp32e
```

See the `ch32fun-cpp-template` skill for adding C++ to a ch32fun project.

## Debugging

```bash
wlink gdbserver --port 3333
# in another terminal
riscv-none-elf-gdb build/firmware.elf -ex "target extended-remote :3333"
```

Or use the VSCode "Debug (GDB / RISC-V)" launch configuration — it resolves the
debugger through `CROSS_GDB`, which `mcu --export` derives from `CROSS_PREFIX`,
so there is no hard-coded path to get wrong.

## Claude skills (5)

| Skill | Covers |
| --- | --- |
| `ch32v-family-differences` | V003 vs V103/V203/V303/X033 — ISA, ABI, memory, peripherals, PFIC/HPE |
| `ch32v-flash-verify` | WCH-Link and SWIO troubleshooting, locked-chip recovery, trap decoding |
| `ch32fun-cpp-template` | Adding C++ to a ch32fun project |
| `ch32v-low-power` | CH32V power modes |
| `riscv-csr-cheatsheet` | QingKe CSRs |

Plus the 11 architecture-neutral skills inherited from `embedded-base`
(`hardfault-decode` includes the RISC-V `mcause` table).

## CI

Every push builds the image and then cross-compiles a real **CH32V003 (RV32EC)**
firmware inside it, asserts via `readelf -A` that the output really is RV32E,
checks `.init_array` survives, verifies the size budget is enforced against the
16 KB / 2 KB limits, confirms the toolchain file rejects an ABI mismatch, and
builds a CH32V203 RV32IMAC image as well. Nothing publishes unless it all passes.

## Update propagation

Tracks `ghcr.io/wojtacz/docker-dev-embedded-base:${BASE_TAG}` (default `latest`;
`DEV_CHANNEL=stable` for the promoted channel). CI rebuilds on a
`repository_dispatch` from the base image and reports `downstream-verified` back.
