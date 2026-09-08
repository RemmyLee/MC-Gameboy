// mc_replay: play a recorded input log (a TAS movie) into the console from
// DDR3, one entry per frame, with the frame timing held by the core itself.
//
// Buffer at byte 0x3C100000 (64 bit word 0x1820000 inside the 0x30000000
// window), written by MiSTer Control:
//   w0  magic "MC-RPLAY"
//   w1  [31:0] frames            [63:32] generation (changes on every arm)
//   w2  [0] armed  [1] abort  [2] poll-indexed  [4:3] console mode the movie was
//       made for: 0 leave the menu, 1 DMG, 2 GBC, 3 SGB (sys_mode; the core boots
//       that mode at the arming reset, whatever the menu says)  [5] Gambatte
//       frames: the entry advances on libgambatte's frame ends, counted in CPU
//       cycles (below), not on vblank  (the rest reserved)
//   w3  [7:0] bytes per entry: must equal this core's ENTRY_BYTES, else the
//       core answers state 7 (layout mismatch) and stays idle
//   w8.. entries:
//       ENTRY_BYTES 4 (NES): 2 per word, frame i is bytes 4*(i&1) .. +3 of
//         word 8 + i/2: [7:0] pad 1  [15:8] pad 2  [23:16] command  [31:24] 0
//       ENTRY_BYTES 8 (Gameboy): 1 per word, frame i is word 8 + i:
//         [7:0] pad 1 [15:8] pad 2 [23:16] pad 3 [31:24] pad 4 [39:32] command
//         [63:40] 0
//       pad byte order is the core's own: NES serial order, bit 7 first,
//       R L D U Start Select B A (the FM2 "RLDUTSBA" column, NES.sv's
//       nes_joy_A); Gameboy the MiSTer joystick order (sgb.v:378-386).
//
// Sequence: the app writes the entries, then the header with a new
// generation and armed = 1, then reloads the ROM. This module polls the header
// while idle; on a new generation it prefetches the first entries and waits
// for the core's reset to release after a ROM download (the end of the ROM
// load: that is power-on). A reset release with no download before it (the
// FPGA load itself; an MGL launch gives one of those about two seconds before
// the ROM upload) is not the start and is ignored.
// From then on entry N is presented at the rising edge of vblank of frame N
// (docs/TAS-semantics.md: FCEUX sets the frame's input just before the frame's
// vblank), entry 0 from the reset release itself.
//
// Poll-indexed mode (header w2 bit 2): the index advances at vblank only when
// the game read the controller during the finished frame. The app then writes
// the entries the emulator actually delivered (its lag frames stripped), so a
// frame where the core lags differently from the emulator no longer shifts
// every later input. This is how console verification rigs stay in sync. At
// `frames` it stops and hands the pads back to the HPS. An entry with a
// command bit set stops the replay with state UNSUPPORTED: reset and power
// inside a movie are not implemented in this version.
//
// Gambatte frames (header w2 bit 5): a BizHawk Gambatte movie with "VBlank
// Driven Frames" (Gambatte.IEmulator.cs FrameAdvance) hands the game one entry
// per gambatte_runfor() call, and libgambatte (gambatte-core 0838651, the
// BizHawk 2.10 submodule; e35e24d in 2.9.1 is the same here) ends that call at
// the earlier of two events, both in 4 MHz CPU cycles (video/lcddef.h: 456 per
// line, 70224 per frame):
//   - the end event, 70224 cycles after the call started (cpu.cpp:519
//     setEndtime, memory.cpp:166-172);
//   - the blit event, when it draws: with the LCD on or a blank picture
//     pending (`lcden | blanklcd_`, memory.cpp:238-258). With the LCD on the
//     blit sits on the mode-1 (vblank) interrupt time and moves one frame on
//     after each draw (:167-169 bumps a due blit; video.cpp m1irq +70224).
//     Turning the LCD off puts the blit 4 lines after the write (:1150-1151);
//     that one draws nothing unless a blank was pending, marks the picture
//     blank and moves a frame on, so with the LCD off a blank frame ends every
//     70224 cycles. Turning it on puts the blit at the next mode-1 time, or at
//     the one after it when the last picture drawn was not blank (:1145-1147).
//   At power-on the blit is due at once and moved a frame on (:157-160, then
//   :167), the picture not blank, so the first frame ends 70224 cycles in.
// The core keeps the same model: `cyc` is the CPU cycle enable, `lcd_on`
// LCDC bit 7, `m1_irq` the PPU's vblank interrupt line (its rising edge is
// the mode-1 time). Not modelled: GBC double speed (the counts would halve)
// and libgambatte's instruction-granular overshoot of an event (its next end
// event starts from the overshot cycle; here from the event itself).
//
// State (also written into the telemetry slot): 0 idle, 1 armed, 2 running,
// 3 done, 4 aborted, 5 unsupported command, 6 bad header, 7 layout mismatch.
//
// Copyright (c) 2026 Remmy Lee. GPLv3, like the core it lives in.

module mc_replay
#(
	parameter        ENTRY_BYTES = 4,          // 4 (two pads) or 8 (four pads)
	parameter [31:0] CLK_HZ      = 32'd21477272, // clk, for the 60 Hz header poll
	parameter [24:0] HDR_W       = 25'h1820000
)
(
	input             clk,
	input             reset,       // the core's reset (high during a ROM load)
	input             downloading, // a game upload is in progress (NES.sv `downloading` for a nes/fds/nsf type; boot0.rom is not a game)
	input             vblank,
	input             joy_read,    // one pulse per controller read (the lag rule's poll)
	// Gambatte frames (header w2 bit 5): the CPU cycle enable, LCDC bit 7 and
	// the PPU's vblank interrupt line. A core without them ties them to 0.
	input             cyc,
	input             lcd_on,
	input             m1_irq,

	// DDR read channel (64 bit word address inside the 0x30000000 window)
	output reg [24:0] ddr_addr,
	output reg        ddr_req,
	input      [63:0] ddr_dout,
	input             ddr_ready,   // one clock, ddr_dout valid

	output reg        active = 0,  // pads come from the buffer
	output reg  [7:0] p1 = 0,
	output reg  [7:0] p2 = 0,
	output reg  [7:0] p3 = 0,      // zero with ENTRY_BYTES 4
	output reg  [7:0] p4 = 0,
	output reg [31:0] index = 0,   // entry being presented
	output reg  [7:0] state = 0,
	output reg  [7:0] gen = 0,     // generation of the last accepted arm; 0 = none yet
	output      [7:0] entry_bytes, // ENTRY_BYTES, for the telemetry header
	output reg  [1:0] sys_mode = 0 // header w2 [4:3] of the last accepted arm
);

localparam [63:0] MAGIC = 64'h59414C50_522D434D;   // "MC-RPLAY"

localparam [7:0] S_IDLE = 0, S_ARMED = 1, S_RUN = 2, S_DONE = 3, S_ABORT = 4, S_UNSUP = 5, S_BADHDR = 6, S_LAYOUT = 7;

// entries per 64 bit word, and the shift that turns an entry index into a word offset
localparam PER_WORD = 8 / ENTRY_BYTES;
localparam SHIFT    = (PER_WORD == 2) ? 1 : 0;

initial if (ENTRY_BYTES != 4 && ENTRY_BYTES != 8) $error("mc_replay: ENTRY_BYTES must be 4 or 8");

assign entry_bytes = 8'(ENTRY_BYTES);

// poll the header about 60 times a second while not running
localparam [31:0] POLL_CLKS = CLK_HZ / 32'd60;
localparam        POLL_W    = $clog2(POLL_CLKS + 1);

reg [POLL_W-1:0] poll_cnt = 0;
reg        vblank_d = 0;
reg        cyc_mode = 0;  // header w2 bit 5: Gambatte frames
reg        gb_frame = 0;  // one clock: a Gambatte frame ended
wire       frame_start = cyc_mode ? gb_frame : (vblank & ~vblank_d);
reg        reset_d = 1;
wire       reset_release = reset_d & ~reset;

reg [31:0] frames;
reg [63:0] cur, nxt;      // the word holding the current entry, and the next word
reg [63:0] hdr0, hdr1, hdr2, hdr3;

// ent: one entry normalised to {command, pad 4, pad 3, pad 2, pad 1}
function automatic [39:0] ent(input [63:0] w, input hi);
	if (PER_WORD == 2) ent = hi ? {w[55:48], 16'd0, w[47:32]} : {w[23:16], 16'd0, w[15:0]};
	else               ent = w[39:0];
endfunction

// one read at a time
typedef enum logic [3:0] { IDLE, RD0, RD1, RD2, RD3, EVAL, PF0, PF1, WAIT_RESET, RUN, RD_FLAGS, RD_NEXT } st_t;
st_t st = IDLE;
reg        pending = 0;   // a read was issued, waiting for ready
// an edge that arrives while a header or entry read is in flight is kept
// until the main state can act on it (a read takes about a microsecond)
reg        frame_pend = 0, release_pend = 0;
wire       tick = frame_start | frame_pend;
wire       release_now = reset_release | release_pend;
reg        dl_seen = 0;   // a download happened since arming: the next release is power-on
reg        poll_mode = 0; // header w2 bit 2: advance per polled frame, not per frame
reg        polled = 0;    // the game read the controller since the last vblank

task automatic read_word(input [24:0] a, input st_t next);
	ddr_addr <= a;
	ddr_req  <= 1;
	pending  <= 1;
	st       <= next;
endtask

// has_cmd: the entry carries a command (reset or power), which stops the run
function automatic has_cmd(input [63:0] w, input hi);
	has_cmd = (PER_WORD == 2) ? (hi ? w[55:48] != 0 : w[23:16] != 0) : w[39:32] != 0;
endfunction

// present one entry on the pad outputs
task automatic present(input [39:0] e);
	p1 <= e[7:0];
	p2 <= e[15:8];
	p3 <= e[23:16];
	p4 <= e[31:24];
endtask

task automatic stop_unsupported;
	active <= 0; state <= S_UNSUP; st <= IDLE;
endtask

// ---- Gambatte frames (the model in the header comment) ---------------------
localparam [16:0] FRAME_CYC = 17'd70224;   // lcd_cycles_per_frame
localparam [16:0] OFF_BLIT  = 17'd1824;    // 4 * lcd_cycles_per_line
wire       gb_run = (state == S_RUN) & cyc_mode;   // the run, whatever the read state (a header poll or a prefetch is not a stop)
reg [16:0] to_end = 0;      // cycles to the end event
reg [16:0] to_blit = 0;     // cycles to the blit while it is counted (LCD off)
reg        blit_cnt = 0;    // the blit is counted, not on the mode-1 edge
reg        blank = 0;       // libgambatte blanklcd_: the last picture drawn was blank
reg        m1_wait = 0;     // LCD on: the blit is on a mode-1 edge
reg        m1_skip = 0;     // and not the first one
reg        lcd_on_d = 0, m1_d = 0;

always @(posedge clk) begin
	gb_frame <= 0;
	if (!gb_run) begin
		// power-on: the blit due and moved a frame on, the picture not blank
		to_end   <= FRAME_CYC;
		to_blit  <= FRAME_CYC;
		blit_cnt <= ~lcd_on;
		m1_wait  <= lcd_on;
		m1_skip  <= 0;
		blank    <= 0;
		lcd_on_d <= lcd_on;
		m1_d     <= m1_irq;
	end
	else if (cyc) begin
		lcd_on_d <= lcd_on;
		m1_d     <= m1_irq;
		// the end event: a frame is at most FRAME_CYC cycles
		if (to_end == 17'd1) begin gb_frame <= 1; to_end <= FRAME_CYC; end
		else to_end <= to_end - 17'd1;
		if (lcd_on_d & ~lcd_on) begin          // LCD off: the blit 4 lines on
			to_blit  <= OFF_BLIT;
			blit_cnt <= 1;
			m1_wait  <= 0;
		end
		else if (~lcd_on_d & lcd_on) begin     // LCD on: the next mode-1 edge, or the one after
			blit_cnt <= 0;
			m1_wait  <= 1;
			m1_skip  <= ~blank;
		end
		else if (blit_cnt) begin
			if (to_blit == 17'd1) begin
				if (blank) begin gb_frame <= 1; to_end <= FRAME_CYC; end   // a blank picture drawn
				blank   <= 1;
				to_blit <= FRAME_CYC;
			end
			else to_blit <= to_blit - 17'd1;
		end
		else if (m1_wait & m1_irq & ~m1_d) begin
			if (m1_skip) m1_skip <= 0;
			else begin gb_frame <= 1; to_end <= FRAME_CYC; blank <= 0; end   // the picture drawn
		end
	end
end

always @(posedge clk) begin
	ddr_req  <= 0;
	vblank_d <= vblank;
	reset_d  <= reset;
	if (ddr_ready) pending <= 0;
	poll_cnt <= (poll_cnt == POLL_CLKS[POLL_W-1:0]) ? {POLL_W{1'b0}} : poll_cnt + 1'd1;
	if (frame_start && st != RUN) frame_pend <= 1;
	if (reset_release && st != WAIT_RESET) release_pend <= 1;
	if (downloading) dl_seen <= 1;   // sticky; EVAL's assignment below wins on the arm clock
	if (joy_read) polled <= 1;

	case (st)

	// ---- idle: poll the header ------------------------------------------------
	IDLE: begin
		active <= 0;
		frame_pend   <= 0;
		release_pend <= 0;
		if (poll_cnt == 0) read_word(HDR_W + 25'd0, RD0);
	end
	RD0: if (ddr_ready) begin hdr0 <= ddr_dout; read_word(HDR_W + 25'd1, RD1); end
	RD1: if (ddr_ready) begin hdr1 <= ddr_dout; read_word(HDR_W + 25'd2, RD2); end
	RD2: if (ddr_ready) begin hdr2 <= ddr_dout; read_word(HDR_W + 25'd3, RD3); end
	RD3: if (ddr_ready) begin hdr3 <= ddr_dout; st <= EVAL; end
	EVAL: begin
		st <= IDLE;
		if (hdr0 == MAGIC && hdr2[0] && hdr1[39:32] != gen) begin
			gen    <= hdr1[39:32];
			frames <= hdr1[31:0];
			index  <= 0;
			if (hdr1[31:0] == 0) state <= S_BADHDR;
			else if (hdr3[7:0] != 8'(ENTRY_BYTES)) state <= S_LAYOUT;
			else begin
				state     <= S_ARMED;
				dl_seen   <= downloading;
				poll_mode <= hdr2[2];
				sys_mode  <= hdr2[4:3];
				cyc_mode  <= hdr2[5];
				read_word(HDR_W + 25'd8, PF0);
			end
		end
	end
	PF0: if (ddr_ready) begin cur <= ddr_dout; read_word(HDR_W + 25'd9, PF1); end
	PF1: if (ddr_ready) begin nxt <= ddr_dout; st <= WAIT_RESET; end

	// ---- armed: wait for the ROM load's reset to release (power-on) ---------------
	WAIT_RESET: begin
		release_pend <= 0;
		frame_pend   <= 0;
		if (poll_cnt == 0 && !pending && !(release_now && dl_seen)) read_word(HDR_W + 25'd2, RD_FLAGS);   // abort?
		if (release_now && dl_seen) begin
			active <= 1;
			state  <= S_RUN;
			index  <= 0;
			polled <= 0;
			st     <= RUN;
			present(ent(cur, 1'b0));
			if (has_cmd(cur, 1'b0)) stop_unsupported;
		end
	end
	RD_FLAGS: if (ddr_ready) begin
		hdr2 <= ddr_dout;
		if (ddr_dout[1]) begin state <= S_ABORT; active <= 0; st <= IDLE; end
		else st <= st_t'((state == S_RUN) ? RUN : WAIT_RESET);
	end

	// ---- running: one entry per vblank (or per Gambatte frame) --------------------
	RUN: begin
		frame_pend <= 0;
		if (reset) begin                      // a load or reset ends the run
			active <= 0; state <= S_ABORT; st <= IDLE;
		end
		else if (tick) begin
			polled <= 0;
			if (poll_mode && !polled) begin
				// the game never read this frame's entry; hold the stream
			end
			else if (index + 32'd1 >= frames) begin
				active <= 0; state <= S_DONE; st <= IDLE;
			end
			else begin
				index <= index + 32'd1;
				if (PER_WORD == 1 || index[0]) begin   // the next entry is in the next word
					cur <= nxt;
					present(ent(nxt, 1'b0));
					if (has_cmd(nxt, 1'b0)) stop_unsupported;
					// prefetch the word after: entry index + 1 + PER_WORD
					else read_word(HDR_W + 25'd8 + ((index[24:0] + 25'd1 + 25'(PER_WORD)) >> SHIFT), RD_NEXT);
				end
				else begin
					present(ent(cur, 1'b1));
					if (has_cmd(cur, 1'b1)) stop_unsupported;
				end
			end
		end
		else if (poll_cnt == 0 && !pending) read_word(HDR_W + 25'd2, RD_FLAGS);
	end
	RD_NEXT: if (ddr_ready) begin nxt <= ddr_dout; st <= RUN; end

	default: st <= IDLE;
	endcase
end

endmodule
