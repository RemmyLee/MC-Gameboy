// mc_telemetry: once per frame, write a snapshot of the machine state to DDR3
// where MiSTer Control reads it over /dev/mem.
//
// The module is generic over the console: the parameters below size the RAM
// image, the pad count and the slot, and the header publishes every size, so
// the app reads offsets from the header (layout version 3) instead of a table
// per core. MC-NES uses the defaults; MC-Gameboy passes RAM_ADDR_W = 15,
// PAD_COUNT = 4, SLOT_WORDS = 5120.
//
// DDR map (byte addresses; the ddram module adds the 0x30000000 window):
//   0x3C000000  header, 48 bytes used
//   0x3C001000  slot ring, 4 slots x (SLOT_WORDS * 8) bytes, slot = frame & 3
//
// Header (little endian 64 bit words):
//   h0  magic  "MC-" + 4 id bytes ("NES\0", "GB\0\0") + \0 + \1
//   h1  [31:0] layout version = 3     [63:32] slot size in bytes
//   h2  [31:0] frame (written last)   [63:32] slot count = 4
//   h3  [31:0] flags: bit0 enabled    [63:32] replay state (rtl/mc/mc_replay.sv)
//   h4  [31:0] core clock Hz          [63:32] system type (core specific)
//   h5  [31:0] RAM image size in bytes  [39:32] pad count  [47:40] regs kind
//       [55:48] register bus words      [63:56] replay entry bytes
//       regs kind: 0 = slot word 1 holds the CPU registers as T65 packs them
//       (NES); 1 = slot word 1 is unused, the registers are on the bus words
//       (Gameboy: reg_savestates.vhd index 1..5)
// The header is written every frame, also while telemetry is off, so a reader
// can tell "off" (frame advances, bit0 clear) from "no MC core" (no magic).
// Layout 2 (the shipped MC-NES_20260904) had no h5; its sizes are the NES
// defaults below and the app keeps decoding it.
//
// Slot (byte offsets; RAM_WORDS = RAM bytes / 8, BM_WORDS = RAM bytes / 64):
//   0x000  [31:0] frame  [40:32] scanline  [56:48] cycle at snapshot
//   0x008  CPU registers (regs kind 0): [63:48] PC [47:32] S [31:24] P
//          [23:16] Y [15:8] X [7:0] A
//   0x010  [7:0] pad 1 latched at the last strobe  [15:8] pad 2
//          [23:16] strobes this frame (saturates at 255)
//          [24] register words valid  [25] RAM torn  [26] replay active
//          [39:32] pad 3  [47:40] pad 4 (zero when PAD_COUNT is 2)
//   0x018  [31:0] replay entry index  [39:32] replay state  [47:40] replay
//          generation  [63:48] joypad reads this frame (saturates; 0 = a lag
//          frame by the emulator's rule, docs/TAS-semantics.md)
//   0x040  64 x 64 bit: the save state register bus, words 0..63
//   0x240  RAM image (2048 bytes on the NES: CPU work RAM $0000-$07FF)
//   0x240 + RAM bytes        written-bitmap (bit i of byte n = RAM byte n*8+i
//                            written since the ROM was loaded), RAM bytes / 8
//   0x240 + RAM bytes * 9/8  [31:0] frame again (a reader accepts the slot
//                            only if both match)
//   NES: bitmap at 0xA40, tail at 0xB40, slot 4096 bytes.
//
// Order of writes: words 0, 1, 3, registers, RAM, bitmap, word 2 (its flags
// are only known after the RAM read-out), tail, header constants, header frame.
//
// The snapshot starts on the rising edge of vblank. The shadow RAM is held for
// the whole RAM read-out, so the RAM image is the state at that instant; the
// register words are read live from the bus a few clocks later, while the CPU
// is already inside its NMI handler. Each word is what it says at the clock
// it was read.
//
// Copyright (c) 2026 Remmy Lee. GPLv3, like the core it lives in.

module mc_telemetry
#(
	parameter [63:0] MAGIC      = 64'h01005345_4E2D434D,   // "MC-NES\0\1"
	parameter        RAM_ADDR_W = 11,                     // RAM image = 2^RAM_ADDR_W bytes
	parameter        PAD_COUNT  = 2,                      // 2 or 4 pads in slot word 2
	parameter        REGS_KIND  = 0,                      // header h5[47:40]
	parameter [24:0] SLOT_WORDS = 25'd512,                // slot stride in 64 bit words (>= 73 + RAM bytes * 9/64)
	parameter [24:0] HEADER_WORD = 25'h1800000,           // (0x3C000000 - 0x30000000) >> 3
	parameter [24:0] SLOT0_WORD  = 25'h1800200            // (0x3C001000 - 0x30000000) >> 3
)
(
	input             clk,
	input             reset,
	input             enable,

	input             vblank,
	input       [8:0] scanline,
	input       [8:0] cycle,
	input      [31:0] clk_hz,
	input       [2:0] sys_type,

	input      [63:0] cpu_regs,

	// save state register bus, read live
	output reg  [9:0] bus_adr,
	input      [63:0] bus_dout,
	input             bus_free,

	// shadow RAM
	output reg        ram_hold,
	output reg [RAM_ADDR_W-1:0] ram_rd_addr,
	input       [7:0] ram_rd_data,     // valid the clock after ram_rd_addr
	output reg [RAM_ADDR_W-4:0] bm_addr,
	input       [7:0] bm_data,         // valid the clock after bm_addr
	input             ram_torn,

	// pads latched by the game
	input       [7:0] joy1_latched,
	input       [7:0] joy2_latched,
	input       [7:0] joy3_latched,    // tie to 0 with PAD_COUNT 2
	input       [7:0] joy4_latched,
	input             joy_strobe,      // one clock per strobe rising edge
	input             joy_read,        // one clock per controller read

	input             replay_active,
	input      [31:0] replay_index,
	input       [7:0] replay_state,
	input       [7:0] replay_gen,
	input       [7:0] replay_entry_bytes,

	// DDR write channel (64 bit word address inside the 0x30000000 window)
	output reg [24:0] ddr_addr,
	output reg [63:0] ddr_din,
	output reg        ddr_req,
	input             ddr_ready,

	output reg [31:0] frame
);

localparam        RAM_BYTES = 1 << RAM_ADDR_W;
localparam        IDX_W     = RAM_ADDR_W - 3;             // RAM word index width (8 on the NES)
localparam        BM_IDX_W  = RAM_ADDR_W - 6;             // bitmap word index width (5 on the NES)
localparam [24:0] RAM_WORDS = 25'(RAM_BYTES / 8);
localparam [24:0] BM_WORDS  = 25'(RAM_BYTES / 64);

// slot word offsets
localparam [24:0] W_REGS = 25'd8;                        // 0x040
localparam [24:0] W_RAM  = 25'd72;                       // 0x240
localparam [24:0] W_BM   = W_RAM + RAM_WORDS;
localparam [24:0] W_TAIL = W_BM + BM_WORDS;

localparam [31:0] LAYOUT    = 32'd3;
localparam [31:0] SLOT_SIZE = {SLOT_WORDS, 3'd0};        // bytes

initial begin
	if (IDX_W < 6)          $error("mc_telemetry: RAM_ADDR_W must be at least 9");
	if (SLOT_WORDS <= W_TAIL) $error("mc_telemetry: SLOT_WORDS %0d does not hold the slot (%0d words)", SLOT_WORDS, W_TAIL + 1);
	if (PAD_COUNT != 2 && PAD_COUNT != 4) $error("mc_telemetry: PAD_COUNT must be 2 or 4");
end

// ---- per-frame inputs --------------------------------------------------------
reg vblank_d = 0;
wire frame_start = vblank & ~vblank_d;

reg  [7:0] strobes = 0;
reg [15:0] reads = 0;
always @(posedge clk) begin
	vblank_d <= vblank;
	if (frame_start) begin
		strobes <= 0;
		reads   <= 0;
	end
	else begin
		if (joy_strobe && strobes != 8'hFF) strobes <= strobes + 8'd1;
		if (joy_read && reads != 16'hFFFF) reads <= reads + 16'd1;
	end
end

wire [1:0] next_slot = frame[1:0] + 2'd1;   // 2 bit wire: wraps

// ---- snapshot state machine --------------------------------------------------
typedef enum logic [3:0] {
	IDLE, HEAD, REGS_SET, REGS_GET, RAM_RUN, RAM_W1, RAM_W2, BM_RUN, BM_W1, BM_W2,
	FLAGS, TAIL, HDR, WRITE
} st_t;

st_t st = IDLE, after_write = IDLE;

reg [63:0] snap_regs;
reg  [8:0] snap_scanline, snap_cycle;
reg  [7:0] snap_strobes, snap_j1, snap_j2, snap_j3, snap_j4;
reg [15:0] snap_reads;
reg        snap_bus_ok;
reg [24:0] slot_base;
reg [IDX_W-1:0] idx;     // word index within the current section
reg  [2:0] byte_idx;     // byte being addressed
reg [63:0] acc;

// read pipeline: an address set at clock k is registered at k, the RAM
// registers its data at k+1, so the byte is on the input during clock k+2.
reg  [2:0] p1_b, p2_b;
reg        p1_v = 0, p2_v = 0, p1_src, p2_src;   // src 0 = RAM, 1 = bitmap
reg  [2:0] hdr_idx;

task automatic write_word(input [24:0] a, input [63:0] d, input st_t next);
	ddr_addr    <= a;
	ddr_din     <= d;
	ddr_req     <= 1;
	after_write <= next;
	st          <= WRITE;
endtask

always @(posedge clk) begin
	ddr_req <= 0;
	p1_v    <= 0;
	p2_v    <= p1_v;  p2_b <= p1_b;  p2_src <= p1_src;
	if (p2_v) acc[p2_b*8 +: 8] <= p2_src ? bm_data : ram_rd_data;

	if (reset) begin
		st       <= IDLE;
		ram_hold <= 0;
		frame    <= 0;
	end
	else case (st)

	IDLE: if (frame_start) begin
		frame     <= frame + 32'd1;
		slot_base <= SLOT0_WORD + {23'd0, next_slot} * SLOT_WORDS;
		idx       <= 0;
		byte_idx  <= 0;
		hdr_idx   <= 0;
		if (enable) begin
			ram_hold      <= 1;
			snap_regs     <= cpu_regs;
			snap_scanline <= scanline;
			snap_cycle    <= cycle;
			snap_strobes  <= strobes;
			snap_reads    <= reads;
			snap_j1       <= joy1_latched;
			snap_j2       <= joy2_latched;
			snap_j3       <= (PAD_COUNT == 4) ? joy3_latched : 8'd0;
			snap_j4       <= (PAD_COUNT == 4) ? joy4_latched : 8'd0;
			snap_bus_ok   <= bus_free;
			st            <= HEAD;
		end
		else st <= HDR;
	end

	// slot words 0, 1, 3 (word 2 carries flags known only at the end)
	HEAD: begin
		idx <= idx + 1'd1;
		case (idx[1:0])
		2'd0: write_word(slot_base + 25'd0, {7'd0, snap_cycle, 7'd0, snap_scanline, frame}, HEAD);
		2'd1: write_word(slot_base + 25'd1, snap_regs, HEAD);
		default: begin
			idx <= 0;
			write_word(slot_base + 25'd3, {snap_reads, replay_gen, replay_state, replay_index}, st_t'(snap_bus_ok ? REGS_SET : RAM_RUN));
		end
		endcase
	end

	// register bus: the read is combinational from bus_adr; present, then take
	REGS_SET: begin
		bus_adr <= {4'd0, idx[5:0]};
		st      <= REGS_GET;
	end
	REGS_GET: begin
		if (!bus_free) begin
			snap_bus_ok <= 0;           // a save or load took the bus mid-read
			idx         <= 0;
			st          <= RAM_RUN;
		end
		else begin
			idx <= (idx[5:0] == 6'd63) ? {IDX_W{1'b0}} : idx + 1'd1;
			write_word(slot_base + W_REGS + {19'd0, idx[5:0]}, bus_dout, st_t'((idx[5:0] == 6'd63) ? RAM_RUN : REGS_SET));
		end
	end

	// RAM: address one byte per clock; the pipeline above captures each byte
	// two clocks later. Bytes 0..6 land during RAM_RUN and RAM_W1; byte 7 is
	// on the input during RAM_W2 and goes straight into the word.
	RAM_RUN: begin
		ram_rd_addr <= {idx, byte_idx};
		p1_v <= 1;  p1_b <= byte_idx;  p1_src <= 0;
		byte_idx <= byte_idx + 3'd1;
		if (byte_idx == 3'd7) st <= RAM_W1;
	end
	RAM_W1: st <= RAM_W2;
	RAM_W2: begin
		// the RAM holds 2^IDX_W words, so the last index is all ones
		idx <= (&idx) ? {IDX_W{1'b0}} : idx + 1'd1;
		write_word(slot_base + W_RAM + 25'(idx), {ram_rd_data, acc[55:0]}, st_t'((&idx) ? BM_RUN : RAM_RUN));
	end

	// written bitmap: RAM bytes / 64 words, same pipeline
	BM_RUN: begin
		bm_addr <= {idx[BM_IDX_W-1:0], byte_idx};
		p1_v <= 1;  p1_b <= byte_idx;  p1_src <= 1;
		byte_idx <= byte_idx + 3'd1;
		if (byte_idx == 3'd7) st <= BM_W1;
	end
	BM_W1: st <= BM_W2;
	BM_W2: begin
		idx <= idx + 1'd1;
		write_word(slot_base + W_BM + 25'(idx[BM_IDX_W-1:0]), {bm_data, acc[55:0]}, st_t'((&idx[BM_IDX_W-1:0]) ? FLAGS : BM_RUN));
	end

	FLAGS: begin
		ram_hold  <= 0;                      // RAM image complete; the FIFO drains
		write_word(slot_base + 25'd2,
			{16'd0, snap_j4, snap_j3, 5'd0, replay_active, ram_torn, snap_bus_ok, snap_strobes, snap_j2, snap_j1}, TAIL);
	end

	TAIL: write_word(slot_base + W_TAIL, {frame, frame}, HDR);

	HDR: begin
		hdr_idx <= hdr_idx + 3'd1;
		case (hdr_idx)
		3'd0: write_word(HEADER_WORD + 25'd0, MAGIC, HDR);
		3'd1: write_word(HEADER_WORD + 25'd1, {SLOT_SIZE, LAYOUT}, HDR);
		3'd2: write_word(HEADER_WORD + 25'd3, {24'd0, replay_state, 31'd0, enable}, HDR);
		3'd3: write_word(HEADER_WORD + 25'd4, {29'd0, sys_type, clk_hz}, HDR);
		3'd4: write_word(HEADER_WORD + 25'd5, {replay_entry_bytes, 8'd64, 8'(REGS_KIND), 8'(PAD_COUNT), 32'(RAM_BYTES)}, HDR);
		default: write_word(HEADER_WORD + 25'd2, {32'd4, frame}, IDLE);
		endcase
	end

	WRITE: if (ddr_ready) st <= after_write;

	default: st <= IDLE;
	endcase
end

endmodule
