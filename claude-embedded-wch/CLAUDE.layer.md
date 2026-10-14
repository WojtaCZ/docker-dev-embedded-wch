
---

## WCH layer (`docker-dev-embedded-wch`)

WCH QingKe RISC-V target image: CH32V003 / V103 / V203 / V303 / X033 and
compatible cores.

`$CROSS_PREFIX` = `riscv-none-elf-`

| Area | What is here |
|---|---|
| Toolchain | `riscv-none-elf-gcc`/`g++`/`gdb` + newlib, xPack prebuilt under `/opt/riscv`, symlinked onto `PATH`. Covers RV32EC through RV32IMAC |
| Probe flashing | `wlink` — WCH-Link flash, debug, and a GDB server |
| **No-probe flashing** | `wchisp` — drives the factory USB ISP bootloader every CH32V part exposes. This is the difference between "needs a WCH-Link" and "needs a USB cable". Reach for it when no probe is attached |
| Bare-metal scaffolding | `$CH32FUN_ROOT` = `/opt/ch32fun` (`$CH32V_FUN` and `/opt/ch32v003fun` are aliases). **Never export `CH32FUN`** � ch32fun.mk reads it as its own `ch32fun/` subdir — cnlohr's ch32fun: header + minimal startup, no MounRiver, no vendor HAL. Covers the whole CH32V/CH32X range |
| CMake toolchain file | `/opt/embedded/cmake/toolchains/riscv-none-elf.cmake` |
| **CH582F / CH58x** | USB-only flow: hold BOOT, plug in, `wchisp` (`4348:55e0`). Profile `/opt/embedded/profiles/ch582f.json`; ch32fun `TARGET_MCU:=CH582F` (RV32IMAC, 448 KB flash, 32 KB RAM). `ch58x-sdk` fetches WCH's official EVT SDK (BLE stack) on demand |
| Default profile | `/opt/embedded/profile.json` (CH32V003F4P6, `rv32ec`, probe/flashTool `wlink`) |

Everything in the embedded layer above is present too — `mcu`, `svd-find`,
`openocd`, `probe-rs`, `gdb`, `clang`, the shared CMake helpers.

### Skills in this layer

| Skill | Reach for it when |
|---|---|
| `ch58x-usb-isp` | Flashing/recovering a CH582F/CH58x over USB, usbipd attach in WSL, option bytes |
| `ch58x-sdk-choices` | Starting CH582F firmware: ch32fun vs official EVT SDK, BLE, build flags |
| `ch32fun-cpp-template` | Starting a ch32fun-based C++ project |
| `ch32v-family-differences` | Choosing or porting between CH32V003/V103/V203/V303/X033 |
| `ch32v-flash-verify` | Flash writes that do not stick, or verification failures |
| `ch32v-low-power` | Sleep / standby on CH32V parts |
| `riscv-csr-cheatsheet` | QingKe CSR names, interrupt controller, `mstatus`/`mtvec` |

Command: `/ch32-new-project` (accepts `CH582F`).

The `ch58x-*` skills are directory-form (`<name>/SKILL.md`) and trigger on their own. The older ones are flat `~/.claude/skills/<name>.md` files and will **not** trigger on
their own — read the file directly when its topic comes up. See the maintenance
rule in the baseline layer.
