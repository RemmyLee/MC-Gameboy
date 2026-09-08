// Testbench for rtl/mc/mc_replay.sv with a DDR read model.
// Run: sim/run.sh (both benches); it runs ENTRY_BYTES 4 (NES) and 8 (Gameboy,
// -P tb_replay.EB=8).
`timescale 1ns/1ps

module tb_replay;

parameter EB = 4;

reg clk = 0;
always #23.28 clk = ~clk;

reg reset = 1, vblank = 0, downloading = 0, joy_read = 0;
reg cyc = 0, lcd_on = 0, m1_irq = 0;
integer errors = 0;

// DDR model: 64 words from the replay header word
localparam [24:0] HDR_W = 25'h1820000;
reg [63:0] mem [0:63];
integer i;
initial for (i = 0; i < 64; i = i + 1) mem[i] = 0;

wire [24:0] ddr_addr; wire ddr_req; reg [63:0] ddr_dout; reg ddr_ready = 0;
reg [24:0] rq_addr; reg [2:0] lat = 0;
always @(posedge clk) begin
	ddr_ready <= 0;
	if (ddr_req) begin rq_addr <= ddr_addr; lat <= 3'd5; end        // ~20 clock latency scaled down
	else if (lat > 1) lat <= lat - 3'd1;
	else if (lat == 1) begin
		lat <= 0;
		if (rq_addr < HDR_W || rq_addr >= HDR_W + 64) begin $display("FAIL read outside buffer %h", rq_addr); errors = errors + 1; end
		else ddr_dout <= mem[rq_addr - HDR_W];
		ddr_ready <= 1;
	end
end

wire active; wire [7:0] p1, p2, p3, p4, state, gen, entry_bytes; wire [31:0] index; wire [1:0] sys_mode;
mc_replay #(.ENTRY_BYTES(EB)) dut (.clk(clk), .reset(reset), .downloading(downloading), .vblank(vblank), .joy_read(joy_read), .cyc(cyc), .lcd_on(lcd_on), .m1_irq(m1_irq),
	.ddr_addr(ddr_addr), .ddr_req(ddr_req), .ddr_dout(ddr_dout), .ddr_ready(ddr_ready),
	.active(active), .p1(p1), .p2(p2), .p3(p3), .p4(p4), .index(index), .state(state), .gen(gen), .entry_bytes(entry_bytes), .sys_mode(sys_mode));

// ---- Gambatte frames: CPU cycles and a PPU model ----------------------------
// With the LCD on, the vblank interrupt line rises 65664 cycles after the
// switch-on (line 144) and every 70224 after, for 10 lines.
integer gcyc = 0;      // cycles since the run start
integer lcd_cyc = 0;   // cycles since the LCD was switched on
always @(posedge clk) if (cyc) begin
	if (!lcd_on) begin lcd_cyc <= 0; m1_irq <= 0; end
	else begin
		lcd_cyc <= lcd_cyc + 1;
		m1_irq <= (lcd_cyc >= 65664) && (((lcd_cyc - 65664) % 70224) < 4560);
	end
end
task cycles(input integer n);   // n CPU cycles, one per 8 clocks (33.5 MHz / 4.19 MHz)
	repeat (n) begin @(posedge clk); cyc <= 1; @(posedge clk); cyc <= 0; repeat (6) @(posedge clk); gcyc = gcyc + 1; end
endtask
task at(input integer c, input string what, input integer want);   // run to cycle c + 8 and check the index
	cycles(c + 8 - gcyc);
	check($sformatf("cycle %0d %s", c, what), index, want);
endtask

// write entry i: p1 = i+1, p2 = 0x80+i, p3 = 0x40+i, p4 = 0xC0+i (8 byte layout only), cmd
task put(input integer i, input [7:0] cmd);
	if (EB == 4) begin
		if (i % 2 == 0) mem[8 + i/2][31:0]  = {8'd0, cmd, 8'h80 + i[7:0], i[7:0] + 8'd1};
		else            mem[8 + i/2][63:32] = {8'd0, cmd, 8'h80 + i[7:0], i[7:0] + 8'd1};
	end
	else mem[8 + i] = {24'd0, cmd, 8'hC0 + i[7:0], 8'h40 + i[7:0], 8'h80 + i[7:0], i[7:0] + 8'd1};
endtask

task check(input string what, input longint got, input longint want);
	if (got !== want) begin $display("FAIL %s: got %0d want %0d", what, got, want); errors = errors + 1; end
endtask

task frame;   // one vblank edge
	@(posedge clk); vblank <= 1; repeat (10) @(posedge clk); vblank <= 0; repeat (30) @(posedge clk);
endtask

task polled_frame;   // the game reads the pad, then the frame ends
	@(posedge clk); joy_read <= 1; @(posedge clk); joy_read <= 0; repeat (3) @(posedge clk);
	frame;
endtask

// let the poll timer fire: force it near the wrap
task poll;
	@(negedge clk) dut.poll_cnt = dut.POLL_CLKS - 2;
	repeat (60) @(posedge clk);   // three header reads and the evaluation
endtask

task arm(input [31:0] frames, input [7:0] g);
	mem[0] = 64'h59414C50_522D434D;
	mem[1] = {24'd0, g, frames};
	mem[2] = 64'd1;
	mem[3] = {56'd0, EB[7:0]};
endtask

// a ROM load as NES.sv shows it: reset up, downloading pulses, reset releases
task load;
	reset <= 1; repeat (3) @(posedge clk);
	downloading <= 1; repeat (5) @(posedge clk); downloading <= 0; repeat (3) @(posedge clk);
	reset <= 0; repeat (3) @(posedge clk);
endtask


initial begin
	check("entry_bytes", entry_bytes, EB);
	for (i = 0; i < 10; i = i + 1) put(i, 0);
	repeat (5) @(posedge clk);

	// nothing armed: stays idle, no pads
	poll; check("idle state", state, 0); check("idle active", active, 0);

	// a header whose entry size is not this core's: refused as a layout mismatch
	arm(10, 8'd6); mem[3] = {56'd0, 8'(EB == 4 ? 8 : 4)}; poll;
	check("layout mismatch", state, 7); check("mismatch gen taken", gen, 6); check("mismatch inactive", active, 0);
	// a reset release after that does not start anything
	load; check("mismatch stays", state, 7); check("mismatch still inactive", active, 0);
	reset <= 1; repeat (3) @(posedge clk);

	// arm 10 frames while the core is in reset (a ROM load)
	arm(10, 8'd7); poll;
	check("armed", state, 1); check("gen", gen, 7); check("still inactive", active, 0);

	// the FPGA load's own reset release, no download before it: ignored
	@(posedge clk); reset <= 0; repeat (3) @(posedge clk);
	check("release without download ignored", state, 1); check("still inactive 2", active, 0);
	frame; check("frames while armed do not advance", index, 0);

	// the ROM load's reset release: entry 0 presented at once
	load;
	check("run", state, 2); check("active", active, 1); check("p1 e0", p1, 1); check("p2 e0", p2, 8'h80); check("index 0", index, 0);
	check("p3 e0", p3, (EB == 8) ? 8'h40 : 8'h00); check("p4 e0", p4, (EB == 8) ? 8'hC0 : 8'h00);

	// frames 1..9
	for (i = 1; i < 10; i = i + 1) begin
		frame;
		check($sformatf("index %0d", i), index, i);
		check($sformatf("p1 e%0d", i), p1, i + 1);
		check($sformatf("p2 e%0d", i), p2, 8'h80 + i);
		if (EB == 8) begin
			check($sformatf("p3 e%0d", i), p3, 8'h40 + i);
			check($sformatf("p4 e%0d", i), p4, 8'hC0 + i);
		end
		check("active during run", active, 1);
	end
	frame;   // the 11th vblank: past the end
	check("done", state, 3); check("inactive after done", active, 0);

	// re-arm with the same generation: ignored; new generation: armed again
	arm(10, 8'd7); poll; check("same gen ignored", state, 3);
	arm(4, 8'd8); poll; check("new gen armed", state, 1);
	// abort while armed
	mem[2] = 64'd3; poll; check("abort while armed", state, 4);

	// unsupported command inside a movie: stops at that entry
	put(1, 8'd1);   // entry 1 carries the reset command
	arm(10, 8'd9); poll; check("armed again", state, 1);
	load;
	check("run again", state, 2);
	frame; check("unsupported cmd", state, 5); check("inactive after unsupported", active, 0);
	put(1, 8'd0);
	// a command in entry 2 (an even index: the other half of a word on the NES layout)
	put(2, 8'd2);
	arm(10, 8'd13); poll; load; frame; check("running before entry 2", state, 2);
	frame; check("unsupported cmd at entry 2", state, 5);
	put(2, 8'd0);

	// a reset during a run aborts it
	arm(10, 8'd10); poll; load;
	frame; check("running", state, 2);
	reset <= 1; repeat (3) @(posedge clk); check("reset aborts", state, 4); reset <= 0;

	// poll-indexed mode (w2 bit 2): a frame without a controller read holds the stream
	arm(10, 8'd12); mem[2] = 64'd5; poll; check("poll mode armed", state, 1);
	load;
	check("poll run", state, 2); check("poll entry 0", p1, 1); check("poll index 0", index, 0);
	frame; check("lag frame does not advance", index, 0); check("entry 0 held", p1, 1);
	frame; check("second lag frame holds too", index, 0);
	polled_frame; check("polled frame advances", index, 1); check("entry 1", p1, 2);
	polled_frame; check("second polled frame", index, 2); check("entry 2", p1, 3);
	frame; check("lag frame between polls holds", index, 2);
	polled_frame; check("resumes on the next poll", index, 3);
	reset <= 1; repeat (3) @(posedge clk); check("reset aborts poll run", state, 4); reset <= 0; repeat (3) @(posedge clk);
	mem[2] = 64'd1;

	// console mode (w2 [4:3]) is latched with the arm and survives the run
	arm(4, 8'd20); mem[2] = 64'd1 | (64'd1 << 3); poll; check("dmg mode armed", state, 1); check("sys_mode dmg", sys_mode, 1);
	load; frame; frame; frame; frame; check("dmg run done", state, 3); check("sys_mode held after the run", sys_mode, 1);
	arm(4, 8'd21); mem[2] = 64'd1 | (64'd3 << 3); poll; check("sys_mode sgb", sys_mode, 3);
	load; frame; frame; frame; frame; check("sgb run done", state, 3);
	arm(4, 8'd22); mem[2] = 64'd1; poll; check("sys_mode menu", sys_mode, 0);
	load; frame; frame; frame; frame;

	// Gambatte frames (w2 bit 5): the entry advances at libgambatte's frame
	// ends, counted in CPU cycles (the model in mc_replay.sv); vblank is ignored
	arm(100, 8'd30); mem[2] = 64'd1 | (64'd1 << 5); poll; check("gambatte armed", state, 1);
	lcd_on <= 0; load; gcyc = 0;
	check("gambatte run", state, 2); check("gambatte entry 0", index, 0);
	frame; check("vblank ignored in gambatte mode", index, 0);
	// LCD off from power-on: the end event at 70224, then the blank blits every 70224
	at(70224 - 16, "before the first end", 0);
	at(70224, "first end event", 1);
	at(140448, "blank blit", 2);
	at(210672, "blank blit 2", 3);
	// LCD on at 220000 with a blank picture pending: the end event at 280896, then
	// the first mode-1 edge at 285664, then every 70224 (the end events tie)
	cycles(220000 - gcyc); lcd_on <= 1;
	at(280896, "end event after LCD on", 4);
	at(285664, "first mode-1 blit", 5);
	at(355888, "mode-1 blit", 6);
	at(426112, "mode-1 blit 2", 7);
	// LCD off at 427000 with the picture drawn: the blit 1824 on arms (no frame),
	// the end event at 496336, the blank blit at 499048, then every 70224
	cycles(427000 - gcyc); lcd_on <= 0;
	at(428824, "arming blit ends no frame", 7);
	at(496336, "end event after LCD off", 8);
	at(499048, "blank blit after LCD off", 9); check("gambatte entry 9", p1, 10);
	at(569272, "blank blit period", 10);
	// LCD on at 570000 with a blank pending: the mode-1 edge at 635664 comes before
	// the end event (639496), which then does not fire
	cycles(570000 - gcyc); lcd_on <= 1;
	at(635664, "mode-1 blit before the end event", 11);
	at(640000, "end event dropped", 11);
	at(705888, "mode-1 tie", 12);
	// off at 706000 and on again at 706100, the picture not blank: the first
	// mode-1 edge (771764) is skipped; the end event at 776112, the edge at 841988
	cycles(706000 - gcyc); lcd_on <= 0;
	cycles(706100 - gcyc); lcd_on <= 1;
	at(771764, "first mode-1 edge skipped", 12);
	at(776112, "end event", 13);
	at(841988, "second mode-1 edge", 14);
	at(846336, "end event tie dropped", 14);
	at(912212, "mode-1 blit resumes", 15);
	reset <= 1; repeat (3) @(posedge clk); check("reset aborts gambatte run", state, 4); reset <= 0; repeat (3) @(posedge clk);
	mem[2] = 64'd1; lcd_on <= 0;

	// a frame edge that lands during a header poll is not lost
	arm(10, 8'd11); poll; load;
	@(negedge clk) dut.poll_cnt = dut.POLL_CLKS - 1; @(posedge clk); @(posedge clk); @(posedge clk);   // poll read in flight
	vblank <= 1; repeat (10) @(posedge clk); vblank <= 0; repeat (40) @(posedge clk);
	check("edge kept during poll", index, 1);

	if (errors == 0) $display("PASS"); else $display("%0d FAILURES", errors);
	$finish;
end

endmodule
