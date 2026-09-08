# Building MC-Gameboy

MC-Gameboy is the MiSTer Gameboy core plus the MiSTer Control telemetry and
input replay interface (`rtl/mc`, shared with MC-NES). It is an additional
core. It does not replace `Gameboy_<date>.rbf`; it installs as
`_Console/MC-Gameboy_<date>.rbf` and reports the same `GAMEBOY` core name, so
`games/GAMEBOY`, saves and save states are the stock ones.

Toolchain, install and the reference machine: MC-NES `BUILD.md` (Quartus Prime
Lite 17.0.2 on the gaming PC, `~/intelFPGA_lite/17.0`).

## Build

    scripts/build.sh            # full compile, output in out/MC-Gameboy_<date>.rbf
    scripts/build.sh 20260908   # fixed datecode
    SEED=2 scripts/build.sh     # another fitter seed when a marginal clock misses timing

The script runs `quartus_sh --flow compile Gameboy`, copies
`output_files/Gameboy.rbf` to `out/MC-Gameboy_<date>.rbf` and writes
`out/MC-Gameboy_<date>.txt` with the fit summary, the timing summary and the
commit. `Gameboy.qsf` is restored with `git checkout` afterwards.

Simulation of `rtl/mc` alone (Icarus Verilog): `sim/run.sh` runs the
telemetry and replay testbenches in the NES geometry and in this core's
(`RAM_ADDR_W` 15, `PAD_COUNT` 4, `SLOT_WORDS` 5120, `ENTRY_BYTES` 8).

## What the port touches

Upstream `MiSTer-devel/Gameboy_MiSTer` `7a5ff50` (2026). Every line below was
read in that source before the wiring was written.

| Signal | Where it comes from | Source |
|---|---|---|
| Joypad register select | `sel_joy = cpu_addr == 16'hff00` | `rtl/gb.v:181` |
| Row select `p54` | written by `ce_cpu && sel_joy && !cpu_wr_n_edge`, read back in `joy_do = {2'b11, p54, joy_din}` | `rtl/gb.v:591-594` |
| Poll (lag rule) | `mc_joy_read = ce_cpu & sel_joy & ~cpu_rd_n & ~mc_joy_rd_d & (p54 != 2'b11)`: the first CPU clock of a `$FF00` read with a row selected. BizHawk's Gambatte clears `IsLagFrame` in the input callback, which libgambatte calls from `Memory::updateInput()` on a `$FF00` read only when `(P1 & 0x30) != 0x30` | BizHawk `Gambatte.cs:360-363`, `:465`; gambatte-speedrun `libgambatte/src/memory.cpp:515-522`, `:604-611`; `rtl/gb.v` MiSTer Control section |
| Strobe | `ce_cpu & sel_joy & ~cpu_wr_n_edge` (a `$FF00` write) | `rtl/gb.v` MiSTer Control section |
| Pads | `sgb.v` builds `joy_data` from `joystick_0..3[7:0]`: bit 0 Right, 1 Left, 2 Down, 3 Up, 4 A, 5 B, 6 Select, 7 Start; with SGB off `joystick = joystick_0 \| joystick_1`. The replay substitutes its pads at the four `sgb` inputs | `rtl/sgb.v:378-386`; `Gameboy.sv` sgb instance |
| Work RAM | `dpram #(15) wram`, port A `clk_cpu` (= `clk_sys & ce_cpu`), `wren_a = wram_wren`, `address_a = wram_addr`, `data_a = cpu_do`; port B is the save-state load (`Savestate_RAMRWrEn[0]`, one byte per `clk_sys`) | `rtl/gb.v:961-973`, `:325-326` |
| Shadow copy | `mc_shadow_ram #(.ADDR_W(15), .FIFO_W(11))` fed by `wram_wren \| Savestate_RAMRWrEn[0]`; the bitmap clears on `cart_download` | `Gameboy.sv` MiSTer Control section |
| Register bus | 64 bit, 10 bit address, combinational read (`BUS_Dout(i) <= Din(i) when BUS_Adr = AdrI`); `gb_savestates` drives `BUS_Adr`, `savestate_busy` is `'0' when state = IDLE else '1'`. The address is muxed as in MC-NES `nes.v:886`: `savestate_busy ? SaveStateBus_Adr_ss : mc_bus_adr` | `rtl/bus_savestates.vhd:35-110`; `rtl/gb_savestates.vhd:122`; `rtl/gb.v` MiSTer Control section |
| Register index map | GBSE 0, CPUREGS 1, T80 2..5, Timer 6, HDMA 7, Link 8, Video 9-10, palettes 11-26, Video3 27, Sound 28-30, Top 31, Ext 32, Wave 33-36, Ext2 37, Top2 38 | `rtl/reg_savestates.vhd:12-44` |
| Frame edge (telemetry slot) | `lcd_vsync` (`vsync <= !v_cnt` at end of line: high on line 0) | `rtl/video.v:685`, `:692`; `rtl/gb.v:78` |
| Replay latch (entry N presented) | rising edge of `~lcd_on \| (lcd_mode == 2'b01)`, GBHawk's `in_vblank`: `mode_vblank` = `vblank_l` (DMG: `& vblank_t`), `vblank = v_cnt >= 144` latched a few cycles after the end of line 143; and the LCD switched off outside vblank. GBHawk latches its pads on the rising edge of `in_vblank` (`GBHawk.IEmulator.cs:143-150`), which its PPU sets at LY 144 (`GB_PPU.cs:190-193`), holds true while the LCD is off (`:434-440`) and clears when the LCD is switched on (`:198-201`). A game that reads `$FF00` during the picture must see the new entry from line 144 on, not from line 0; a game that switches the LCD off during the picture (Contra 4199M's title routine, movie frames 350, 358, 362, 366) consumes an entry there, and without the `~lcd_on` term the core ran 3 entries behind from the title on (build h, 2026-09-08) | `rtl/video.v:280`, `:304-313`, `:395-398`; `rtl/mc/mc_replay.sv:94`; `Gameboy.sv` mc_replay instance |
| Slot scanline and cycle | `v_cnt`, `h_cnt` of the `lcd` converter (informational) | `Gameboy.sv:692`, lcd instance |
| Reset and download | `reset = RESET \| status[0] \| buttons[1] \| cart_download \| boot_download \| bk_loading`; `cart_download = ioctl_download && (filetype[5:0] == 6'h01 \|\| filetype == 8'h80)` | `Gameboy.sv:546`, `:307` |
| Console mode while a movie is armed | replay header w2 [4:3] (`mc_replay.sys_mode`): 1 DMG, 2 GBC, 3 SGB, 0 the menu. Latched at the arming reset into `mc_sys_ovr` and held to the next reset: `isGBC` follows it, and `sgb_sel` replaces `\|sgb_en` at the boot ROM select, the `sgb` instance and the telemetry system type; the border is off under an override | `Gameboy.sv` isGBC block, `sgb_sel`; `rtl/mc/mc_replay.sv` EVAL |
| DMG boot ROM per launch | conf string `FC5,BIN,Load DMG boot ROM` on the root page (ioctl index 5 = `dmg_boot_download`, `Gameboy.sv:317`; the firmware matches an MGL `<file index="5">` only against a visible root-page F entry, `menu.cpp:1976`, `:2034`, `:2408`, and an unmatched item falls through to entry 0, the cartridge slot, `mra_loader.cpp:1436`, `menu.cpp:2320`: build g had the entry on page 4 and the boot ROM loaded as a 256-byte cartridge, index 1.2): the app's MGL for a movie made with Nintendo's DMG boot ROM loads that file (his copy, `tas/GAMEBOY/dmg_boot.bin`) before the cartridge, so the core runs the same boot the emulator did: offset 0, same start state. A custom DMG boot ROM makes `fastboot_available` 0, so the forced fast boot does not apply | `Gameboy.sv` CONF_STR, `:317`, `:320-325` |
| Fast boot while a movie is armed | `fast_boot_en` is forced while `mc_sys_ovr` is set: the MiSTer DMG boot ROM skips its logo animation, as the SGB boot ROM (which every DMG game got with the menu at Palette or On, `isSGB = \|sgb_en & ~isGBC`) always does. The GBHawk offset of -332 was measured against that short boot; with Fast boot off in the menu the DMG boot ROM takes about 300 frames more and a movie's first input lands before the title (Terminator 2 on build e). Not available with a custom DMG boot ROM (`fastboot_available`) | `Gameboy.sv` gb instance, `:320-325` |
| Backup RAM while a movie is armed | `bk_load`, `bk_save` and the auto-load after a download are gated by `~mc_rp_armed` (state 1 or 2), as MC-NES does | `Gameboy.sv` bk section; MC-NES `NES.sv:1199-1237` |
| DDR | `rtl/ddram.sv` is byte-identical to the NES upstream file (diffed 2026-09-07); the MC-NES version with `ch2` (telemetry writes) and `ch3` (replay reads) drops in | `git -C MC-NES show upstream/master:rtl/ddram.sv` |
| Clock | `clk_sys` is the PLL's `outclk_1` = 33.554432 MHz (`outclk_0` = 67.108864 MHz is `clk_ram`). `mc_replay` polls at `CLK_HZ` 33554432 / 60; the header publishes 33554432 | `rtl/pll/pll_0002.v:25-28`; `Gameboy.sv:157-163` |
| Status | 64 bits; free before this port: 10, 11, 17, 28-30, 37, 51-63. Telemetry on/off is `status[51]` (CONF_STR page "MiSTer Control") | `Gameboy.sv` CONF_STR, grep of `status[` |
| Frame rate | 4194304 / 70224 = 59.7275 Hz | standard DMG timing; BizHawk header `ClockRate 2097152` |

## Telemetry geometry

`mc_telemetry #(.MAGIC("MC-GB\0\0\1"), .RAM_ADDR_W(16), .PAD_COUNT(4),
.REGS_KIND(1), .SLOT_WORDS(9344))`: header layout 3, 74752 byte slots at
`0x3C001000`, RAM image 64 KB at slot offset `0x240`, bitmap 8 KB at `0x10240`,
tail at `0x12240`. `regs kind 1`: slot word 1 is zero, the CPU registers are on
the bus words (index 1..5). Replay entries are 8 bytes (`mc_replay
#(.ENTRY_BYTES(8))`), pads 1..4 in the MiSTer joystick order above.

The image is the CPU address space, so a RAM map is written in CPU addresses
(`rtl/gb.v`, `mc_wram_img`):

| Image offset | Holds | Written by |
|---|---|---|
| `$C000-$CFFF` | WRAM bank 0 | `wram_wren` (CPU, DMA), save-state load `Savestate_RAMRWrEn[0]` |
| `$D000-$DFFF` | WRAM bank 1 (the DMG's upper 4 KB) | same |
| `$2000-$7FFF` | GBC WRAM banks 2-7 at `bank<<12` | same |
| `$FF80-$FFFE` | HRAM (zero page, 127 bytes) | `cpu_wr_zpram`, save-state load `Savestate_RAMRWrEn[3]` |

Everything else in the image is never written and its bitmap stays clear. The
first build (`MC-Gameboy_20260908`) had a 32 KB WRAM-only image (`RAM_ADDR_W`
15, 40960 byte slots, `$C000` at offset 0); the app tells the two apart by the
header's RAM size.

The shadow FIFO holds 4096 pending writes (`FIFO_W` 12): the 64 KB read-out
takes about 3.3 ms per frame and a GBC at double speed can write every other
cycle (about 3,300 writes in that time).

## Reference numbers

`MC-Gameboy_20260908h.rbf` (commit `625f9f1`, default seed, 2026-09-07, `out/MC-Gameboy_20260908h.txt`):
build g with the DMG boot ROM slot on the root page (`FC5,BIN,Load DMG boot ROM`): the
firmware matches an MGL file index only against visible root-page F entries, and build g's
page-4 entry let the boot ROM fall through to the cartridge slot.

| Item | Value |
|---|---|
| Wall time | 904 s on the 3960X |
| Logic (ALMs) | 22,233 / 41,910 (53%) |
| Registers | 28,706 |
| RAM blocks | 493 / 553 (89%) |
| Setup slack, clk_sys / clk_ram / tightest (HDMI PLL) | 1.672 ns / 2.747 ns / 0.367 ns (TNS 0) |
| Critical warnings | 0 |
| `MC-Gameboy_20260908h.rbf` | 4,033,424 bytes, SHA-256 `79307dc5c710188481097dd1af7005ce29a900ac4e689121ce9d7afdf8628508` |

`MC-Gameboy_20260908g.rbf` (commit `f8e8ca7`, default seed, 2026-09-07, `out/MC-Gameboy_20260908g.txt`):
build f plus the loadable DMG boot ROM slot (`P4FC5,BIN,Load DMG boot ROM`, ioctl index 5):
a movie launch loads the boot ROM the emulator ran before the cartridge, offset 0.

| Item | Value |
|---|---|
| Wall time | 880 s on the 3960X |
| Logic (ALMs) | 22,296 / 41,910 (53%) |
| Registers | 28,914 |
| RAM blocks | 493 / 553 (89%) |
| Setup slack, clk_sys / clk_ram / tightest (HDMI PLL) | 1.549 ns / 2.943 ns / 0.250 ns (TNS 0) |
| Critical warnings | 0 |
| `MC-Gameboy_20260908g.rbf` | 4,009,020 bytes, SHA-256 `7f07e14c33fa01befb33f6d3a716d55d6b1203bc413d6a8be1ddc6d461239c1c` |

`MC-Gameboy_20260908f.rbf` (commit `07502bb`, default seed, 2026-09-07, `out/MC-Gameboy_20260908f.txt`):
build e plus fast boot forced while a movie is armed (the DMG boot ROM's logo animation
otherwise adds about 300 frames when Fast boot is off in the menu).

| Item | Value |
|---|---|
| Wall time | 884 s on the 3960X |
| Logic (ALMs) | 22,300 / 41,910 (53%) |
| Registers | 28,825 |
| RAM blocks | 493 / 553 (89%) |
| Setup slack, clk_sys / clk_ram / tightest (HDMI PLL) | 2.005 ns / 3.157 ns / 0.498 ns (TNS 0) |
| Critical warnings | 0 |
| `MC-Gameboy_20260908f.rbf` | 4,007,560 bytes, SHA-256 `0d3a120f73047f41003eb261b6dcf1427517ca55f8793231057d2ba531cf68e1` |

`MC-Gameboy_20260908e.rbf` (commit `86058f2`, default seed, 2026-09-07, `out/MC-Gameboy_20260908e.txt`):
build d plus the console mode from the replay header (w2 [4:3]): a DMG movie boots the DMG
path on an SGB-enhanced cartridge whatever the Super Game Boy menu says (Contra 4199M
stalled in its SGB handshake on build d with the menu at Palette; on this build it plays).

| Item | Value |
|---|---|
| Wall time | 879 s on the 3960X |
| Logic (ALMs) | 22,244 / 41,910 (53%) |
| Registers | 28,952 |
| RAM blocks | 493 / 553 (89%) |
| Setup slack, clk_sys / clk_ram / tightest (HDMI PLL) | 1.690 ns / 2.869 ns / 0.203 ns (TNS 0) |
| Critical warnings | 0 |
| `MC-Gameboy_20260908e.rbf` | 4,006,976 bytes, SHA-256 `21b08629267c8c2b887408bb5ebdd4be1f04ff236a82e0854caba1e4c93bc43c` |

`MC-Gameboy_20260908d.rbf` (commit `d7d3ec2`, default seed, 2026-09-07, `out/MC-Gameboy_20260908d.txt`):
build c plus the replay latch point at the PPU's vblank entry (`lcd_mode == 2'b01`, line 144,
where GBHawk latches its pads) instead of `lcd_vsync` (line 0). With line 0 a one-frame tap
that Super Mario Land 2 read during the picture landed a frame late (3746M, `$CC2A` diverged
at movie frame 2313); with this build the work RAM matches GBHawk's dump from movie frame
2238 to the last input (2751).

| Item | Value |
|---|---|
| Wall time | 883 s on the 3960X |
| Logic (ALMs) | 22,339 / 41,910 (53%) |
| Registers | 28,717 |
| RAM blocks | 493 / 553 (89%) |
| Setup slack, clk_sys / clk_ram / tightest (HDMI PLL) | 1.851 ns / 2.895 ns / 0.116 ns (TNS 0) |
| Critical warnings | 0 |
| `MC-Gameboy_20260908d.rbf` | 4,013,048 bytes, SHA-256 `6bfe2630c0baa1eaa31173efd524e1e25ca4b7cd0140342771b3db299991398a` |

`MC-Gameboy_20260908c.rbf` (commit `832943c`, default seed, 2026-09-07, `out/MC-Gameboy_20260908c.txt`):
the 64 KB image plus the fix that drops a pending backup RAM auto-load and the run's save
while a movie is armed (the deferred load fired at the movie's end and its reset hid the
run's ending).

| Item | Value |
|---|---|
| Wall time | 882 s on the 3960X |
| Logic (ALMs) | 22,147 / 41,910 (53%) |
| Registers | 28,876 |
| RAM blocks | 493 / 553 (89%) |
| Setup slack, clk_sys / clk_ram / tightest (HDMI PLL) | 2.258 ns / 2.895 ns / 0.569 ns (TNS 0) |
| Critical warnings | 0 |
| `MC-Gameboy_20260908c.rbf` | 4,020,044 bytes, SHA-256 `5739994fc3ffd61ffbc4f28cdd79f7ac3e1f56eaa1687bcbac7c2271be7c3568` |

`MC-Gameboy_20260908b.rbf` (commit `f13d9d5`, default seed, 2026-09-07, the 64 KB image,
`out/MC-Gameboy_20260908b.txt`):

| Item | Value |
|---|---|
| Wall time | 894 s (14 min 54 s) on the 3960X |
| Logic (ALMs) | 22,225 / 41,910 (53%) |
| Registers | 28,918 |
| Block memory | 3,879,605 / 5,662,720 bits (69%), 493 / 553 RAM blocks (89%) |
| DSP blocks | 36 / 112 |
| Setup slack, clk_sys (pll general[1]) | 1.845 ns (TNS 0) |
| Setup slack, clk_ram (pll general[0]) | 2.686 ns (TNS 0) |
| Setup slack, tightest | 0.597 ns, HDMI PLL (TNS 0) |
| Critical warnings | 0 |
| `MC-Gameboy_20260908b.rbf` | 3,997,116 bytes, SHA-256 `747638676a1378d3f105cd10080932e7fa6050b7e5d0a8f975ff6564a15cfe94` |

Against the first build: +24 ALMs, +47 RAM blocks (the shadow copy 32 KB to 64 KB, the
bitmap 4 KB to 8 KB, the FIFO 2048 to 4096 entries of 24 bits). 60 RAM blocks remain.

First MC build, `MC-Gameboy_20260908.rbf` (commit `73455ee`, default seed, 2026-09-07,
`out/MC-Gameboy_20260908.txt`, the 32 KB WRAM-only image):

| Item | Value |
|---|---|
| Wall time | 955 s (15 min 55 s) on the 3960X |
| Logic (ALMs) | 22,201 / 41,910 (53%) |
| Registers | 28,818 |
| Block memory | 3,500,725 / 5,662,720 bits (62%), 446 / 553 RAM blocks (81%) |
| DSP blocks | 35 / 112 |
| Setup slack, clk_sys (pll general[1]) | 1.759 ns (TNS 0) |
| Setup slack, clk_ram (pll general[0]) | 2.955 ns (TNS 0) |
| Setup slack, tightest | 0.526 ns, HDMI PLL (TNS 0) |
| Critical warnings | 0 |
| Warnings in `rtl/mc` | 3 (two sized-localparam truncations, one unused register; cleared in `3a35113`, not yet rebuilt) |
| `MC-Gameboy_20260908.rbf` | 3,933,444 bytes, SHA-256 `f2f6a19ccf5d5d4fdd853792939ab417d4600dc75d78859c14be204237c01523` |

An unmodified upstream build was not run, so the port's own cost in ALMs and RAM blocks is
not measured. Expected from the design: about 35 RAM blocks (32 KB shadow copy, 2048 x 23
bit FIFO, 4 KB bitmap) and the telemetry, replay and DDR channel logic.
