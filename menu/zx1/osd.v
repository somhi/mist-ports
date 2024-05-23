module osd (
	clk_sys,
	ce,
	SPI_SCK,
	SPI_SS3,
	SPI_DI,
	rotate,
	R_in,
	G_in,
	B_in,
	HBlank,
	VBlank,
	HSync,
	VSync,
	R_out,
	G_out,
	B_out
);
	input clk_sys;
	input ce;
	input SPI_SCK;
	input SPI_SS3;
	input SPI_DI;
	input [1:0] rotate;
	parameter OUT_COLOR_DEPTH = 6;
	input [OUT_COLOR_DEPTH - 1:0] R_in;
	input [OUT_COLOR_DEPTH - 1:0] G_in;
	input [OUT_COLOR_DEPTH - 1:0] B_in;
	input HBlank;
	input VBlank;
	input HSync;
	input VSync;
	output wire [OUT_COLOR_DEPTH - 1:0] R_out;
	output wire [OUT_COLOR_DEPTH - 1:0] G_out;
	output wire [OUT_COLOR_DEPTH - 1:0] B_out;
	parameter OSD_X_OFFSET = 11'd0;
	parameter OSD_Y_OFFSET = 11'd0;
	parameter OSD_COLOR = 3'd0;
	parameter OSD_AUTO_CE = 1'b1;
	parameter USE_BLANKS = 1'b0;
	parameter BIG_OSD = 1'b0;
	localparam OSD_WIDTH = 11'd256;
	localparam OSD_HEIGHT = 11'd128;
	localparam OSD_LINES = 8 << BIG_OSD;
	localparam OSD_WIDTH_PADDED = OSD_WIDTH + (OSD_WIDTH >> 1);
	reg osd_enable;
	(* ramstyle = "no_rw_check" *) reg [7:0] osd_buffer [(256 * OSD_LINES) - 1:0];
	always @(posedge SPI_SCK or posedge SPI_SS3) begin : sv2v_autoblock_1
		reg [4:0] cnt;
		reg [11:0] bcnt;
		reg [7:0] sbuf;
		reg [7:0] cmd;
		if (SPI_SS3) begin
			cnt <= 0;
			bcnt <= 0;
		end
		else begin
			sbuf <= {sbuf[6:0], SPI_DI};
			if (cnt < 15)
				cnt <= cnt + 1'd1;
			else
				cnt <= 8;
			if (cnt == 7) begin
				cmd <= {sbuf[6:0], SPI_DI};
				bcnt <= {sbuf[2:0], SPI_DI, 8'h00};
				if (sbuf[6:3] == 4'b0100)
					osd_enable <= SPI_DI;
			end
			if ((cmd[7:4] == 4'b0010) && (cnt == 15)) begin
				osd_buffer[bcnt] <= {sbuf[6:0], SPI_DI};
				bcnt <= bcnt + 1'd1;
			end
		end
	end
	reg [10:0] h_cnt;
	reg [10:0] hs_low;
	reg [10:0] hs_high;
	wire hs_pol = hs_high < hs_low;
	wire [10:0] dsp_width = (hs_pol & !USE_BLANKS ? hs_low : hs_high);
	reg [10:0] v_cnt;
	reg [10:0] vs_low;
	reg [10:0] vs_high;
	wire vs_pol = vs_high < vs_low;
	wire [10:0] dsp_height = (vs_pol & !USE_BLANKS ? vs_low : vs_high);
	wire doublescan = dsp_height > 350;
	reg auto_ce_pix;
	always @(posedge clk_sys) begin : sv2v_autoblock_2
		reg [15:0] cnt = 0;
		reg [2:0] pixsz;
		reg [2:0] pixcnt;
		reg hs;
		//cnt = 0;
		cnt <= cnt + 1'd1;
		hs <= HSync;
		pixcnt <= pixcnt + 1'd1;
		if (pixcnt == pixsz)
			pixcnt <= 0;
		auto_ce_pix <= !pixcnt;
		if (hs && ~HSync) begin
			cnt <= 0;
			if (cnt <= (OSD_WIDTH_PADDED * 2))
				pixsz <= 0;
			else if (cnt <= (OSD_WIDTH_PADDED * 3))
				pixsz <= 1;
			else if (cnt <= (OSD_WIDTH_PADDED * 4))
				pixsz <= 2;
			else if (cnt <= (OSD_WIDTH_PADDED * 5))
				pixsz <= 3;
			else if (cnt <= (OSD_WIDTH_PADDED * 6))
				pixsz <= 4;
			else
				pixsz <= 5;
			pixcnt <= 0;
			auto_ce_pix <= 1;
		end
	end
	wire ce_pix = (OSD_AUTO_CE ? auto_ce_pix : ce);
	always @(posedge clk_sys) begin : sv2v_autoblock_3
		reg hsD;
		reg vsD;
		if (ce_pix) begin
			if (USE_BLANKS) begin
				h_cnt <= h_cnt + 1'd1;
				if (HBlank) begin
					h_cnt <= 0;
					if (h_cnt != 0) begin
						hs_high <= h_cnt;
						v_cnt <= v_cnt + 1'd1;
					end
				end
				if (VBlank) begin
					v_cnt <= 0;
					if ((v_cnt != 0) && (vs_high != (v_cnt + 1'd1)))
						vs_high <= v_cnt;
				end
			end
			else begin
				hsD <= HSync;
				if (!HSync && hsD) begin
					h_cnt <= 0;
					hs_high <= h_cnt;
				end
				else if (HSync && !hsD) begin
					h_cnt <= 0;
					hs_low <= h_cnt;
					v_cnt <= v_cnt + 1'd1;
				end
				else
					h_cnt <= h_cnt + 1'd1;
				vsD <= VSync;
				if (!VSync && vsD) begin
					v_cnt <= 0;
					if (vs_high != (v_cnt + 1'd1))
						vs_high <= v_cnt;
				end
				else if (VSync && !vsD) begin
					v_cnt <= 0;
					if (vs_low != (v_cnt + 1'd1))
						vs_low <= v_cnt;
				end
			end
		end
	end
	reg [10:0] h_osd_start;
	reg [10:0] h_osd_end;
	reg [10:0] v_osd_start;
	reg [10:0] v_osd_end;
	always @(posedge clk_sys) begin
		h_osd_start <= ((dsp_width - OSD_WIDTH) >> 1) + OSD_X_OFFSET;
		h_osd_end <= h_osd_start + OSD_WIDTH;
		v_osd_start <= ((dsp_height - (OSD_HEIGHT << doublescan)) >> 1) + OSD_Y_OFFSET;
		v_osd_end <= v_osd_start + (OSD_HEIGHT << doublescan);
	end
	wire [10:0] osd_hcnt = h_cnt - h_osd_start;
	wire [10:0] osd_vcnt = v_cnt - v_osd_start;
	wire [10:0] osd_hcnt_next = osd_hcnt + 2'd1;
	reg osd_de;
	reg [11:0] osd_buffer_addr;
	wire [7:0] osd_byte = osd_buffer[osd_buffer_addr];
	reg osd_pixel;
	always @(posedge clk_sys)
		if (ce_pix) begin
			if (!BIG_OSD) begin
				osd_buffer_addr <= (rotate[0] ? {(rotate[1] ? osd_hcnt_next[7:5] : ~osd_hcnt_next[7:5]), (rotate[1] ? (doublescan ? ~osd_vcnt[7:0] : ~{osd_vcnt[6:0], 1'b0}) : (doublescan ? osd_vcnt[7:0] : {osd_vcnt[6:0], 1'b0}))} : {(doublescan ? osd_vcnt[7:5] : osd_vcnt[6:4]), osd_hcnt_next[7:0]});
				osd_pixel <= (rotate[0] ? osd_byte[(rotate[1] ? osd_hcnt[4:2] : ~osd_hcnt[4:2])] : osd_byte[(doublescan ? osd_vcnt[4:2] : osd_vcnt[3:1])]);
			end
			else begin
				osd_buffer_addr <= (rotate[0] ? {(rotate[1] ? osd_hcnt_next[7:4] : ~osd_hcnt_next[7:4]), (rotate[1] ? (doublescan ? ~osd_vcnt[7:0] : ~{osd_vcnt[6:0], 1'b0}) : (doublescan ? osd_vcnt[7:0] : {osd_vcnt[6:0], 1'b0}))} : {(doublescan ? osd_vcnt[7:4] : osd_vcnt[6:3]), osd_hcnt_next[7:0]});
				osd_pixel <= (rotate[0] ? osd_byte[(rotate[1] ? osd_hcnt[3:1] : ~osd_hcnt[3:1])] : osd_byte[(doublescan ? osd_vcnt[3:1] : osd_vcnt[2:0])]);
			end
//			osd_de <= (((((((USE_BLANKS && !HBlank) || (!USE_BLANKS && (HSync != hs_pol)))) && (h_cnt >= h_osd_start)) && (h_cnt < h_osd_end)) && ((USE_BLANKS && !VBlank) || (!USE_BLANKS && (VSync != vs_pol)))) && (v_cnt >= v_osd_start)) && (v_cnt < v_osd_end);
			osd_de <= (((((osd_enable && ((USE_BLANKS && !HBlank) || (!USE_BLANKS && (HSync != hs_pol)))) && (h_cnt >= h_osd_start)) && (h_cnt < h_osd_end)) && ((USE_BLANKS && !VBlank) || (!USE_BLANKS && (VSync != vs_pol)))) && (v_cnt >= v_osd_start)) && (v_cnt < v_osd_end);
		end
	assign R_out = (!osd_de ? R_in : {osd_pixel, osd_pixel, OSD_COLOR[2], R_in[OUT_COLOR_DEPTH - 1:3]});
	assign G_out = (!osd_de ? G_in : {osd_pixel, osd_pixel, OSD_COLOR[1], G_in[OUT_COLOR_DEPTH - 1:3]});
	assign B_out = (!osd_de ? B_in : {osd_pixel, osd_pixel, OSD_COLOR[0], B_in[OUT_COLOR_DEPTH - 1:3]});
endmodule
