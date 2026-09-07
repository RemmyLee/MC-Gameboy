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
| Row select `p54` | written by `ce_cpu && sel_joy && !cpu_wr_n_edge`, read back in `joy_do = {2'b11, p54, joy_din}` | `rtl/gb.v:589-594` |
| Poll (lag rule) | `mc_joy_read = ce_cpu & sel_joy & ~cpu_rd_n & ~mc_joy_rd_d & (p54 != 2'b11)`: the first CPU clock of a `$FF00` read with a row selected. BizHawk's Gambatte clears `IsLagFrame` in the input callback, which libgambatte calls from `Memory::updateInput()` on a `$FF00` read only when `(P1 & 0x30) != 0x30` | BizHawk `Gambatte.cs:360-363`, `:465`; gambatte-speedrun `libgambatte/src/memory.cpp:515-522`, `:604-611`; `rtl/gb.v` MiSTer Control section |
| Strobe | `ce_cpu & sel_joy & ~cpu_wr_n_edge` (a `$FF00` write) | `rtl/gb.v` MiSTer Control section |
| Pads | `sgb.v` builds `joy_data` from `joystick_0..3[7:0]`: bit 0 Right, 1 Left, 2 Down, 3 Up, 4 A, 5 B, 6 Select, 7 Start; with SGB off `joystick = joystick_0 \| joystick_1`. The replay substitutes its pads at the four `sgb` inputs | `rtl/sgb.v:378-386`; `Gameboy.sv` sgb instance |
| Work RAM | `dpram #(15) wram`, port A `clk_cpu` (= `clk_sys & ce_cpu`), `wren_a = wram_wren`, `address_a = wram_addr`, `data_a = cpu_do`; port B is the save-state load (`Savestate_RAMRWrEn[0]`, one byte per `clk_sys`) | `rtl/gb.v:961-973`, `:325-326` |
| Shadow copy | `mc_shadow_ram #(.ADDR_W(15), .FIFO_W(11))` fed by `wram_wren \| Savestate_RAMRWrEn[0]`; the bitmap clears on `cart_download` | `Gameboy.sv` MiSTer Control section |
| Register bus | 64 bit, 10 bit address, combinational read (`BUS_Dout(i) <= Din(i) when BUS_Adr = AdrI`); `gb_savestates` drives `BUS_Adr`, `savestate_busy` is `'0' when state = IDLE else '1'`. The address is muxed as in MC-NES `nes.v:886`: `savestate_busy ? SaveStateBus_Adr_ss : mc_bus_adr` | `rtl/bus_savestates.vhd:35-110`; `rtl/gb_savestates.vhd:122`; `rtl/gb.v` MiSTer Control section |
| Register index map | GBSE 0, CPUREGS 1, T80 2..5, Timer 6, HDMA 7, Link 8, Video 9-10, palettes 11-26, Video3 27, Sound 28-30, Top 31, Ext 32, Wave 33-36, Ext2 37, Top2 38 | `rtl/reg_savestates.vhd:12-44` |
| Frame edge | `lcd_vsync` (`vsync <= !v_cnt` at end of line: high on line 0) | `rtl/video.v:685`, `:692`; `rtl/gb.v:78` |
| Slot scanline and cycle | `v_cnt`, `h_cnt` of the `lcd` converter (informational) | `Gameboy.sv:692`, lcd instance |
| Reset and download | `reset = RESET \| status[0] \| buttons[1] \| cart_download \| boot_download \| bk_loading`; `cart_download = ioctl_download && (filetype[5:0] == 6'h01 \|\| filetype == 8'h80)` | `Gameboy.sv:546`, `:307` |
| Backup RAM while a movie is armed | `bk_load`, `bk_save` and the auto-load after a download are gated by `~mc_rp_armed` (state 1 or 2), as MC-NES does | `Gameboy.sv` bk section; MC-NES `NES.sv:1199-1237` |
| DDR | `rtl/ddram.sv` is byte-identical to the NES upstream file (diffed 2026-09-07); the MC-NES version with `ch2` (telemetry writes) and `ch3` (replay reads) drops in | `git -C MC-NES show upstream/master:rtl/ddram.sv` |
| Clock | `clk_sys` is the PLL's `outclk_1` = 33.554432 MHz (`outclk_0` = 67.108864 MHz is `clk_ram`). `mc_replay` polls at `CLK_HZ` 33554432 / 60; the header publishes 33554432 | `rtl/pll/pll_0002.v:25-28`; `Gameboy.sv:186-192` |
| Status | 64 bits; free before this port: 10, 11, 17, 28-30, 37, 51-63. Telemetry on/off is `status[51]` (CONF_STR page "MiSTer Control") | `Gameboy.sv` CONF_STR, grep of `status[` |
| Frame rate | 4194304 / 70224 = 59.7275 Hz | standard DMG timing; BizHawk header `ClockRate 2097152` |

## Telemetry geometry

`mc_telemetry #(.MAGIC("MC-GB\0\0\1"), .RAM_ADDR_W(15), .PAD_COUNT(4),
.REGS_KIND(1), .SLOT_WORDS(5120))`: header layout 3, 40960 byte slots at
`0x3C001000`, RAM image 32 KB at slot offset `0x240`, bitmap 4 KB at `0x8240`,
tail at `0x9240`. `regs kind 1`: slot word 1 is zero, the CPU registers are on
the bus words (index 1..5). Replay entries are 8 bytes (`mc_replay
#(.ENTRY_BYTES(8))`), pads 1..4 in the MiSTer joystick order above.

## Reference numbers

Filled in after the first build on the PC.
