#!/usr/bin/env bash
# Smoke test for docker-dev-embedded-wch. Runs INSIDE the built image.
#
#   docker run --rm -e DEV_SKIP_UPDATE=1 -v "$PWD/tests:/tests:ro" <image> bash /tests/smoke.sh
#
# A green run means a CH32V003 (RV32EC) firmware really compiles and links here,
# and that the flash tooling the profile invokes actually exists.

set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "  ok  $*"; }

echo "== cross toolchain =="
for t in gcc g++ gdb objcopy objdump nm size readelf; do
    command -v "riscv-none-elf-$t" >/dev/null || fail "missing riscv-none-elf-$t"
    pass "riscv-none-elf-$t"
done
pass "gcc $(riscv-none-elf-gcc -dumpversion)"

# launch.json's RISC-V configuration resolves the debugger through CROSS_GDB,
# which mcu --export derives from CROSS_PREFIX. Both must line up.
[ "${CROSS_PREFIX:-}" = "riscv-none-elf-" ] \
    || fail "CROSS_PREFIX is '${CROSS_PREFIX:-}', expected riscv-none-elf-"
pass "CROSS_PREFIX=$CROSS_PREFIX"

echo "== multilibs =="
riscv-none-elf-gcc -print-multi-lib | grep -q 'rv32e' \
    || fail "no rv32e multilib — CH32V003 would not link"
pass "rv32e present (CH32V003)"
riscv-none-elf-gcc -print-multi-lib | grep -q 'rv32imac' \
    || fail "no rv32imac multilib — CH32V203/X033 would not link"
pass "rv32imac present (CH32V203/X033)"

echo "== flash tooling =="
# wlink was previously expected from a non-existent AUR package, so every
# flash/erase/reset in the profile failed with 'command not found'.
command -v wlink >/dev/null || fail "wlink missing — the profile's flash/erase/reset cannot work"
wlink --version
pass "wlink"
command -v wchisp >/dev/null || fail "wchisp missing — no probe-free flash path"
pass "wchisp"

echo "== ch32fun =="
[ -f "$CH32FUN/ch32fun/ch32fun.c" ] || fail "ch32fun sources not found at $CH32FUN"
[ -f "$CH32FUN/ch32fun/ch32fun.h" ] || fail "ch32fun.h not found"
pass "ch32fun at $CH32FUN"
[ -L /opt/ch32v003fun ] || fail "backwards-compatible /opt/ch32v003fun symlink missing"
pass "legacy \$CH32V_FUN path still resolves"

echo "== claude assets =="
for s in ch32fun-cpp-template ch32v-low-power riscv-csr-cheatsheet \
         ch32v-flash-verify ch32v-family-differences; do
    [ -f "$HOME/.claude/skills/$s.md" ] || fail "skill $s.md not installed"
    pass "skill: $s"
done
[ -f "$HOME/.claude/commands/scaffold-mcu-project.md" ] || fail "inherited command missing"
[ -f "$HOME/.claude/commands/ch32-new-project.md" ] || fail "/ch32-new-project missing"
pass "inherited commands present"

echo "== settings layers merged =="
S="$HOME/.claude/settings.json"
for server in github git context7 sequential-thinking fetch; do
    jq -e --arg s "$server" '.mcpServers | has($s)' "$S" >/dev/null || fail "MCP $server missing"
done
[ "$(jq -r '.mcpServers.fetch.command' "$S")" = "uvx" ] || fail "fetch MCP must use uvx"
pass "baseline + embedded + wch layers merged"

# --------------------------------------------------------------------------
echo "== END TO END: build a real CH32V003 (RV32EC) firmware =="
# --------------------------------------------------------------------------
work=$(mktemp -d)
cd "$work"
mkdir -p src

cat > src/main.cpp <<'CPP'
#include <cstdint>
struct Counter {
    Counter() : value(7) {}
    volatile std::uint32_t value;
};
static Counter counter;
int main() { for (;;) { counter.value = counter.value + 1u; } }
CPP

cat > src/startup.cpp <<'CPP'
#include <cstdint>
extern std::uint32_t _sidata, _sdata, _edata, _sbss, _ebss, _estack;
extern void (*__init_array_start)();
extern void (*__init_array_end)();
int main();

extern "C" [[noreturn]] void Reset_Handler() {
    std::uint32_t* src = &_sidata;
    for (std::uint32_t* d = &_sdata; d < &_edata; ) { *d++ = *src++; }
    for (std::uint32_t* d = &_sbss;  d < &_ebss;  ) { *d++ = 0u; }
    for (void (**c)() = &__init_array_start; c < &__init_array_end; ++c) { (*c)(); }
    main();
    for (;;) {}
}

extern "C" void Default_Handler() { for (;;) {} }

__attribute__((section(".init"), naked, used))
void _start() {
    __asm volatile(
        ".option norvc            \n"
        "la sp, _estack           \n"
        "j  Reset_Handler         \n"
    );
}
CPP

# CH32V003: 16 KB flash at 0x00000000, 2 KB SRAM at 0x20000000.
cat > linker.ld <<'LD'
ENTRY(_start)
MEMORY {
  FLASH (rx)  : ORIGIN = 0x00000000, LENGTH = 16K
  RAM   (rwx) : ORIGIN = 0x20000000, LENGTH = 2K
}
_estack = ORIGIN(RAM) + LENGTH(RAM);
SECTIONS {
  .init      : { KEEP(*(SORT_NONE(.init))) } > FLASH
  .text      : { *(.text*) *(.rodata*) } > FLASH
  .init_arr  : {
    . = ALIGN(4);
    PROVIDE_HIDDEN(__init_array_start = .);
    KEEP(*(SORT(.init_array.*)))
    KEEP(*(.init_array))
    PROVIDE_HIDDEN(__init_array_end = .);
  } > FLASH
  _sidata = LOADADDR(.data);
  .data : { _sdata = .; *(.data*) . = ALIGN(4); _edata = .; } > RAM AT> FLASH
  .bss  : { _sbss  = .; *(.bss*) *(COMMON) . = ALIGN(4); _ebss = .; } > RAM
  /DISCARD/ : { *(.riscv.attributes) *(.comment) }
}
LD

cat > CMakeLists.txt <<'CMAKE'
cmake_minimum_required(VERSION 3.20)
project(firmware CXX ASM)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
include(/opt/embedded/cmake/embedded-common.cmake)
add_executable(firmware src/main.cpp src/startup.cpp)
target_link_options(firmware PRIVATE -T ${CMAKE_SOURCE_DIR}/linker.ld -nostartfiles)
target_compile_features(firmware PRIVATE cxx_std_20)
target_compile_options(firmware PRIVATE
    -fno-exceptions -fno-rtti -fno-threadsafe-statics
    -ffunction-sections -fdata-sections -Os -Wall -Wextra)
target_link_options(firmware PRIVATE -Wl,--gc-sections -nostdlib -lgcc)
CMAKE

python - <<'PY'
import json
json.dump({
    "chip": "CH32V003F4P6",
    "core": "rv32ec",
    "march": "rv32ec_zicsr",
    "mabi": "ilp32e",
    "flashTool": "wlink",
    "ELF": "build/firmware.elf",
    "sizeBudget": {"flash": 16384, "ram": 2048},
    "build": ("cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release "
              "-DCMAKE_TOOLCHAIN_FILE=/opt/embedded/cmake/toolchains/riscv-none-elf.cmake "
              "-DRISCV_MARCH=${march} -DRISCV_MABI=${mabi} "
              "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON && cmake --build build"),
    "flash": "wlink flash build/firmware.bin",
    "postBuild": ["size"],
}, open(".mcu-profile.json", "w"), indent=2)
PY

mcu build
pass "CH32V003 firmware built via mcu"
[ -f build/firmware.elf ] || fail "no firmware.elf"

echo "-- build attributes --"
riscv-none-elf-readelf -A build/firmware.elf | grep -i 'Tag_RISCV_arch' || true
riscv-none-elf-readelf -A build/firmware.elf | grep -qi 'rv32e' \
    || fail "binary is NOT RV32E — the toolchain file is not applying -march"
pass "binary really is RV32EC"

riscv-none-elf-nm build/firmware.elf | grep -q '__init_array_start' \
    || fail ".init_array not emitted — C++ globals would never be constructed"
pass ".init_array present"

mcu size
pass "fits the 16 KB / 2 KB CH32V003 budget"

# The toolchain file must refuse an ABI/ISA mismatch rather than produce a
# subtly broken binary.
if cmake -S . -B build-bad -G Ninja \
      -DCMAKE_TOOLCHAIN_FILE=/opt/embedded/cmake/toolchains/riscv-none-elf.cmake \
      -DRISCV_MARCH=rv32ec_zicsr -DRISCV_MABI=ilp32 >/dev/null 2>&1; then
    fail "toolchain file accepted rv32ec + ilp32, which is not ABI-compatible"
fi
pass "toolchain file rejects an rv32e/ilp32 mismatch"

echo "== END TO END: CH32V203 (RV32IMAC) also builds =="
rm -rf build
python - <<'PY'
import json
p = json.load(open(".mcu-profile.json"))
p.update({"chip": "CH32V203C8T6", "core": "rv32imac", "march": "rv32imac_zicsr",
          "mabi": "ilp32", "sizeBudget": {"flash": 65536, "ram": 20480}})
json.dump(p, open(".mcu-profile.json", "w"), indent=2)
PY
sed -i 's/LENGTH = 16K/LENGTH = 64K/; s/LENGTH = 2K/LENGTH = 20K/' linker.ld
sed -i 's/ORIGIN = 0x00000000/ORIGIN = 0x08000000/' linker.ld
mcu build
riscv-none-elf-readelf -A build/firmware.elf | grep -qi 'rv32i' \
    || fail "V203 build did not target RV32I"
pass "CH32V203 RV32IMAC build works"

cd /
rm -rf "$work"

echo "== dev-doctor =="
dev-doctor
dev-doctor --json | jq -e '.ok == true' >/dev/null || fail "dev-doctor reported failures"
pass "dev-doctor clean"

echo "== CLAUDE.md memory layers assembled =="
M="$HOME/.claude/CLAUDE.md"
[ -d "$HOME/.claude-memory-layers" ] || fail "$HOME/.claude-memory-layers missing"
for l in 00-baseline.md 10-embedded.md 20-wch.md; do
    [ -f "$HOME/.claude-memory-layers/$l" ] || fail "memory layer $l not installed"
done
pass "memory layers present: $(ls "$HOME/.claude-memory-layers" | tr '\n' ' ')"
[ -s "$M" ] || fail "entrypoint did not assemble ~/.claude/CLAUDE.md"
grep -q "## WCH layer" "$M" || fail "merged CLAUDE.md is missing this image's layer (## WCH layer)"
pass "CLAUDE.md assembled, this image's layer present"

echo
echo "SMOKE TEST PASSED"
