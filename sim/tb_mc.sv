// Testbench for rtl/mc: mc_shadow_ram + mc_telemetry with a DDR write sink.
// Run: sim/run.sh   (Icarus Verilog, -g2012); it runs the NES geometry
// (defaults) and the Gameboy one (-P tb_mc.RAM_ADDR_W=15 -P tb_mc.PAD_COUNT=4
// -P tb_mc.SLOT_WORDS=5120).
//
// Checks, per frame:
//   header magic and frame word, slot frame head and tail, RAM bytes written
//   through the FIFO (held during the read-out), the written bitmap, the pad
//   latch and strobe count, the register bus words, and that a write during the
//   hold lands in the NEXT frame's image, not this one.
`timescale 1ns/1ps

module tb_mc;

parameter RAM_ADDR_W = 11;
parameter PAD_COUNT  = 2;
parameter SLOT_WORDS = 512;
parameter TRACE = 0;
localparam RAM_BYTES = 1 << RAM_ADDR_W;
localparam RAM_WORDS = RAM_BYTES / 8;
localparam BM_WORDS  = RAM_BYTES / 64;
localparam W_BM      = 72 + RAM_WORDS;
localparam W_TAIL    = W_BM + BM_WORDS;
localparam [RAM_ADDR_W-1:0] LAST = {RAM_ADDR_W{1'b1}};   // the highest RAM address
localparam integer RING = 512 + 4 * SLOT_WORDS;           // the trace ring sits after the slots (64 words)
localparam integer WIN = RING + 1024;                      // DDR words the sink records (the ring is 1024 words)
localparam [63:0] MAGIC = (RAM_ADDR_W == 11) ? 64'h01005345_4E2D434D : 64'h01000042_472D434D;   // "MC-NES\0\1" / "MC-GB\0\0\1"

reg clk = 0;
always #23.28 clk = ~clk;      // 21.477 MHz

reg reset = 1, enable = 1, vblank = 0;
reg [8:0] scanline = 9'd241, cycle = 9'd5;
reg [63:0] cpu_regs = 64'h8000_01FD_2411_2233;

// register bus model: word k reads as k repeated
wire [9:0] bus_adr;
wire [63:0] bus_dout = {8{bus_adr[7:0]}} ^ 64'hA5A5_0000_0000_0000;
reg bus_free = 1;

// shadow RAM
reg wr = 0; reg [RAM_ADDR_W-1:0] wr_addr = 0; reg [7:0] wr_data = 0;
wire hold; wire [RAM_ADDR_W-1:0] rd_addr; wire [7:0] rd_data; wire [RAM_ADDR_W-4:0] bm_addr; wire [7:0] bm_data; wire torn;
reg clear = 0;

mc_shadow_ram #(.ADDR_W(RAM_ADDR_W), .FIFO_W((RAM_ADDR_W >= 15) ? RAM_ADDR_W - 4 : 9)) sh (.clk(clk), .clear(clear), .wr(wr), .wr_addr(wr_addr), .wr_data(wr_data),
	.hold(hold), .rd_addr(rd_addr), .rd_data(rd_data), .bm_addr(bm_addr), .bm_data(bm_data), .torn(torn));

integer errors = 0;
// DDR sink: records every word by address
wire [24:0] ddr_addr; wire [63:0] ddr_din; wire ddr_req; reg ddr_ready = 0;
// the header page and the four slots, starting at the header word (0x1800000)
reg [63:0] ddr [0:WIN-1];
reg        ddr_seen [0:WIN-1];
integer ddr_writes = 0;
integer i;
initial for (i = 0; i < WIN; i = i + 1) begin ddr[i] = 64'hx; ddr_seen[i] = 0; end
always @(posedge clk) begin
	ddr_ready <= 0;
	if (ddr_req) begin
		if (ddr_addr < 25'h1800000 || ddr_addr >= 25'h1800000 + WIN) begin
			$display("FAIL: write outside the MC window: %h", ddr_addr);
			errors = errors + 1;
		end
		else begin
			ddr[ddr_addr - 25'h1800000] = ddr_din;
			ddr_seen[ddr_addr - 25'h1800000] = 1;
		end
		ddr_writes = ddr_writes + 1;
		ddr_ready <= 1;             // one clock later, like the arbiter when idle
	end
end

reg [7:0] j1 = 8'h12, j2 = 8'h34, j3 = 8'h56, j4 = 8'h78; reg strobe = 0;
wire [31:0] frame;
localparam [7:0] EB = (PAD_COUNT == 4) ? 8'd8 : 8'd4;   // what the replay module would report

reg tr_we = 0; reg [15:0] tr_pc = 0, tr_cyc = 0;
task fetch(input [15:0] pc, input [15:0] cyc);
	@(posedge clk); tr_we <= 1; tr_pc <= pc; tr_cyc <= cyc;
	@(posedge clk); tr_we <= 0;
	repeat (30) @(posedge clk);
endtask

mc_telemetry #(.MAGIC(MAGIC), .RAM_ADDR_W(RAM_ADDR_W), .PAD_COUNT(PAD_COUNT), .REGS_KIND((PAD_COUNT == 4) ? 1 : 0), .SLOT_WORDS(SLOT_WORDS),
	.TRACE(TRACE), .RING_WORD(25'h1800000 + RING), .RING_W(10)) dut (
	.clk(clk), .reset(reset), .enable(enable), .vblank(vblank), .scanline(scanline), .cycle(cycle),
	.trace_we(tr_we), .trace_pc(tr_pc), .trace_cyc(tr_cyc),
	.clk_hz(32'd21477272), .sys_type(3'd0), .cpu_regs(cpu_regs),
	.bus_adr(bus_adr), .bus_dout(bus_dout), .bus_free(bus_free),
	.ram_hold(hold), .ram_rd_addr(rd_addr), .ram_rd_data(rd_data), .bm_addr(bm_addr), .bm_data(bm_data), .ram_torn(torn),
	.joy1_latched(j1), .joy2_latched(j2), .joy3_latched(j3), .joy4_latched(j4), .joy_strobe(strobe), .joy_read(strobe),
	.replay_active(1'b0), .replay_index(32'd77), .replay_state(8'd2), .replay_gen(8'd9), .replay_entry_bytes(EB),
	.ddr_addr(ddr_addr), .ddr_din(ddr_din), .ddr_req(ddr_req), .ddr_ready(ddr_ready), .frame(frame));

localparam integer HDR  = 0;
localparam integer SLOT0 = 512;

task check(input string what, input longint got, input longint want);
	if (got !== want) begin
		$display("FAIL %s: got %h want %h", what, got, want);
		errors = errors + 1;
	end
endtask

// write one byte into the work RAM the way the CPU does: level held 12 clocks
task ram_write(input [RAM_ADDR_W-1:0] a, input [7:0] d);
	@(posedge clk); wr <= 1; wr_addr <= a; wr_data <= d;
	repeat (12) @(posedge clk);
	wr <= 0; @(posedge clk);
endtask

task pulse_strobe;
	@(posedge clk); strobe <= 1; @(posedge clk); strobe <= 0;
endtask

task frame_tick;  // vblank rising edge, then wait for the snapshot to finish
	@(posedge clk); vblank <= 1;
	repeat (20) @(posedge clk);
	vblank <= 0;
	wait (dut.st == dut.IDLE);
	repeat (4) @(posedge clk);
endtask

longint slot;
initial begin
	repeat (5) @(posedge clk);
	reset = 0;
	// power-on style clear of the bitmap, then a few RAM writes
	clear = 1; repeat (3) @(posedge clk); clear = 0;
	wait (!sh.clearing);            // the bitmap walk: 256 clocks on the NES, 4096 on the Gameboy
	repeat (20) @(posedge clk);
	ram_write(0, 8'hAA);
	ram_write(1, 8'hBB);
	ram_write(LAST, 8'hCC);
	ram_write(11'h75A, 8'h03);   // "lives" in SMB
	pulse_strobe; pulse_strobe;   // two strobes this frame

	// ---- frame 1
	frame_tick;
	check("frame", frame, 1);
	slot = SLOT0 + 1*SLOT_WORDS;
	check("hdr magic", ddr[HDR+0], MAGIC);
	check("hdr h1", ddr[HDR+1], {32'(SLOT_WORDS * 8), 32'd3});
	check("hdr h2", ddr[HDR+2], {32'd4, 32'd1});
	check("hdr h3", ddr[HDR+3], {24'd0, 8'd2, 32'(1 + 2 * TRACE)});
	check("hdr h5", ddr[HDR+5], {EB, 8'd64, 8'((PAD_COUNT == 4) ? 1 : 0), 8'(PAD_COUNT), 32'(RAM_BYTES)});
	check("slot w3 replay/reads", ddr[slot+3], {16'd2, 8'd9, 8'd2, 32'd77});
	check("slot w0", ddr[slot+0], {7'd0, cycle, 7'd0, scanline, 32'd1});
	check("slot w1", ddr[slot+1], cpu_regs);
	if (PAD_COUNT == 4)
		check("slot w2 pads/strobes/flags", ddr[slot+2], {16'd0, j4, j3, 5'd0, 1'b0, 1'b0, 1'b1, 8'd2, j2, j1});
	else
		check("slot w2 pads/strobes/flags", ddr[slot+2], {32'd0, 5'd0, 1'b0, 1'b0, 1'b1, 8'd2, j2, j1});
	check("regs word 0", ddr[slot+8+0], {8{8'd0}} ^ 64'hA5A5_0000_0000_0000);
	check("regs word 63", ddr[slot+8+63], {8{8'd63}} ^ 64'hA5A5_0000_0000_0000);
	check("ram word 0", ddr[slot+72+0][15:0], 16'hBBAA);
	check("ram last word top byte", ddr[slot+72+RAM_WORDS-1][63:56], 8'hCC);
	check("ram $075A", ddr[slot+72+(11'h75A>>3)][(11'h75A%8)*8 +: 8], 8'h03);
	check("bitmap byte 0", ddr[slot+W_BM+0][7:0], 8'b0000_0011);
	check("bitmap last byte", ddr[slot+W_BM+BM_WORDS-1][63:56], 8'b1000_0000);
	check("bitmap $075A", ddr[slot+W_BM+((11'h75A>>3)>>3)][((11'h75A>>3)%8)*8 + (11'h75A%8)], 1'b1);
	check("tail", ddr[slot+W_TAIL], {32'd1, 32'd1});
	check("nothing past the tail", ddr_seen[slot+W_TAIL+1], 0);
	check("nothing in the next slot", ddr_seen[SLOT0 + 2*SLOT_WORDS], 0);

	// ---- frame 2: no strobes (lag frame); a write during the hold must not
	// appear in this image but in the next
	fork
		frame_tick;
		begin
			wait (hold);
			repeat (40) @(posedge clk);
			ram_write(0, 8'h55);   // arrives while held
		end
	join
	check("frame", frame, 2);
	slot = SLOT0 + 2*SLOT_WORDS;
	check("lag frame strobes", ddr[slot+2][23:16], 8'd0);
	check("held write not in frame 2", ddr[slot+72+0][7:0], 8'hAA);
	check("torn flag clear", ddr[slot+2][25], 1'b0);

	// ---- frame 3: the held write has drained
	frame_tick;
	slot = SLOT0 + 3*SLOT_WORDS;
	check("drained write in frame 3", ddr[slot+72+0][7:0], 8'h55);
	check("hdr h2 frame 3", ddr[HDR+2][31:0], 32'd3);

	// ---- frame 4: telemetry off: header still written, slot 0 untouched
	enable = 0;
	for (i = 0; i < WIN; i = i + 1) ddr_seen[i] = 0;
	frame_tick;
	check("off: hdr h2", ddr[HDR+2][31:0], 32'd4);
	check("off: hdr h3 flags", ddr[HDR+3][31:0], 32'(2 * TRACE));
	check("off: slot untouched", ddr_seen[SLOT0 + 0*SLOT_WORDS], 0);

	// ---- frame 5: bus busy mid-read: flag clears, RAM still written
	enable = 1;
	fork
		frame_tick;
		begin
			wait (dut.st == dut.REGS_GET);
			repeat (30) @(posedge clk);
			bus_free = 0;
			repeat (200) @(posedge clk);
			bus_free = 1;
		end
	join
	slot = SLOT0 + 1*SLOT_WORDS;
	check("bus busy: regs flag clear", ddr[slot+2][24], 1'b0);
	check("bus busy: ram present", ddr[slot+72+0][7:0], 8'h55);
	check("bus busy: tail", ddr[slot+W_TAIL][31:0], 32'd5);

	if (TRACE) begin
		// ---- the instruction trace: every vblank edge queued a marker, so the
		// markers of frames 1..4 filled ring words 0 and 1 in pairs; marker 5
		// waits. Frame 6's marker pairs with it, then fetches follow.
		check("ring w0 markers 1,2", ddr[RING+0], {16'hFFFF, 16'd2, 16'hFFFF, 16'd1});
		check("ring w1 markers 3,4", ddr[RING+1], {16'hFFFF, 16'd4, 16'hFFFF, 16'd3});
		frame_tick;
		repeat (20) @(posedge clk);
		check("ring w2 markers 5,6", ddr[RING+2], {16'hFFFF, 16'd6, 16'hFFFF, 16'd5});
		check("hdr h6 ptr after frame 6", ddr[HDR+6][31:0], 32'd2);
		check("hdr h6 ring size", ddr[HDR+6][63:56], 8'd10);
		check("hdr h3 trace bit", ddr[HDR+3][1], 1'b1);
		fetch(16'h0100, 16'd10);
		fetch(16'h0103, 16'd14);
		repeat (20) @(posedge clk);
		check("ring w3 two fetches", ddr[RING+3], {16'd14, 16'h0103, 16'd10, 16'h0100});
		fetch(16'h2000, 16'hFFFF);   // a real cycle of FFFF is written FFFE
		check("fetch waits for a pair", ddr_seen[RING+4], 0);
		frame_tick;                  // marker 7 pairs with it, drained after the snapshot
		repeat (20) @(posedge clk);
		check("ring w4 fetch + marker 7", ddr[RING+4], {16'hFFFF, 16'd7, 16'hFFFE, 16'h2000});
		check("hdr h6 ptr after frame 7", ddr[HDR+6][31:0], 32'd4);
		check("frame 7 slot tail", ddr[SLOT0 + 3*SLOT_WORDS + W_TAIL][31:0], 32'd7);
		// ---- 700 fetches during frame 8's snapshot: the FIFO (1023 entries) must
		// not lose any, the snapshot must still complete, and the ring holds
		// marker 8 then the fetches in order (the drain interleaves with the
		// snapshot once the FIFO is half full).
		fork
			frame_tick;
			begin
				repeat (40) @(posedge clk);
				for (i = 0; i < 700; i = i + 1) fetch(16'h3000 + i[15:0], 16'd100 + i[15:0]);
			end
		join
		wait (dut.st == dut.IDLE && dut.tr_count < 2);
		repeat (20) @(posedge clk);
		check("frame 8 slot tail", ddr[SLOT0 + 0*SLOT_WORDS + W_TAIL][31:0], 32'd8);
		check("hdr h6 drops after frame 8", ddr[HDR+6][47:32], 16'd0);
		check("ring w5 marker 8 + fetch 0", ddr[RING+5], {16'd100, 16'h3000, 16'hFFFF, 16'd8});
		for (i = 6; i < 355; i = i + 1)
			if (ddr[RING+i] !== {16'(100 + 2*(i-5)), 16'(16'h3000 + 2*(i-5)), 16'(100 + 2*(i-5) - 1), 16'(16'h3000 + 2*(i-5) - 1)}) begin
				$display("FAIL ring word %0d during the snapshot: got %h", i, ddr[RING+i]);
				errors = errors + 1;
			end
		check("fetch 699 waits for a pair", ddr_seen[RING+355], 0);
		check("ring ptr after the drain", dut.ring_ptr, 10'd355);
	end
	else begin
		check("hdr h3 no trace", ddr[HDR+3][1], 1'b0);
		check("hdr h6 no ring", ddr[HDR+6], 64'd0);
		check("ring untouched", ddr_seen[RING], 0);
	end

	$display("RAM_ADDR_W=%0d PAD_COUNT=%0d SLOT_WORDS=%0d: %0d DDR writes over 5 frames", RAM_ADDR_W, PAD_COUNT, SLOT_WORDS, ddr_writes);
	if (errors == 0) $display("PASS"); else $display("%0d FAILURES", errors);
	$finish;
end

// measure one snapshot's length in clocks
integer t0, t1;
always @(posedge clk) begin
	if (dut.st == dut.IDLE && vblank && !dut.vblank_d) t0 = $time;
	if (dut.st == dut.WRITE && dut.after_write == dut.IDLE && dut.ddr_req) begin
		t1 = $time;
		$display("snapshot: %0d clocks (%0.1f us)", (t1 - t0) / 46.56, (t1 - t0) / 1000.0);
	end
end

endmodule
