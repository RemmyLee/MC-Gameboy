//============================================================================
//  Gameboy
//  Copyright (c) 2015 Till Harbaum <till@harbaum.org>  
//
//  Port to MiSTer
//  Copyright (C) 2017,2018 Sorgelig
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

// Bootrom checksums
`define MISTER_CGB0_CHECKSUM 18'h2CE10
`define ORIGINAL_CGB_CHECKSUM 18'h2F3EA

module emu
(
	`include "sys/emu_ports.vh"
);

assign ADC_BUS  = 'Z;
assign VGA_F1 = 0;

assign {UART_RTS, UART_TXD, UART_DTR} = 0;

assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

assign LED_USER  = ioctl_download | sav_pending;
assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS   = 0;
assign HDMI_FREEZE = 0;
assign VGA_SCALER= 0;
assign VGA_DISABLE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_MIX = status[8:7];

// Status Bit Map: (0..31 => "O", 32..63 => "o")
// 0         1         2         3          4         5         6
// 01234567890123456789012345678901 23456789012345678901234567890123
// 0123456789ABCDEFGHIJKLMNOPQRSTUV 0123456789ABCDEFGHIJKLMNOPQRSTUV
// XXXXXXXXXXX XXXXXXXXXXXXXXXXXXXX XXXXXXXXXXXXXXXXXXXX
//                                  bit 51: MiSTer Control telemetry

`include "build_id.v" 
localparam CONF_STR = {
	"GAMEBOY;SS3E000000:40000;",
	"FS1,GBCGB BIN,Load ROM;",
	"OEF,System,Auto,Gameboy,Gameboy Color,MegaDuck;",
	"D7o79,Mapper,Auto,WisdomTree,Mani161,MBC1,MBC3;",
	"d7o[50:48],Mapper,Auto,MD0,MD1,MD2;",
	"-;",
	"ONO,Super Game Boy,Off,Palette,On;",
	"d5FC2,SGB,Load SGB border;",
	"-;",
	"C,Cheats;",
	"h0OH,Cheats enabled,Yes,No;",
	"-;",
	"h2R9,Load Backup RAM;",
	"h2RA,Save Backup RAM;",
	"OD,Autosave,Off,On;",
	"-;",
	"OV,Savestates to SDCard,On,Off;",
	"o01,Savestate Slot,1,2,3,4;",
	"h3RS,Save state (Alt-F1);",
	"h3RT,Restore state (F1);",
	"-;",

	"P1,Audio & Video;",
	"P1-;",
	"P1O[44],Extra sprites,No,Yes;",
	"P1OC,Inverted color,No,Yes;",
	"P1o4,Screen Shadow,No,Yes;",
	"P1O12,Custom Palette,Off,Auto,On;",
	"h1P1FC3,GBP,Load Palette;",
	"P1OG,Frame blend,Off,On;",
	"d4P1OU,GBC Colors,Corrected,Raw;",
	"H9P1FC7,LUT,Load GBC Color LUT;",
	"P1O5,Stabilize video(buffer),Off,On;",
	"P1-;",
	"P1O34,Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"P1OLM,Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
	"P1OIK,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"P1o2,Analog width,Narrow,Wide;",
	"P1-;",
	"P1O78,Stereo mix,none,25%,50%,100%;",
	"P1O[43],Audio mode,Accurate,No Pops;",

    "P2,Bootroms;",
	"P2-;",
	"P2FC4,BIN,Load GBC Boot;",
	"P2FC5,BIN,Load DMG Boot;",
	"P2FC6,BIN,Load SGB Boot;",
	"P2-;",
	"d6P2O[37],GBC/GBA mode,GBC,GBA;",
    "d8P2O[42],Fast boot,Off,On;",

	"P3,Misc.;",
	"P3-;",
	"P3O6,Link Port,Disabled,Enabled;",
	"P3O[45],WorkBoy Keyboard,Off,On;",
	"P3O[46],iG Keyboard/Mouse,Off,On;",
	"d7P3O[47],MegaDuck Laptop,Off,On;",
	"P3o6,Rumble,On,Off;",
	"P3-;",
	"P3OP,FastForward Sound,On,Off;",
	"P3OQ,Pause when OSD is open,Off,On;",
	"P3OR,Rewind Capture,Off,On;",
	"P3-;",
	"P3o3,Super Game Boy + GBC,Off,On;",

	"P4,MiSTer Control;",
	"P4-;",
	"P4O[51],Telemetry,On,Off;",

	// ioctl index 5 = dmg_boot_download: a movie launch loads the boot ROM the emulator ran
	// before the cartridge (MiSTer Control MGL). A root-page, visible entry: the firmware
	// matches an MGL <file index="5"> only against root-page F entries (Main_MiSTer
	// menu.cpp:1976 inpage, :2034 the match, inside !h && inpage) and will not select a
	// disabled one (:2408 if (p && !d)); an unmatched item loads through entry 0, the
	// cartridge slot (mra_loader.cpp:1436 memset, menu.cpp:2320). Build g had it on P4 and
	// the boot ROM went in as a 256-byte cartridge (index 1.2).
	"FC5,BIN,Load DMG boot ROM;",
	"-;",
	"R0,Reset;",
	"J1,A,B,Select,Start,FastForward,Savestates,Rewind;",
	"I,",
	"Slot=DPAD|Save/Load=Pause+DPAD,",
	"Active Slot 1,",
	"Active Slot 2,",
	"Active Slot 3,",
	"Active Slot 4,",
	"Save to state 1,",
	"Restore state 1,",
	"Save to state 2,",
	"Restore state 2,",
	"Save to state 3,",
	"Restore state 3,",
	"Save to state 4,",
	"Restore state 4,",
	"Rewinding...;",
	"V,v",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

wire clk_sys, clk_ram;
wire pll_locked;

assign CLK_VIDEO = clk_ram;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_ram),
	.outclk_1(clk_sys),
	.locked(pll_locked)
);

///////////////////////////////////////////////////

wire [63:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;
wire        direct_video;
wire [21:0] gamma_bus;

wire        ioctl_download;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire [15:0] ioctl_dout;
wire        ioctl_wait;

wire [15:0] joystick_0, joy0_unmod, joystick_1, joystick_2, joystick_3;
wire [15:0] joystick_analog_0;
wire [10:0] ps2_key;
wire [24:0] ps2_mouse;

wire [7:0]  filetype;

reg  [31:0] sd_lba;
reg         sd_rd = 0;
reg         sd_wr = 0;
wire        sd_ack;
wire  [7:0] sd_buff_addr;
wire [15:0] sd_buff_dout;
wire [15:0] sd_buff_din;
wire        sd_buff_wr;
wire        img_mounted;
wire        img_readonly;
wire [63:0] img_size;
wire [15:0] joy0_rumble;

wire [64:0] RTC_bcd;
wire [32:0] RTC_time;

wire        sys_auto     = (status[15:14] == 0);
wire        sys_gbc      = (status[15:14] == 2);
wire        sys_megaduck = (status[15:14] == 3);

wire        gbc_raw_colors = status[30];

hps_io #(.CONF_STR(CONF_STR), .WIDE(1)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait | save_wait),
	.ioctl_index(filetype),
	
	.sd_lba('{sd_lba}),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din('{sd_buff_din}),
	.sd_buff_wr(sd_buff_wr),
	.img_mounted(img_mounted),
	.img_readonly(img_readonly),
	.img_size(img_size),

	.buttons(buttons),
	.status(status),
	.status_menumask({6'h0,
        gbc_raw_colors, fastboot_available,
        sys_megaduck, boot_gba_available, sgb_border_en, isGBC,
        cart_ready, sav_supported, |tint, gg_available}),
	.status_in({status[63:34],ss_slot,status[31:0]}),
	.status_set(statusUpdate),
	.direct_video(direct_video),
	.gamma_bus(gamma_bus),
	.forced_scandoubler(forced_scandoubler),

	.joystick_0(joy0_unmod),
	.joystick_1(joystick_1),
	.joystick_2(joystick_2),
	.joystick_3(joystick_3),
	.joystick_l_analog_0(joystick_analog_0),

	.joystick_0_rumble(joy0_rumble),
	
	.ps2_key(ps2_key),
	.ps2_mouse(ps2_mouse),

	.info_req(ss_info_req),
	.info(ss_info),
	
	.RTC(RTC_bcd),
	.TIMESTAMP(RTC_time)
);

assign joystick_0 = joy0_unmod[9] ? 16'b0 : joy0_unmod;

// MiSTer Control (rtl/mc): declared here, driven in the telemetry section at
// the end of the file
wire  [9:0] mc_bus_adr;
wire [63:0] mc_bus_dout;
wire        mc_bus_free;
wire [24:0] mc_ddr_addr;
wire [63:0] mc_ddr_din;
wire        mc_ddr_req, mc_ddr_ready;
wire [31:0] mc_frame;
wire        mc_wr, mc_joy_read, mc_strobe, mc_vblank_irq;
wire        mc_stat_read, mc_ly_read, mc_dma_write, mc_lcdc_write;
wire        mc_fetch;
wire [15:0] mc_pc;
wire        mc_video_irq, mc_rd_we, mc_irq_ack;
wire  [1:0] mc_rd_kind;
wire  [7:0] mc_rd_val, mc_vcnt;
wire  [8:0] mc_hcyc;
wire [63:0] mc_bus_dout_gb;
wire [15:0] mc_wr_addr;
wire  [7:0] mc_wr_data;

// replay
wire        mc_rp_active;
wire  [7:0] mc_rp_p1, mc_rp_p2, mc_rp_p3, mc_rp_p4, mc_rp_state, mc_rp_gen, mc_rp_entry_bytes;
wire        mc_rp_armed = (mc_rp_state == 8'd1) || (mc_rp_state == 8'd2);
wire  [1:0] mc_rp_sys;   // replay header w2 [4:3]: 0 menu, 1 DMG, 2 GBC, 3 SGB
// The console mode the running movie asked for, latched at the arming reset
// and held until the next reset, so the SGB and GBC paths do not flip when
// the movie ends. 0 = the menu decides (no movie).
reg   [1:0] mc_sys_ovr = 0;
wire [31:0] mc_rp_index;
wire [24:0] mc_rd_addr;
wire        mc_rd_req, mc_rd_ready;
wire [63:0] mc_rd_dout;

// the pads the SGB module reads (MiSTer joystick order: bit 0 Right, 1 Left,
// 2 Down, 3 Up, 4 A, 5 B, 6 Select, 7 Start; rtl/sgb.v joy_dir/joy_buttons)
wire  [7:0] mc_joy0 = mc_rp_active ? mc_rp_p1 : joystick_0[7:0];
wire  [7:0] mc_joy1 = mc_rp_active ? mc_rp_p2 : joystick_1[7:0];
wire  [7:0] mc_joy2 = mc_rp_active ? mc_rp_p3 : joystick_2[7:0];
wire  [7:0] mc_joy3 = mc_rp_active ? mc_rp_p4 : joystick_3[7:0];

///////////////////////////////////////////////////

wire [14:0] cart_addr;
wire [22:0] mbc_addr;
wire cart_a15;
wire cart_rd;
wire cart_wr;
wire cart_oe;
wire [7:0] cart_di, cart_do;
wire nCS; // WRAM or Cart RAM CS
wire sdram_rd;

wire cart_download = ioctl_download && (filetype[5:0] == 6'h01 || filetype == 8'h80);
wire md_download = ioctl_download && (filetype == 8'h81);
wire palette_download = ioctl_download && (filetype == 3 /*|| !filetype*/);
wire sgb_border_download = ioctl_download && (filetype == 2);
wire cgb_boot_download = ioctl_download && (filetype == 4);
wire dmg_boot_download = ioctl_download && (filetype == 5);
wire sgb_boot_download = ioctl_download && (filetype == 6);
wire cgb_lut_download = ioctl_download && (filetype == 7);
wire boot_download = cgb_boot_download | dmg_boot_download | sgb_boot_download;

///////////////////////////// Bootrom added features ///////////////////////////

// Fastboot is available for MiSTer-built bootroms (except SGB)
wire fastboot_available = !((isGBC && using_custom_cgb_bootrom &&  checksum_cgb != `MISTER_CGB0_CHECKSUM) || (!isGBC && using_custom_dmg_bootrom));
// GBA mode is available for MiSTer-built CGB bootroms and the original CGB bootrom.
// We verify that a loaded bootrom enables GBA mode by calculating a simple checksum.
wire boot_gba_available = (!using_custom_cgb_bootrom || using_real_cgb_bios || checksum_cgb == `MISTER_CGB0_CHECKSUM);
wire using_real_cgb_bios = (checksum_cgb == `ORIGINAL_CGB_CHECKSUM);

reg using_custom_dmg_bootrom = 0;
reg using_custom_cgb_bootrom = 0;
always @(posedge clk_sys) begin
	if (cgb_boot_download)
		using_custom_cgb_bootrom <= 1;
	if (dmg_boot_download)
		using_custom_dmg_bootrom <= 1;
end

reg boot_download_r;
always @(posedge clk_sys)
    boot_download_r <= boot_download;

// Calculate checksum for incoming cgb bootrom downloads
reg [17:0] checksum_cgb;
always @(posedge clk_sys) begin
    // Reset checksum on new boot download
    if (cgb_boot_download && !boot_download_r)
        checksum_cgb <= 0;
    else if (cgb_boot_download && ioctl_wr)
        checksum_cgb <= checksum_cgb + ioctl_dout[15:8] + ioctl_dout[7:0];
end

////////////////////////////////////////////////////////////////////////////////

localparam CARTRAM_BANK = 2'b01;

//wire  [1:0] sdram_ds = cart_download ? 2'b11 : {mbc_addr[0], ~mbc_addr[0]};
wire [15:0] sdram_do;
wire [15:0] sdram_di = cart_download ? ioctl_dout :
						savestate_ovr ? Savestate_CRAMWriteData :
						cart_di;

wire [24:0] sdram_addr = cart_download ? ioctl_addr[24:0] :
						(savestate_ovr | is_cram_addr) ? { CARTRAM_BANK, 6'd0, cram_addr } :
						{2'b00, mbc_addr[22:0]};

wire sdram_oe = ~cart_download & (savestate_ovr ? Savestate_CRAMRdEn : sdram_rd);
wire sdram_we = (cart_download & dn_write) | cram_wr;
wire sdram_pause_refresh;
wire sdram_busy;

wire [15:0] save_dout;

assign Savestate_CRAMReadData = bram_save ? Savestate_CRAM_Q : sdram_do;

sdram sdram
(
	.SDRAM_DQ(SDRAM_DQ),
	.SDRAM_A(SDRAM_A),
	.SDRAM_DQML(SDRAM_DQML),
	.SDRAM_DQMH(SDRAM_DQMH),
	.SDRAM_BA(SDRAM_BA),
	.SDRAM_nCS(SDRAM_nCS),
	.SDRAM_nWE(SDRAM_nWE),
	.SDRAM_nRAS(SDRAM_nRAS),
	.SDRAM_nCAS(SDRAM_nCAS),
	.SDRAM_CLK(SDRAM_CLK),
	.SDRAM_CKE(SDRAM_CKE),

	// system interface
	.clk        ( clk_ram           ),
	.init       (0), //~clock_locked),

	// ROM + Cart RAM
	.ch0_addr   ( sdram_addr  ),
	.ch0_wr     ( sdram_we ),
	.ch0_din    ( sdram_di  ),
	.ch0_rd     ( sdram_oe ),
	.ch0_dout   ( sdram_do   ),
	.ch0_word   ( cart_download | savestate_ovr),
	.ch0_busy   ( sdram_busy),

	// HPS Cart RAM Save/Load
	.ch1_addr   ( { CARTRAM_BANK, 6'd0, save_addr, 1'b0 } ),
	.ch1_wr     ( save_wr ),
	.ch1_din    ( bk_data  ),
	.ch1_rd     ( save_rd ),
	.ch1_dout   ( save_dout ),
	.ch1_word   ( 1'b1 ),
	.ch1_busy   ( save_busy ),

	.ch2_addr   ( 0 ),
	.ch2_wr     ( 0 ),
	.ch2_din    ( 0 ),
	.ch2_rd     ( 0 ),
	.ch2_dout   (   ),
	.ch2_busy   (   ),

	.refresh    ( sdram_pause_refresh )
);

wire dn_write;
wire cart_ready;
wire cram_rd, cram_wr, cram_bram_wr, is_cram_addr;
wire [16:0] cram_addr;
wire [15:0] Savestate_CRAM_Q;

wire [7:0] ram_mask_file, cart_ram_size;
wire isGBC_game, isSGB_game;
wire cart_has_save, bram_save;
wire [31:0] RTC_timestampOut;
wire [47:0] RTC_savedtimeOut;
wire RTC_inuse;
wire rumbling;
wire [2:0] mapper_sel = status[41:39];
wire [2:0] duck_mapper_sel = status[50:48];
// The existing MegaDuck mapper path already handles MD1/MD2. Only MD0 needs
// an explicit cart-side mode select.
wire duck_md0_mode = megaduck && (duck_mapper_sel == 3'd1);

assign joy0_rumble = {8'd0, ((rumbling & ~status[38]) ? 8'd128 : 8'd0)};

reg ce_32k; // 32768Hz clock for RTC
reg [9:0] ce_32k_div;
always @(posedge clk_sys) begin
	ce_32k_div <= ce_32k_div + 1'b1;
	ce_32k <= !ce_32k_div;
end

cart_top cart (
	.reset	     ( reset      ),

	.clk_sys     ( clk_sys    ),
	.ce_cpu      ( ce_cpu     ),
	.ce_cpu2x    ( ce_cpu2x   ),
	.speed       ( speed      ),
	.megaduck    ( megaduck   ),
	.duck_md0_mode ( duck_md0_mode ),
	.mapper_sel  ( mapper_sel ),

	.cart_addr   ( cart_addr  ),
	.cart_a15    ( cart_a15   ),
	.cart_rd     ( cart_rd    ),
	.cart_wr     ( cart_wr    ),
	.cart_do     ( cart_do    ),
	.cart_di     ( cart_di    ),
	.cart_oe     ( cart_oe    ),

	.nCS         ( nCS        ),

	.mbc_addr    ( mbc_addr   ),

	.dn_write    ( dn_write    ),
	.cart_ready  ( cart_ready  ),

	.is_cram_addr( is_cram_addr),
	.cram_rd     ( cram_rd     ),
	.cram_wr     ( cram_wr     ),
	.cram_bram_wr( cram_bram_wr ),
	.cram_addr   ( cram_addr   ),

	.cart_download ( cart_download ),

	.ram_mask_file ( ram_mask_file ),
	.ram_size      ( cart_ram_size ),
	.has_save      ( cart_has_save ),
	.bram_save     ( bram_save   ),

	.isGBC_game    ( isGBC_game    ),
	.isSGB_game    ( isSGB_game    ),

	.ioctl_download ( ioctl_download ),
	.ioctl_wr       ( ioctl_wr       ),
	.ioctl_addr     ( ioctl_addr     ),
	.ioctl_dout     ( ioctl_dout     ),
	.ioctl_wait     ( ioctl_wait     ),

	.bk_wr          ( bk_wr          ),
	.bk_rtc_wr      ( bk_rtc_wr      ),
	.bk_addr        ( bk_addr        ),
	.bk_data        ( bk_data        ),
	.bk_q           ( bk_q           ),
	.img_size       ( img_size       ),

	.rom_di         ( sdram_do[7:0]  ),

	.joystick_analog_0 ( joystick_analog_0 ),

	.ce_32k           ( ce_32k           ),
	.RTC_time         ( RTC_time         ),
	.RTC_timestampOut ( RTC_timestampOut ),
	.RTC_savedtimeOut ( RTC_savedtimeOut ),
	.RTC_inuse        ( RTC_inuse        ),

	.SaveStateExt_Din ( SaveStateBus_Din  ),
	.SaveStateExt_Adr ( SaveStateBus_Adr  ),
	.SaveStateExt_wren( SaveStateBus_wren ),
	.SaveStateExt_rst ( SaveStateBus_rst  ),
	.SaveStateExt_Dout( SaveStateBus_Dout ),
	.savestate_load   ( savestate_load    ),
	.savestate_ovr    ( savestate_ovr     ),

	.Savestate_CRAMAddr     ( Savestate_CRAMAddr      ),
	.Savestate_CRAMRWrEn    ( Savestate_CRAMRWrEn     ),
	.Savestate_CRAMWriteData( Savestate_CRAMWriteData ),
	.Savestate_CRAM_Q       ( Savestate_CRAM_Q        ),
	
	.rumbling (rumbling)
);

reg [127:0] palette = 128'h828214517356305A5F1A3B4900000000;

always @(posedge clk_sys) begin
	if (palette_download & ioctl_wr) begin
			palette[127:0] <= {palette[111:0], ioctl_dout[7:0], ioctl_dout[15:8]};
	end
end

wire lcd_clkena;
wire [14:0] lcd_data;
wire [1:0] lcd_mode;
wire [1:0] lcd_data_gb;
wire lcd_on;
wire lcd_vsync;

wire DMA_on;

assign AUDIO_S = 1;

wire reset = (RESET | status[0] | buttons[1] | cart_download | boot_download | bk_loading);
wire speed;
reg megaduck = 0;

reg isGBC = 0;
always @(posedge clk_sys) if(reset) begin
	if (cart_download)
		megaduck <= sys_megaduck;
	if (md_download)
		megaduck <= sys_auto || sys_megaduck;

	mc_sys_ovr <= mc_rp_armed ? mc_rp_sys : 2'd0;
	if (mc_rp_armed && mc_rp_sys != 2'd0) isGBC <= (mc_rp_sys == 2'd2);   // the movie's console, not the menu's
	else if(~sys_auto) isGBC <= sys_gbc;
	else if(cart_download) begin
		if (!filetype[5:0]) isGBC <= isGBC_game;
		else isGBC <= !filetype[7:6];
	end
end

wire [15:0] GB_AUDIO_L;
wire [15:0] GB_AUDIO_R;

// the gameboy itself
gb gb (
	.reset	    ( reset      ),
	
	.clk_sys     ( clk_sys    ),
	.ce          ( ce_cpu     ),   // the whole gameboy runs on 4mhnz
	.ce_n        ( ce_cpu_n   ),   // 4MHz falling edge clock enable
	.ce_2x       ( ce_cpu2x   ),   // ~8MHz in dualspeed mode (GBC)
	
	.isGBC       ( isGBC      ),
    .real_cgb_boot ( using_real_cgb_bios ),  
	.isSGB       ( sgb_sel & ~isGBC ),
	.megaduck    ( megaduck   ),
	.extra_spr_en( status[44] ),

	.joy_p54     ( joy_p54     ),
	.joy_din     ( joy_do_sgb  ),

	// MiSTer Control telemetry taps (rtl/mc, wired below)
	.mc_wram_wr    ( mc_wr        ),
	.mc_wram_addr  ( mc_wr_addr   ),
	.mc_wram_din   ( mc_wr_data   ),
	.mc_joy_read   ( mc_joy_read  ),
	.mc_joy_strobe ( mc_strobe    ),
	.mc_stat_read  ( mc_stat_read ),
	.mc_ly_read    ( mc_ly_read   ),
	.mc_dma_write  ( mc_dma_write ),
	.mc_lcdc_write ( mc_lcdc_write),
	.mc_fetch      ( mc_fetch     ),
	.mc_pc         ( mc_pc        ),
	.mc_vblank_irq ( mc_vblank_irq ),
	.mc_video_irq  ( mc_video_irq ),
	.mc_rd_we      ( mc_rd_we     ),
	.mc_rd_kind    ( mc_rd_kind   ),
	.mc_rd_val     ( mc_rd_val    ),
	.mc_irq_ack    ( mc_irq_ack   ),
	.mc_vcnt       ( mc_vcnt      ),
	.mc_hcyc       ( mc_hcyc      ),
	.mc_bus_adr    ( mc_bus_adr   ),
	.mc_bus_dout   ( mc_bus_dout_gb ),
	.mc_bus_free   ( mc_bus_free  ),

	// interface to the "external" game cartridge
	.ext_bus_addr( cart_addr  ),
	.ext_bus_a15 ( cart_a15   ),
	.cart_rd     ( cart_rd    ),
	.cart_wr     ( cart_wr    ),
	.cart_do     ( cart_do    ),
	.cart_di     ( cart_di    ),
	.cart_oe     ( cart_oe    ),

	.nCS         ( nCS        ),

	.sdram_rd    ( sdram_rd   ),

	.boot_gba_en    ( boot_gba_available && status[37] ),
	.fast_boot_en   ( fastboot_available && (status[42] || mc_sys_ovr != 2'd0) ),   // a movie always gets the short boot the offsets were measured on

	.cgb_boot_download ( cgb_boot_download ),
	.dmg_boot_download ( dmg_boot_download ),
	.sgb_boot_download ( sgb_boot_download ),
	.ioctl_wr       ( ioctl_wr       ),
	.ioctl_addr     ( ioctl_addr     ),
	.ioctl_dout     ( ioctl_dout     ),

	// audio
	.audio_l 	 ( GB_AUDIO_L ),
	.audio_r 	 ( GB_AUDIO_R ),
	.audio_no_pops (status[43]),
	
	// interface to the lcd
	.lcd_clkena  ( lcd_clkena ),
	.lcd_data    ( lcd_data   ),
	.lcd_data_gb ( lcd_data_gb ),
	.lcd_mode    ( lcd_mode   ),
	.lcd_on      ( lcd_on     ),
	.lcd_vsync   ( lcd_vsync  ),
	
	.speed       ( speed      ),
	.DMA_on      ( DMA_on    ),
	
	// serial port
	.sc_int_clock2(sc_int_clock_out),
	.serial_clk_in(ser_clk_in),
	.serial_data_in(ser_data_in),
	.serial_clk_out(ser_clk_out),
	.serial_data_out(ser_data_out),
	
	// Palette download will disable cheats option (HPS doesn't distinguish downloads),
	// so clear the cheats and disable second option (chheats enable/disable)
	.gg_reset((code_download && ioctl_wr && !ioctl_addr) | cart_download | palette_download),
	.gg_en(~status[17]),
	.gg_code(gg_code),
	.gg_available(gg_available),
	
	// savestates
	.increaseSSHeaderCount (!status[31]),
	.cart_ram_size   (cart_ram_size),
	.save_state      (ss_save),
	.load_state      (ss_load),
	.savestate_number(ss_slot),
	.sleep_savestate (sleep_savestate),
	.savestate_ovr   (savestate_ovr),
	
	.SaveStateExt_Din (SaveStateBus_Din),
	.SaveStateExt_Adr (SaveStateBus_Adr),
	.SaveStateExt_wren(SaveStateBus_wren),
	.SaveStateExt_rst (SaveStateBus_rst),
	.SaveStateExt_Dout(SaveStateBus_Dout),
	.SaveStateExt_load(savestate_load),
	
	.Savestate_CRAMAddr     (Savestate_CRAMAddr),
	.Savestate_CRAMRdEn     (Savestate_CRAMRdEn),
	.Savestate_CRAMRWrEn    (Savestate_CRAMRWrEn),
	.Savestate_CRAMWriteData(Savestate_CRAMWriteData),
	.Savestate_CRAMReadData (Savestate_CRAMReadData),
	
	.SAVE_out_Din(ss_din),            // data read from savestate
	.SAVE_out_Dout(ss_dout),          // data written to savestate
	.SAVE_out_Adr(ss_addr),           // all addresses are DWORD addresses!
	.SAVE_out_rnw(ss_rnw),            // read = 1, write = 0
	.SAVE_out_ena(ss_req),            // one cycle high for each action
	.SAVE_out_be(ss_be),            
	.SAVE_out_done(ss_ack),            // should be one cycle high when write is done or read value is valid
	
	.savestate_sdram_busy(sdram_busy),

	.rewind_on(status[27]),
	.rewind_active(status[27] & joystick_0[10])
);

assign AUDIO_L = (fast_forward && status[25]) ? 16'd0 : GB_AUDIO_L;
assign AUDIO_R = (fast_forward && status[25]) ? 16'd0 : GB_AUDIO_R;

// the lcd to vga converter
wire [7:0] R,G,B;
wire video_hs, video_vs;
wire HBlank, VBlank;
wire ce_pix;
wire [8:0] h_cnt, v_cnt;
wire [1:0] tint = status[2:1];
wire h_end;

lcd lcd
(
	// serial interface
	.clk_sys( clk_sys    ),
	.ce     ( ce_cpu         ),

	.lcd_clkena ( sgb_lcd_clkena ),
	.data   ( sgb_lcd_data   ),
	.mode   ( sgb_lcd_mode   ),  // used to detect begin of new lines and frames
	.on     ( sgb_lcd_on     ),
	.lcd_vs ( sgb_lcd_vsync  ),
	.shadow ( status[36]     ),

	.isGBC  ( isGBC      ),

	.tint   ( |tint       ),
	.inv    ( status[12]  ),
	.double_buffer( status[5]),
	.frame_blend( status[16] ),
	.originalcolors( gbc_raw_colors ),
	.analog_wide ( status[34] ),

	// Palettes
	.pal1   (palette[127:104]),
	.pal2   (palette[103:80]),
	.pal3   (palette[79:56]),
	.pal4   (palette[55:32]),

	.lut_download (cgb_lut_download),
	.ioctl_wr     (ioctl_wr),
	.ioctl_addr   (ioctl_addr),
	.ioctl_dout   (ioctl_dout),

	.sgb_border_pix ( sgb_border_pix),
	.sgb_pal_en     ( sgb_pal_en ),
	.sgb_en         ( sgb_border_en ),
	.sgb_freeze     ( sgb_lcd_freeze),

	.clk_vid( CLK_VIDEO  ),
	.hs     ( video_hs   ),
	.vs     ( video_vs   ),
	.hbl    ( HBlank     ),
	.vbl    ( VBlank     ),
	.r      ( R          ),
	.g      ( G          ),
	.b      ( B          ),
	.ce_pix ( ce_pix     ),
	.h_cnt  ( h_cnt      ),
	.v_cnt  ( v_cnt      ),
	.h_end  ( h_end      )
);

wire [1:0] joy_p54;
wire [3:0] joy_do_sgb;
wire [14:0] sgb_lcd_data;
wire [15:0] sgb_border_pix;
wire sgb_lcd_clkena, sgb_lcd_on, sgb_lcd_vsync, sgb_lcd_freeze;
wire [1:0] sgb_lcd_mode;
wire sgb_pal_en;
wire [1:0] sgb_en = status[24:23];
// Super Game Boy path: the menu's choice, unless a movie is running that
// was made for a DMG or GBC (SGB off) or for an SGB (on). A DMG movie on an
// SGB-enhanced cart with the menu at Palette or On otherwise boots the SGB
// path and stalls in the game's SGB handshake (Contra, 2026-09-07).
wire sgb_sel = (mc_sys_ovr != 2'd0) ? (mc_sys_ovr == 2'd3) : |sgb_en;
wire sgb_border_en = (mc_sys_ovr != 2'd0) ? 1'b0 : sgb_en[1];

sgb sgb (
	.reset       ( reset       ),
	.clk_sys     ( clk_sys     ),
	.ce          ( ce_cpu      ),

	.clk_vid     ( CLK_VIDEO   ),
	.ce_pix      ( ce_pix      ),

	// MiSTer Control replay: the movie owns all four pads while it runs
	.joystick_0  ( mc_joy0     ),
	.joystick_1  ( mc_joy1     ),
	.joystick_2  ( mc_joy2     ),
	.joystick_3  ( mc_joy3     ),
	.joy_p54     ( joy_p54     ),
	.joy_do      ( joy_do_sgb  ),

	.sgb_en      ( sgb_sel & isSGB_game & (~isGBC | status[35]) ),
	.tint        ( tint[1]     ),
	.isGBC_game  ( isGBC & isGBC_game ),

	.lcd_on      ( lcd_on      ),
	.lcd_clkena  ( lcd_clkena  ),
	.lcd_data    ( lcd_data    ),
	.lcd_data_gb ( lcd_data_gb ),
	.lcd_mode    ( lcd_mode    ),
	.lcd_vsync   ( lcd_vsync   ),

	.h_cnt       ( h_cnt      ),
	.v_cnt       ( v_cnt      ),
	.h_end       ( h_end      ),

	.border_download (sgb_border_download),
	.ioctl_wr        (ioctl_wr),
	.ioctl_addr      (ioctl_addr),
	.ioctl_dout      (ioctl_dout),

	.sgb_border_pix  ( sgb_border_pix  ),
	.sgb_pal_en      ( sgb_pal_en      ),
	.sgb_lcd_data    ( sgb_lcd_data    ),
	.sgb_lcd_on      ( sgb_lcd_on      ),
	.sgb_lcd_freeze  ( sgb_lcd_freeze  ),
	.sgb_lcd_clkena  ( sgb_lcd_clkena  ),
	.sgb_lcd_mode    ( sgb_lcd_mode    ),
	.sgb_lcd_vsync   ( sgb_lcd_vsync   )
);

reg HSync, VSync;
always @(posedge CLK_VIDEO) begin
	if(ce_pix) begin
		HSync <= video_hs;
		if(~HSync & video_hs) VSync <= video_vs;
	end
end

assign VGA_F1 = 0;
assign VGA_SL = sl[1:0];

wire [2:0] scale = status[20:18];
wire [2:0] sl = scale ? scale - 1'd1 : 3'd0;
wire       scandoubler = (scale || forced_scandoubler);

video_mixer #(.LINE_LENGTH(200), .GAMMA(1)) video_mixer
(
	.*,
	.freeze_sync(),
	.hq2x(scale==1)
);

wire [1:0] ar = status[4:3];
video_freak video_freak
(
	.*,
	.VGA_DE_IN(VGA_DE),
	.VGA_DE(),

	.ARX((!ar) ? (sgb_border_en ? 12'd16 : 12'd10) : (ar - 1'd1)),
	.ARY((!ar) ? (sgb_border_en ? 12'd14 : 12'd9 ) : 12'd0),
	.CROP_SIZE(0),
	.CROP_OFF(0),
	.SCALE(status[22:21])
);

//////////////////////////////// CE ////////////////////////////////////


wire ce_cpu, ce_cpu_n, ce_cpu2x;
wire cart_act = cart_wr | cart_rd;

wire fastforward = joystick_0[8] && !ioctl_download && !OSD_STATUS;

wire sleep_savestate, savestate_ovr;

reg paused;
always_ff @(posedge clk_sys) begin
   paused <= sleep_savestate | (status[26] && OSD_STATUS && !ioctl_download && !reset && ~status[27]); // no pause when downloading rom, resetting or rewind capture is on
end

speedcontrol speedcontrol
(
	.clk_sys     (clk_sys),
	.pause       (paused),
	.speedup     (fast_forward),
	.cart_act    (cart_act),
	.save_act    (bk_state),
	.DMA_on      (DMA_on),
	.ce          (ce_cpu),
	.ce_n        (ce_cpu_n),
	.ce_2x       (ce_cpu2x),
	.refresh     (sdram_pause_refresh),
	.ff_on       ()
);

///////////////////////////// Fast Forward Latch /////////////////////////////////

reg fast_forward;
reg ff_latch;

always @(posedge clk_sys) begin : ffwd
	reg last_ffw;
	reg ff_was_held;
	longint ff_count;

	last_ffw <= fastforward;

	if (fastforward)
		ff_count <= ff_count + 1;

	if (~last_ffw & fastforward) begin
		ff_latch <= 0;
		ff_count <= 0;
	end

	if ((last_ffw & ~fastforward)) begin // 32mhz clock, 0.2 seconds
		ff_was_held <= 0;

		if (ff_count < 3200000 && ~ff_was_held) begin
			ff_was_held <= 1;
			ff_latch <= 1;
		end
	end

	fast_forward <= (fastforward | ff_latch);
end

///////////////////////////// savestates /////////////////////////////////

wire [63:0] SaveStateBus_Din; 
wire [9:0]  SaveStateBus_Adr; 
wire        SaveStateBus_wren;
wire        SaveStateBus_rst; 
wire [63:0] SaveStateBus_Dout;
wire        savestate_load;

wire [19:0] Savestate_CRAMAddr;     
wire        Savestate_CRAMRdEn;
wire        Savestate_CRAMRWrEn;    
wire [15:0] Savestate_CRAMWriteData;
wire [15:0] Savestate_CRAMReadData;
	
wire [63:0] ss_dout, ss_din;
wire [27:2] ss_addr;
wire  [7:0] ss_be;
wire        ss_rnw, ss_req, ss_ack;

assign DDRAM_CLK = clk_sys;
ddram ddram
(
	.*,

	.ch1_addr({ss_addr, 1'b0}),
	.ch1_din(ss_din),
	.ch1_dout(ss_dout),
	.ch1_req(ss_req),
	.ch1_rnw(ss_rnw),
	.ch1_be(ss_be),
	.ch1_ready(ss_ack),

	// MiSTer Control telemetry
	.ch2_addr(mc_ddr_addr),
	.ch2_din(mc_ddr_din),
	.ch2_req(mc_ddr_req),
	.ch2_ready(mc_ddr_ready),

	// MiSTer Control replay
	.ch3_addr(mc_rd_addr),
	.ch3_req(mc_rd_req),
	.ch3_dout(mc_rd_dout),
	.ch3_ready(mc_rd_ready)
);

// saving with keyboard/OSD/gamepad
wire [1:0] ss_slot;
wire [7:0] ss_info;
wire ss_save, ss_load, ss_info_req;
wire statusUpdate;

savestate_ui savestate_ui
(
	.clk            (clk_sys       ),
	.ps2_key        (ps2_key[10:0] ),
	.allow_ss       (cart_ready    ),
	.joySS          (joy0_unmod[9] ),
	.joyRight       (joy0_unmod[0] ),
	.joyLeft        (joy0_unmod[1] ),
	.joyDown        (joy0_unmod[2] ),
	.joyUp          (joy0_unmod[3] ),
	.joyStart       (joy0_unmod[7] ),
	.joyRewind      (joy0_unmod[10]),
	.rewindEnable   (status[27]    ), 
	.status_slot    (status[33:32] ),
	.OSD_saveload   (status[29:28] ),
	.ss_save        (ss_save       ),
	.ss_load        (ss_load       ),
	.ss_info_req    (ss_info_req   ),
	.ss_info        (ss_info       ),
	.statusUpdate   (statusUpdate  ),
	.selected_slot  (ss_slot       )
);
defparam savestate_ui.INFO_TIMEOUT_BITS = 27;

///////////////////////////// CHEATS //////////////////////////////////
// Code loading for WIDE IO (16 bit)
reg [128:0] gg_code;
wire        gg_available;
wire        code_download = &filetype;

// Code layout:
// {clock bit, code flags,     32'b address, 32'b compare, 32'b replace}
//  128        127:96          95:64         63:32         31:0
// Integer values are in BIG endian byte order, so it up to the loader
// or generator of the code to re-arrange them correctly.

always_ff @(posedge clk_sys) begin
	gg_code[128] <= 1'b0;

	if (code_download & ioctl_wr) begin
		case (ioctl_addr[3:0])
			0:  gg_code[111:96]  <= ioctl_dout; // Flags Bottom Word
			2:  gg_code[127:112] <= ioctl_dout; // Flags Top Word
			4:  gg_code[79:64]   <= ioctl_dout; // Address Bottom Word
			6:  gg_code[95:80]   <= ioctl_dout; // Address Top Word
			8:  gg_code[47:32]   <= ioctl_dout; // Compare Bottom Word
			10: gg_code[63:48]   <= ioctl_dout; // Compare top Word
			12: gg_code[15:0]    <= ioctl_dout; // Replace Bottom Word
			14: begin
				gg_code[31:16]    <= ioctl_dout; // Replace Top Word
				gg_code[128]      <= 1'b1;       // Clock it in
			end
		endcase
	end
end

/////////////////////////////  Serial link  ///////////////////////////////

assign USER_OUT[2] = 1'b1;
assign USER_OUT[3] = 1'b1;
assign USER_OUT[4] = 1'b1;
assign USER_OUT[5] = 1'b1;
assign USER_OUT[6] = 1'b1;

wire sc_int_clock_out;
wire ser_data_in;
wire ser_data_out;
wire ser_clk_in;
wire ser_clk_out;
wire workboy_ena = status[45];
wire ig_kb_ena   = status[46];
wire duck_laptop_ena = status[47] & megaduck;
wire serial_ena  = status[6] & ~workboy_ena & ~ig_kb_ena & ~duck_laptop_ena;
wire workboy_data_out;
wire ig_kb_data_out;
wire duck_laptop_data_out;
wire duck_laptop_clk_out;

workboy workboy
(
	.clk_sys(clk_sys),
	.reset(reset | ~workboy_ena),
	.ps2_key(ps2_key),
	.rtc_bcd(RTC_bcd),
	.serial_clk_in(ser_clk_out),
	.serial_data_in(ser_data_out),
	.serial_data_out(workboy_data_out)
);

ig_kb ig_kb
(
	.clk_sys(clk_sys),
	.reset(reset | ~ig_kb_ena),
	.ps2_key(ps2_key),
	.ps2_mouse(ps2_mouse),
	.serial_clk_in(ser_clk_out),
	.serial_data_out(ig_kb_data_out)
);

megaduck_laptop megaduck_laptop
(
	.clk_sys(clk_sys),
	.reset(reset | ~duck_laptop_ena),
	.ce_32k(ce_32k),
	.ps2_key(ps2_key),
	.rtc_bcd(RTC_bcd),
	.serial_clk_in(ser_clk_out),
	.serial_data_in(ser_data_out),
	.serial_clk_out(duck_laptop_clk_out),
	.serial_data_out(duck_laptop_data_out)
);

assign ser_data_in = duck_laptop_ena ? duck_laptop_data_out :
                     ig_kb_ena   ? ig_kb_data_out   :
                     workboy_ena ? workboy_data_out  :
                     serial_ena  ? USER_IN[2]        : 1'b1;
assign USER_OUT[1] = serial_ena ? ser_data_out : 1'b1;

assign ser_clk_in = duck_laptop_ena ? duck_laptop_clk_out :
                    serial_ena ? USER_IN[0] : 1'b1;
assign USER_OUT[0] = (serial_ena & sc_int_clock_out) ? ser_clk_out : 1'b1;



/////////////////////////  BRAM SAVE/LOAD  /////////////////////////////





wire downloading = cart_download;

reg  bk_ena          = 0;
reg  new_load        = 0;
reg  old_downloading = 0;
reg  sav_pending     = 0;
wire sav_supported   = cart_has_save && bk_ena;

always @(posedge clk_sys) begin
	old_downloading <= downloading;
	if(~old_downloading & downloading) bk_ena <= 0;

	//Save file always mounted in the end of downloading state.
	if(downloading && img_mounted && !img_readonly) bk_ena <= 1;

	// A MiSTer Control movie drops the pending auto-load instead of holding
	// it: held, it fired the moment the movie ended and a load resets the
	// console, which hid the run's ending behind the title screen (seen with
	// Super Mario Land 2, 2026-09-07). The run's own writes into cartridge RAM
	// are never saved over the owner's file either.
	if (old_downloading & ~downloading & sav_supported)
		new_load <= 1'b1;
	else if (bk_state | mc_rp_armed)
		new_load <= 1'b0;

	if ((cram_wr | cram_bram_wr) & ~OSD_STATUS & sav_supported & ~mc_rp_armed)
		sav_pending <= 1'b1;
	else if (bk_state | mc_rp_armed)
		sav_pending <= 1'b0;
end

// no backup RAM load or save while a MiSTer Control movie is armed or
// running: the run starts from a clean cartridge, as the emulator did
wire bk_load    = (status[9] | new_load) & ~mc_rp_armed;
wire bk_save    = (status[10] | (sav_pending & OSD_STATUS & status[13])) & ~mc_rp_armed;
reg  bk_loading = 0;
reg  bk_state   = 0;


always @(posedge clk_sys) begin
	reg old_load = 0, old_save = 0, old_ack;

	old_load <= bk_load;
	old_save <= bk_save;
	old_ack  <= sd_ack;
	
	if(~old_ack & sd_ack) {sd_rd, sd_wr} <= 0;
	
	if(!bk_state) begin
		if(bk_ena & ((~old_load & bk_load) | (~old_save & bk_save))) begin
			bk_state <= 1;
			bk_loading <= bk_load;
			sd_lba <= 32'd0;
			sd_rd <=  bk_load;
			sd_wr <= ~bk_load;
		end
		if(old_downloading & ~downloading & |img_size & bk_ena & ~mc_rp_armed) begin
			bk_state <= 1;
			bk_loading <= 1;
			sd_lba <= 0;
			sd_rd <= 1;
			sd_wr <= 0;
		end
	end else begin
		if(old_ack & ~sd_ack) begin
			
			if (RTC_inuse && sd_lba[7:0]>ram_mask_file) begin // save/load one block more when game/savefile uses RTC, only first 8 bytes used
				bk_loading <= 0;
				bk_state <= 0;
			end else if(!RTC_inuse && sd_lba[7:0]>=ram_mask_file) begin
				bk_loading <= 0;
				bk_state <= 0;
			end else begin
				sd_lba <= sd_lba + 1'd1;
				sd_rd  <=  bk_loading;
				sd_wr  <= ~bk_loading;
			end
		end
	end
end

wire [15:0] bk_addr = {sd_lba[7:0],sd_buff_addr};
wire bk_addr_end = (sd_lba[7:0] > ram_mask_file);
wire bk_wr = bk_addr_end ? 1'b0 : sd_buff_wr & sd_ack; // only restore data amount of saveram, don't save on RTC data
wire bk_rtc_wr = bk_addr_end & sd_buff_wr & sd_ack;
wire [15:0] bk_data = sd_buff_dout;
wire [15:0] bk_q;
assign sd_buff_din = (sd_lba[7:0] <= ram_mask_file) ? ( bram_save ? bk_q : save_dout ) :  // normal saveram data or RTC data
					 (sd_buff_addr == 8'd0) ? RTC_timestampOut[15:0]  :
					 (sd_buff_addr == 8'd1) ? RTC_timestampOut[31:16] :
					 (sd_buff_addr == 8'd2) ? RTC_savedtimeOut[15:0]  :
					 (sd_buff_addr == 8'd3) ? RTC_savedtimeOut[31:16] :
					 (sd_buff_addr == 8'd4) ? RTC_savedtimeOut[47:32] :
					 16'hFFFF;


wire save_busy;
reg save_rd, save_wr;
reg save_wait;
reg [15:0] save_addr;

always @(posedge clk_sys) begin

	if(~save_busy & ~save_rd & ~save_wr) save_wait <= 0;

	if(~bk_state) begin
		save_addr <= '1;
		save_wait <= 0;
	end else if(sd_ack & ~save_busy) begin
		if( ~bk_loading & ~bk_addr_end & (save_addr != bk_addr) ) begin
			save_rd <= 1;
			save_addr <= bk_addr;
			save_wait <= 1;
		end
		if( bk_loading & ~bk_addr_end & sd_buff_wr ) begin
			save_wr <= 1;
			save_addr <= bk_addr;
			save_wait <= 1;
		end
	end
	if(~bk_state | save_busy) {save_rd, save_wr} <= 0;
end

/**********************************************************/
/*************     MiSTer Control telemetry   *************/
/**********************************************************/
// rtl/mc: a per-frame snapshot (the save state register bus, the 32 KB work
// RAM, the pads the game read) written to DDR3 at 0x3C000000 for the MiSTer
// Control app, and a movie replay from 0x3C100000. Layouts in
// rtl/mc/mc_telemetry.sv and rtl/mc/mc_replay.sv; the Gameboy taps are the
// mc_* ports of rtl/gb.v. MC-NES is the reference wiring (NES.sv).


// the pads as the game last read them
reg  [7:0] mc_j1, mc_j2, mc_j3, mc_j4;
always @(posedge clk_sys) if (mc_joy_read) begin
	mc_j1 <= mc_joy0;
	mc_j2 <= mc_joy1;
	mc_j3 <= mc_joy2;
	mc_j4 <= mc_joy3;
end

mc_replay #(.ENTRY_BYTES(8), .CLK_HZ(32'd33554432)) mc_replay
(
	.clk(clk_sys),
	.reset(reset),
	.downloading(cart_download),
	// entry N at the rising edge of GBHawk's in_vblank: line 144 with the LCD on
	// (GB_PPU.cs:190-193), and the LCD switched off outside vblank (with the LCD
	// off the PPU tick holds in_vblank true, GB_PPU.cs:434-440; switching it on
	// clears it, :198-201); the pads latch on that edge (GBHawk.IEmulator.cs:143-150).
	// With lcd_mode alone the core missed the entries Contra's title routine consumes
	// by switching the LCD on and off within a frame (4199M: movie frames 350, 358,
	// 362, 366 are non-lag with LCDC bit 7 clear), and ran 3 entries behind from
	// there (2026-09-08). With lcd_vsync (line 0) a one-frame tap read during the
	// picture landed a frame late (SML2 3746M, 2026-09-07).
	.vblank(~lcd_on | (lcd_mode == 2'b01)),
	.joy_read(mc_joy_read),
	// Gambatte frames (header w2 bit 5): counted in CPU cycles from LCDC bit 7
	// and the vblank interrupt line (the model in mc_replay.sv)
	.cyc(ce_cpu),
	.lcd_on(lcd_on),
	.m1_irq(mc_vblank_irq),
	.ddr_addr(mc_rd_addr),
	.ddr_req(mc_rd_req),
	.ddr_dout(mc_rd_dout),
	.ddr_ready(mc_rd_ready),
	.active(mc_rp_active),
	.p1(mc_rp_p1),
	.p2(mc_rp_p2),
	.p3(mc_rp_p3),
	.p4(mc_rp_p4),
	.index(mc_rp_index),
	.state(mc_rp_state),
	.sys_mode(mc_rp_sys),
	.gen(mc_rp_gen),
	.entry_bytes(mc_rp_entry_bytes)
);

wire        mc_ram_hold;
wire [15:0] mc_ram_rd_addr;
wire  [7:0] mc_ram_rd_data, mc_bm_data;
wire [12:0] mc_bm_addr;
wire        mc_ram_torn;

// 64 KB image (the CPU address space, see gb.v), 4096 pending writes: the
// read-out of 64 KB takes about 3.3 ms per frame and the CPU can write
// every other cycle at double speed (about 3,300 writes in that time).
mc_shadow_ram #(.ADDR_W(16), .FIFO_W(12)) mc_shadow_ram
(
	.clk(clk_sys),
	.clear(cart_download),
	.wr(mc_wr),
	.wr_addr(mc_wr_addr),
	.wr_data(mc_wr_data),
	.hold(mc_ram_hold),
	.rd_addr(mc_ram_rd_addr),
	.rd_data(mc_ram_rd_data),
	.bm_addr(mc_bm_addr),
	.bm_data(mc_bm_data),
	.torn(mc_ram_torn)
);

// system type: 0 DMG, 1 GBC, 2 SGB (the emulator's console choice)
wire [2:0] mc_sys_type = isGBC ? 3'd1 : sgb_sel ? 3'd2 : 3'd0;

// When in the frame the game read the pads: 4 MHz cycles (ce_cpu) counted from
// the lcd_vsync rising edge the telemetry takes as the frame boundary. The
// telemetry samples these on that same edge, so a slot carries the finished
// frame's values. Slot word 1 (cpu_regs; REGS_KIND 1 leaves it free):
// [16:0] first $FF00 read, [33:17] last, [50:34] frame length, [51] a read happened.
reg [16:0] mc_fcyc = 0, mc_rd_first = 0, mc_rd_last = 0;
reg        mc_rd_seen = 0, mc_vs_d = 0;
always @(posedge clk_sys) begin
	mc_vs_d <= lcd_vsync;
	if (lcd_vsync & ~mc_vs_d) begin
		mc_fcyc    <= 0;
		mc_rd_seen <= mc_joy_read;
		if (mc_joy_read) begin
			mc_rd_first <= 0;
			mc_rd_last  <= 0;
		end
	end
	else begin
		if (ce_cpu && mc_fcyc != 17'h1FFFF) mc_fcyc <= mc_fcyc + 17'd1;
		if (mc_joy_read) begin
			if (!mc_rd_seen) mc_rd_first <= mc_fcyc;
			mc_rd_last <= mc_fcyc;
			mc_rd_seen <= 1;
		end
	end
end
wire [63:0] mc_stamps = {12'd0, mc_rd_seen, mc_fcyc, mc_rd_last, mc_rd_first};

// PPU-timeline events for the instruction trace (build p): every STAT or LY read
// with the byte the CPU latched, every rise of the vblank and STAT interrupt
// lines, and every interrupt acknowledge, each stamped with the PPU's own line
// and cycle and the frame cycle. Three ring entries per event:
//   {FFF0 | kind, val[7:0], vcnt[7:0]}  {FFFA, 7'd0, hcyc[8:0]}  {FFFB, fcyc[15:0]}
// kind 1 STAT read, 2 LY read, 3 interrupt line rise (val bit 0 vblank, bit 1
// STAT), 4 interrupt acknowledge. Two sources (CPU side, PPU side) can fire on
// the same clock; each holds one burst, the CPU burst goes first; a source that
// fires again before its burst went is dropped (mc_aux_drops).
reg        mc_vbl_d = 0, mc_vid_d = 0;
reg        mc_axc_pend = 0, mc_axp_pend = 0;
reg [19:0] mc_axc_w0 = 0, mc_axp_w0 = 0;   // {kind[3:0], val[7:0], vcnt[7:0]}
reg [15:0] mc_axc_w1 = 0, mc_axc_w2 = 0, mc_axp_w1 = 0, mc_axp_w2 = 0;
reg  [1:0] mc_ax_step = 0;     // 0: idle, 1..3: word n of the current burst goes out
reg        mc_ax_src = 0;      // 0: CPU burst, 1: PPU burst
reg  [7:0] mc_aux_drops = 0;
reg        mc_aux_we = 0;
reg [31:0] mc_aux_word = 0;
wire       mc_aux_ready;
wire       mc_cpu_ev = mc_rd_we | mc_irq_ack;
wire       mc_ppu_ev = (mc_vblank_irq & ~mc_vbl_d) | (mc_video_irq & ~mc_vid_d);
always @(posedge clk_sys) begin
	mc_vbl_d <= mc_vblank_irq;
	mc_vid_d <= mc_video_irq;
	if (mc_cpu_ev) begin
		if (mc_axc_pend && mc_aux_drops != 8'hFF) mc_aux_drops <= mc_aux_drops + 8'd1;
		mc_axc_pend <= 1;
		mc_axc_w0 <= {mc_irq_ack ? 4'd4 : {2'd0, mc_rd_kind}, mc_irq_ack ? 8'd0 : mc_rd_val, mc_vcnt};
		mc_axc_w1 <= {7'd0, mc_hcyc};
		mc_axc_w2 <= mc_fcyc[15:0];
	end
	if (mc_ppu_ev) begin
		if (mc_axp_pend && mc_aux_drops != 8'hFF) mc_aux_drops <= mc_aux_drops + 8'd1;
		mc_axp_pend <= 1;
		mc_axp_w0 <= {4'd3, 6'd0, mc_video_irq & ~mc_vid_d, mc_vblank_irq & ~mc_vbl_d, mc_vcnt};
		mc_axp_w1 <= {7'd0, mc_hcyc};
		mc_axp_w2 <= mc_fcyc[15:0];
	end
	mc_aux_we <= 0;
	if (mc_ax_step == 0) begin
		if (mc_axc_pend && !mc_cpu_ev) begin mc_ax_src <= 0; mc_ax_step <= 1; end
		else if (mc_axp_pend && !mc_ppu_ev) begin mc_ax_src <= 1; mc_ax_step <= 1; end
	end
	else if (mc_aux_ready) begin
		mc_aux_we <= 1;
		case (mc_ax_step)
		2'd1: mc_aux_word <= {12'hFFF, mc_ax_src ? mc_axp_w0 : mc_axc_w0};   // 12 + 20 bits
		2'd2: mc_aux_word <= {16'hFFFA, mc_ax_src ? mc_axp_w1 : mc_axc_w1};
		default: begin
			mc_aux_word <= {16'hFFFB, mc_ax_src ? mc_axp_w2 : mc_axc_w2};
			if (mc_ax_src) mc_axp_pend <= 0; else mc_axc_pend <= 0;
		end
		endcase
		mc_ax_step <= (mc_ax_step == 2'd3) ? 2'd0 : mc_ax_step + 2'd1;
	end
end

// Per-frame counts of the PPU accesses the game paces itself with, latched on
// the same lcd_vsync edge and presented as telemetry bus words 60..62 (the
// save-state register bus stops at index 5):
//   60: [15:0] STAT reads, [32:16] cycle of the first, [49:33] cycle of the last
//   61: [15:0] LY reads, [23:16] OAM DMA writes, [40:24] cycle of the first DMA write, [48:41] LCDC writes
//   62: [16:0] cycles the PPU spent in mode 3 (ce_cpu), [33:17] in mode 2, [50:34] in mode 0
reg [15:0] mc_stat_n = 0, mc_ly_n = 0;
reg [16:0] mc_stat_first = 0, mc_stat_last = 0, mc_dma_first = 0, mc_m3_cyc = 0, mc_m2_cyc = 0, mc_m0_cyc = 0;
reg  [7:0] mc_dma_n = 0, mc_lcdc_n = 0;
reg [63:0] mc_w60 = 0, mc_w61 = 0, mc_w62 = 0;
always @(posedge clk_sys) begin
	if (lcd_vsync & ~mc_vs_d) begin
		mc_w60 <= {14'd0, mc_stat_last, mc_stat_first, mc_stat_n};
		mc_w61 <= {15'd0, mc_lcdc_n, mc_dma_first, mc_dma_n, mc_ly_n};
		mc_w62 <= {13'd0, mc_m0_cyc, mc_m2_cyc, mc_m3_cyc};
		mc_stat_n <= 0; mc_ly_n <= 0; mc_dma_n <= 0; mc_lcdc_n <= 0;
		mc_stat_first <= 0; mc_stat_last <= 0; mc_dma_first <= 0;
		mc_m3_cyc <= 0; mc_m2_cyc <= 0; mc_m0_cyc <= 0;
	end
	else begin
		if (mc_stat_read) begin
			if (mc_stat_n == 0) mc_stat_first <= mc_fcyc;
			mc_stat_last <= mc_fcyc;
			if (mc_stat_n != 16'hFFFF) mc_stat_n <= mc_stat_n + 16'd1;
		end
		if (mc_ly_read && mc_ly_n != 16'hFFFF) mc_ly_n <= mc_ly_n + 16'd1;
		if (mc_dma_write) begin
			if (mc_dma_n == 0) mc_dma_first <= mc_fcyc;
			if (mc_dma_n != 8'hFF) mc_dma_n <= mc_dma_n + 8'd1;
		end
		if (mc_lcdc_write && mc_lcdc_n != 8'hFF) mc_lcdc_n <= mc_lcdc_n + 8'd1;
		if (ce_cpu && lcd_on) begin
			if (lcd_mode == 2'b11 && mc_m3_cyc != 17'h1FFFF) mc_m3_cyc <= mc_m3_cyc + 17'd1;
			if (lcd_mode == 2'b10 && mc_m2_cyc != 17'h1FFFF) mc_m2_cyc <= mc_m2_cyc + 17'd1;
			if (lcd_mode == 2'b00 && mc_m0_cyc != 17'h1FFFF) mc_m0_cyc <= mc_m0_cyc + 17'd1;
		end
	end
end
assign mc_bus_dout = (mc_bus_adr == 10'd60) ? mc_w60 :
                     (mc_bus_adr == 10'd61) ? mc_w61 :
                     (mc_bus_adr == 10'd62) ? mc_w62 : mc_bus_dout_gb;

mc_telemetry #(
	.MAGIC(64'h01000042_472D434D),   // "MC-GB\0\0\1"
	.RAM_ADDR_W(16),
	.PAD_COUNT(4),
	.REGS_KIND(1),                   // no packed CPU word: the registers are on the bus (reg_savestates.vhd index 1..5)
	.SLOT_WORDS(25'd9344),           // 74752 byte slots (>= 73 + 65536 * 9 / 64 words)
	.TRACE(1)                        // instruction trace ring at 0x3D000000, 8 MB (the replay buffer is at 0x3C100000)
) mc_telemetry
(
	.clk(clk_sys),
	.reset(reset),
	.enable(~status[51]),
	.vblank(lcd_vsync),
	.scanline(v_cnt),
	.cycle(h_cnt),
	.clk_hz(32'd33554432),
	.sys_type(mc_sys_type),
	.cpu_regs(mc_stamps),
	.bus_adr(mc_bus_adr),
	.bus_dout(mc_bus_dout),
	.bus_free(mc_bus_free),
	.ram_hold(mc_ram_hold),
	.ram_rd_addr(mc_ram_rd_addr),
	.ram_rd_data(mc_ram_rd_data),
	.bm_addr(mc_bm_addr),
	.bm_data(mc_bm_data),
	.ram_torn(mc_ram_torn),
	.joy1_latched(mc_j1),
	.joy2_latched(mc_j2),
	.joy3_latched(mc_j3),
	.joy4_latched(mc_j4),
	.joy_strobe(mc_strobe),
	.joy_read(mc_joy_read),
	.replay_active(mc_rp_active),
	.replay_index(mc_rp_index),
	.replay_state(mc_rp_state),
	.replay_gen(mc_rp_gen),
	.replay_entry_bytes(mc_rp_entry_bytes),
	.trace_we(mc_fetch),
	.trace_pc(mc_pc),
	.trace_cyc(mc_fcyc[15:0]),
	.aux_we(mc_aux_we),
	.aux_word(mc_aux_word),
	.aux_ready(mc_aux_ready),
	.ddr_addr(mc_ddr_addr),
	.ddr_din(mc_ddr_din),
	.ddr_req(mc_ddr_req),
	.ddr_ready(mc_ddr_ready),
	.frame(mc_frame)
);

endmodule
