// mc_shadow_ram: a copy of the console's work RAM that the telemetry block
// can read without touching the core's own memory.
//
// Sized by ADDR_W: 11 on the NES (the 2 KB CPU work RAM $0000-$07FF, kept
// upstream in SDRAM at linear 0x380000, cart.sv:2552), 15 on the Gameboy (the
// 32 KB WRAM dpram, whose second port is the save-state path).
// Every write that reaches the RAM is mirrored here: CPU writes, the loader's
// "RAM Clear" fill, and a save state load. Writes enter through a FIFO. While
// `hold` is high (a snapshot is being read out) the FIFO keeps the writes
// back, so the read-out sees the RAM exactly as it was at the hold instant.
// When `hold` drops the FIFO drains. If the FIFO fills while held, `torn` is
// raised for that snapshot. NES: the CPU writes at most one byte per 12 clocks
// at 21.48 MHz and the read-out takes about 2100 clocks. Gameboy: at most one
// byte per 32 clocks at 67.1 MHz (a store every 8 T-cycles at 4.19 MHz) and
// the read-out takes about 56000 clocks (sim/tb_mc.sv with a one-clock DDR
// sink: 55584; 1.66 ms at the Gameboy's 33.55 MHz clk_sys), so up to ~870
// writes (1740 in GBC double speed) could queue in the worst case, an
// unrolled `ld (hl+),a` for the whole read-out; the Gameboy build uses 2048
// entries (FIFO_W 11). A save-state load writes one byte per clock in bursts
// of 8 between DDR reads; the drain takes one every 2 clocks and catches up
// in the gaps.
//
// `written` is a per-byte flag, set on the first write since `clear`, so a
// reader can tell a real value from stale power-on content when "RAM Clear" is
// off. It lives in a (2^ADDR_W / 8) x 8 RAM updated read-modify-write from the
// drain path; consecutive drains are at least 2 clocks apart by construction
// of the FIFO pop, which is what the RMW needs.
//
// Copyright (c) 2026 Remmy Lee. GPLv3, like the core it lives in.

module mc_shadow_ram
#(
	parameter ADDR_W = 11,           // RAM copy = 2^ADDR_W bytes
	parameter FIFO_W = 9             // pending-write FIFO = 2^FIFO_W entries (512 NES, 2048 Gameboy)
)
(
	input             clk,
	input             clear,      // core start: mark every byte unwritten

	// write side (mirrors of the core's RAM writes)
	input             wr,
	input      [ADDR_W-1:0] wr_addr,
	input       [7:0] wr_data,

	// snapshot read side
	input             hold,       // 1 while a snapshot is read; writes queue up
	input      [ADDR_W-1:0] rd_addr,
	output reg  [7:0] rd_data,    // valid the clock after rd_addr
	input      [ADDR_W-4:0] bm_addr,    // bitmap byte address (bit i = byte bm_addr*8+i)
	output reg  [7:0] bm_data,    // valid the clock after bm_addr
	output reg        torn        // FIFO overflowed during the last hold
);

localparam BM_W = ADDR_W - 3;     // bitmap byte address width

// ---- input stage: the SDRAM write strobes are levels held for the whole
// CPU cycle (12 clocks), so one transaction is taken once: on the first clock
// it is seen, and again only when the address or data changes.
reg        wr_d = 0;
reg [ADDR_W-1:0] wa_d;
reg  [7:0] wd_d;
wire       wr_new = wr && !(wr_d && wa_d == wr_addr && wd_d == wr_data);
always @(posedge clk) begin
	wr_d <= wr;
	wa_d <= wr_addr;
	wd_d <= wr_data;
end

// ---- FIFO of pending writes (2^FIFO_W deep) ---------------------------------
reg [ADDR_W+7:0] fifo [0:(1<<FIFO_W)-1];
reg  [FIFO_W-1:0] wp = 0, rp = 0;
wire       empty = (wp == rp);
wire [FIFO_W-1:0] wp_next = wp + 1'd1;
wire       full  = (wp_next == rp);

always @(posedge clk) begin
	if (wr_new && !full) begin
		fifo[wp] <= {wr_addr, wr_data};
		wp <= wp_next;
	end
end

// ---- the RAM copy ------------------------------------------------------------
reg [7:0] mem [0:(1<<ADDR_W)-1];
reg       clearing = 0;     // bitmap clear in progress (declared here: used by the drain)

// drain: one pop every 2 clocks (pop, then RMW the bitmap on the next clock)
reg        pop = 0;
reg [ADDR_W+7:0] cur;
reg        drain_wr = 0;
reg [ADDR_W-1:0] drain_addr;
reg  [7:0] drain_data;

always @(posedge clk) begin
	drain_wr <= 0;
	if (!hold && !clearing && !empty && !pop) begin
		cur <= fifo[rp];
		rp <= rp + 1'd1;
		pop <= 1;
	end
	else if (pop) begin
		pop        <= 0;
		drain_wr   <= 1;
		drain_addr <= cur[ADDR_W+7:8];
		drain_data <= cur[7:0];
	end
end

always @(posedge clk) begin
	if (drain_wr) mem[drain_addr] <= drain_data;
	rd_data <= mem[rd_addr];
end

// ---- written bitmap (2^BM_W x 8, read-modify-write) --------------------------
reg [7:0] bitmap [0:(1<<BM_W)-1];
reg       bm_rmw = 0;
reg [BM_W-1:0] bm_rmw_addr;
reg [2:0] bm_rmw_bit;
reg [7:0] bm_rmw_old;

// clear walks the bitmap on the rising edge of `clear`; takes 2^BM_W clocks
// (256 on the NES, 4096 on the Gameboy), during which the FIFO does not drain
// (writes queue up; the core is in reset for the whole download anyway).
reg       clear_d = 0;
reg [BM_W-1:0] clear_addr;

always @(posedge clk) begin
	bm_rmw  <= 0;
	clear_d <= clear;
	if (clear && !clear_d && !clearing) begin
		clearing   <= 1;
		clear_addr <= 0;
	end
	if (clearing) begin
		bitmap[clear_addr] <= 8'h00;
		clear_addr <= clear_addr + 1'd1;
		if (&clear_addr) clearing <= 0;
	end
	else begin
		if (drain_wr) begin
			bm_rmw      <= 1;
			bm_rmw_addr <= drain_addr[ADDR_W-1:3];
			bm_rmw_bit  <= drain_addr[2:0];
			bm_rmw_old  <= bitmap[drain_addr[ADDR_W-1:3]];
		end
		if (bm_rmw) bitmap[bm_rmw_addr] <= bm_rmw_old | (8'h01 << bm_rmw_bit);
	end
	bm_data <= bitmap[bm_addr];
end

// ---- torn flag: set when a write is dropped while held, cleared at hold start
reg hold_d = 0;
always @(posedge clk) begin
	hold_d <= hold;
	if (hold && !hold_d) torn <= 0;
	if (wr_new && full) torn <= 1;
end

endmodule
