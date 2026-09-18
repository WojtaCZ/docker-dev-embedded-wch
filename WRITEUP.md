# docker-dev-embedded-wch — Functional Writeup

> Leaf image for WCH CH32V (RISC-V). Inherits `docker-dev-embedded-base`.
> Fleet-wide architecture: [`docker-dev-embedded-base/WRITEUP.md`](../docker-dev-embedded-base/WRITEUP.md)

> **Note:** the analysis below describes the repo *as it was audited* on
> 2026-09-02. Every defect listed has since been fixed and every proposal
> implemented — see **Status: implemented** at the end for the mapping. The
> analysis is kept because it records *why* the current design is the way it is.


## 1. Purpose and position

The RISC-V sibling of the ARM leaf. Targets WCH's QingKe cores — **CH32V003**
(RV32EC, 16 KB flash / 2 KB SRAM), CH32V203, CH32V303, CH32X033 — with the same
no-vendor-SDK philosophy: no MounRiver, no WCH HAL.

```
docker-dev-template
  └── docker-dev-embedded-base
       └── docker-dev-embedded-wch   ← THIS IMAGE
```

It is the smallest leaf in the fleet — one AUR toolchain, one git clone, three
skills, one profile.

## 2. What this image adds

| Addition | Detail |
| --- | --- |
| `riscv-none-elf-gcc-bin` | xPack prebuilt RISC-V toolchain from AUR (currently 14.2.0). Chosen `-bin` to avoid a from-source GCC build in CI. |
| `ch32v003fun` | `git clone` → `/opt/ch32v003fun`, exported as `$CH32V_FUN`. cnlohr's community bare-metal scaffolding: register defs, `SystemInit()`, `Delay_Ms()`, SysTick/GPIO/UART/SPI/I2C helpers, and an `examples/` tree. |
| `profile.json` | Make-based (`make -j$(nproc)`), `wlink` for flash/erase/reset, openocd `wlink-rs.cfg` + `wch-riscv.cfg` for the debug server. |
| Claude skills (3) | `ch32fun-cpp-template`, `ch32v-low-power`, `riscv-csr-cheatsheet` |

The design choice worth calling out: rather than a CMake scaffold like the ARM
leaf, this leaf leans on `ch32v003fun`'s existing Makefile conventions. That is
pragmatic — `ch32v003fun` is the de-facto open toolchain for these parts — but it
means the two leaves have structurally different project layouts, which weakens
the "one `tasks.json` everywhere" story slightly.

## 3. Verified defects

Checked against live Arch/AUR sources on 2026-09-02.

| # | Severity | Finding |
| --- | --- | --- |
| **W0** | **Blocker (inherited)** | Parent `docker-dev-embedded-base` references seven package names that do not exist and cannot build. See [base writeup §5](../docker-dev-embedded-base/WRITEUP.md). |
| **W1** | **Blocker** | `wlink` is advertised in this repo's README and used by every `profile.json` command, but it is **never installed here**. The base image tries to install `wlink-bin` from AUR — and **`wlink-bin` does not exist in AUR**. Only `wlink` (0.1.2, from-source cargo build) exists. Result: `flash`, `erase`, and `reset` all fail with "command not found". |
| W2 | Medium | `wlink` is a WCH-only tool but is (attempted to be) installed in the **shared base image**, where ARM and Telink users pay for it too. Move the install here. |
| W3 | Medium | The base's `vscode-templates/launch.json` RISC-V configuration hard-codes `miDebuggerPath: /usr/bin/riscv-none-elf-gdb`. The AUR `riscv-none-elf-gcc-bin` package installs into a versioned prefix (typically `/opt/riscv-none-elf-gcc/<ver>/bin/`), **not** `/usr/bin`. Verify and either symlink into `/usr/bin` from this Dockerfile or make the path a profile variable. |
| W4 | Medium | `settings.json` re-declares the `fetch` MCP as `npx -y @modelcontextprotocol/server-fetch`, an npm package that **does not exist** (404). Use `uvx mcp-server-fetch`. |
| W5 | Low | `git clone --depth=1` of `ch32v003fun` is unpinned — image content drifts silently between builds. Pin a tag or commit. |
| W6 | Low | `openocd -f interface/wlink-rs.cfg` — that config name is not in stock OpenOCD 0.12.0. WCH-Link debugging normally needs **WCH's OpenOCD fork** or `wlink`'s own GDB server (`wlink gdbserver`). Verify before relying on the `debugServer` profile key. |
| W7 | Low | No `riscv-none-elf-gdb` is separately installed. It comes bundled with the xPack toolchain, but note Arch also has `riscv32-elf-gdb` in `extra` as a fallback. |
| W8 | Low | The skills are CH32V003-specific (RV32EC / QingKe V2A) while the README advertises CH32V203/V303/X033 (which are RV32IMAC / V4 cores with different CSRs and interrupt controllers). The `riscv-csr-cheatsheet` skill says "QingKe RV32EC on CH32V003" in its own title — good honesty, but the coverage gap is real. |

## 4. Proposed features

### 4.1 Install `wlink` here, and verify it (fixes W1/W2)

```dockerfile
USER root
RUN su aurbuild -c "paru -S --noconfirm --needed --skipreview wlink" \
 && wlink --version
```

Better still: `cargo install wlink` or fetch a release binary, and drop the AUR
dependency. Add the `wlink --version` assertion so a broken install fails the
build instead of the user.

### 4.2 Add `wchisp` as a second flash path

`wchisp` (the USB bootloader tool) works without a WCH-Link probe at all — the
CH32V parts expose a factory USB DFU-ish bootloader. Having a probe-free path is
genuinely useful and costs almost nothing.

### 4.3 Broaden beyond CH32V003

Add profile entries and skills for CH32V203/V303 (RV32IMAC, different PFIC
config, USB peripheral) and CH32X033. Right now the image claims them but only
really equips you for the V003.

### 4.4 Unified CMake path

Offer a CMake toolchain file for `riscv-none-elf` alongside the `ch32v003fun`
Makefile route, so a project can use the same `tasks.json`/`launch.json` flow as
the ARM leaf. `ch32v003fun` can be consumed as a plain source list from CMake.

### 4.5 A `ch32v-flash-verify` skill

CH32V003 has only 16 KB flash and a notoriously touchy SWIO single-wire debug
interface. A skill that walks the "wlink can't connect" decision tree (power,
NRST, the 8 MHz internal RC, the `-r` reset flag, the bootloader pin) would pay
for itself quickly — the WCH equivalent of the base's `probe-troubleshoot`.

### 4.6 Shared items to inherit from base improvements

The RTT/HIL feedback loop (base §7.5, §7.6) applies here too — `probe-rs` has
partial CH32V support, and `wlink` can stream via the debug interface. A
machine-readable feedback channel from the running target is the biggest single
upgrade for autonomous development on these parts.

---

## Status: implemented 2026-09-02

Everything proposed in section 4 is now in the repo, and every defect in
section 3 is fixed.

| Item | Resolution |
| --- | --- |
| W0 — parent could not build | fixed in `docker-dev-embedded-base` |
| W1/W2 — `wlink` advertised but never installed | installed **here** from the official `ch32-rs/wlink` release tarball; the Dockerfile runs `wlink --version`, and the smoke test fails without it |
| W3 — hard-coded `/usr/bin/riscv-none-elf-gdb` | xPack toolchain symlinked onto `/usr/local/bin`, and `launch.json` resolves `${env:CROSS_GDB}` from `CROSS_PREFIX` |
| W4 — non-existent `fetch` npm package | fixed upstream in the embedded layer |
| W5 — unpinned `ch32v003fun` clone | `CH32FUN_REF` build arg |
| W6 — questionable `wlink-rs.cfg` openocd config | `debugServer` now uses `wlink gdbserver`, which is real |
| W7 — no separate RISC-V gdb | bundled with the xPack toolchain; asserted in the smoke test |
| W8 — skills only covered the V003 | `ch32v-family-differences` covers V003/V103/V203/V303/X033 |
| 4.2 — `wchisp` | installed from the official release; probe-free USB-bootloader flashing |
| 4.3 — broaden beyond the V003 | `profile.json` `_chips` per part; `ch32fun` (not just `ch32v003fun`) |
| 4.4 — unified CMake path | `cmake/toolchains/riscv-none-elf.cmake`, `_cmake_variant` in the profile |
| 4.5 — `ch32v-flash-verify` skill | added, including locked-chip recovery |

The whole image now installs from official prebuilt release tarballs, so **no
AUR helper is needed at all**. CI cross-compiles a real CH32V003 (RV32EC)
firmware, asserts the ISA via `readelf -A`, checks the 16 KB / 2 KB budget is
enforced, verifies the toolchain file rejects an `rv32e`/`ilp32` mismatch, and
builds a CH32V203 image too.
