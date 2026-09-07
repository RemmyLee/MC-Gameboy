#!/bin/sh
# Simulate rtl/mc with Icarus Verilog (brew install icarus-verilog), in the
# NES geometry and the Gameboy one.
set -e
cd "$(dirname "$0")/.."
SRC="rtl/mc/mc_shadow_ram.sv rtl/mc/mc_telemetry.sv"
iverilog -g2012 -o sim/tb_mc.vvp sim/tb_mc.sv $SRC
vvp -n sim/tb_mc.vvp | tail -3
iverilog -g2012 -P tb_mc.RAM_ADDR_W=15 -P tb_mc.PAD_COUNT=4 -P tb_mc.SLOT_WORDS=5120 -o sim/tb_mc_gb.vvp sim/tb_mc.sv $SRC
vvp -n sim/tb_mc_gb.vvp | tail -3
iverilog -g2012 -P tb_mc.RAM_ADDR_W=16 -P tb_mc.PAD_COUNT=4 -P tb_mc.SLOT_WORDS=9344 -o sim/tb_mc_gb64.vvp sim/tb_mc.sv $SRC
vvp -n sim/tb_mc_gb64.vvp | tail -3
iverilog -g2012 -o sim/tb_replay.vvp sim/tb_replay.sv rtl/mc/mc_replay.sv
vvp -n sim/tb_replay.vvp | tail -12
iverilog -g2012 -P tb_replay.EB=8 -o sim/tb_replay_gb.vvp sim/tb_replay.sv rtl/mc/mc_replay.sv
vvp -n sim/tb_replay_gb.vvp | tail -12
