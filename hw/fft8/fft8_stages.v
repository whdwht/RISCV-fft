`timescale 1ns / 1ps

module butterfly2 (
    input  signed [15:0] re0, im0,
    input  signed [15:0] re1, im1,
    output signed [15:0] ore0, oim0,
    output signed [15:0] ore1, oim1
);
    assign ore0 = re0 + re1;
    assign oim0 = im0 + im1;
    assign ore1 = re0 - re1;
    assign oim1 = im0 - im1;
endmodule


module fft8_stage1 (
    input  wire [127:0] in_re,
    input  wire [127:0] in_im,
    output wire [127:0] out_re,
    output wire [127:0] out_im
);
    wire signed [15:0] xr [0:7];
    wire signed [15:0] xi [0:7];
    wire signed [15:0] yr [0:7];
    wire signed [15:0] yi [0:7];

    genvar gi;
    generate
        for (gi = 0; gi < 8; gi = gi + 1) begin : sl
            assign xr[gi] = in_re[16*gi+15 : 16*gi];
            assign xi[gi] = in_im[16*gi+15 : 16*gi];
            assign out_re[16*gi+15 : 16*gi] = yr[gi];
            assign out_im[16*gi+15 : 16*gi] = yi[gi];
        end
    endgenerate

    butterfly2 b0 (.re0(xr[0]),.im0(xi[0]),.re1(xr[4]),.im1(xi[4]),.ore0(yr[0]),.oim0(yi[0]),.ore1(yr[1]),.oim1(yi[1]));
    butterfly2 b1 (.re0(xr[2]),.im0(xi[2]),.re1(xr[6]),.im1(xi[6]),.ore0(yr[2]),.oim0(yi[2]),.ore1(yr[3]),.oim1(yi[3]));
    butterfly2 b2 (.re0(xr[1]),.im0(xi[1]),.re1(xr[5]),.im1(xi[5]),.ore0(yr[4]),.oim0(yi[4]),.ore1(yr[5]),.oim1(yi[5]));
    butterfly2 b3 (.re0(xr[3]),.im0(xi[3]),.re1(xr[7]),.im1(xi[7]),.ore0(yr[6]),.oim0(yi[6]),.ore1(yr[7]),.oim1(yi[7]));
endmodule


module fft8_stage2 (
    input  wire [127:0] in_re,
    input  wire [127:0] in_im,
    output wire [127:0] out_re,
    output wire [127:0] out_im
);
    wire signed [15:0] xr [0:7];
    wire signed [15:0] xi [0:7];
    wire signed [15:0] temp_r [0:7];
    wire signed [15:0] temp_i [0:7];
    wire signed [15:0] yr [0:7];
    wire signed [15:0] yi [0:7];

    genvar gi;
    generate
        for (gi = 0; gi < 8; gi = gi + 1) begin : sl
            assign xr[gi] = in_re[16*gi+15 : 16*gi];
            assign xi[gi] = in_im[16*gi+15 : 16*gi];
            assign out_re[16*gi+15 : 16*gi] = yr[gi];
            assign out_im[16*gi+15 : 16*gi] = yi[gi];
        end
    endgenerate

    assign temp_r[0]=xr[0]; assign temp_i[0]=xi[0];
    assign temp_r[1]=xr[1]; assign temp_i[1]=xi[1];
    assign temp_r[2]=xr[2]; assign temp_i[2]=xi[2];       // W4^0 = 1
    assign temp_r[3]=xi[3]; assign temp_i[3]=-xr[3];      // W4^1 = -j
    assign temp_r[4]=xr[4]; assign temp_i[4]=xi[4];
    assign temp_r[5]=xr[5]; assign temp_i[5]=xi[5];
    assign temp_r[6]=xr[6]; assign temp_i[6]=xi[6];       // W4^0 = 1
    assign temp_r[7]=xi[7]; assign temp_i[7]=-xr[7];      // W4^1 = -j

    butterfly2 b0 (.re0(temp_r[0]),.im0(temp_i[0]),.re1(temp_r[2]),.im1(temp_i[2]),.ore0(yr[0]),.oim0(yi[0]),.ore1(yr[2]),.oim1(yi[2]));
    butterfly2 b1 (.re0(temp_r[1]),.im0(temp_i[1]),.re1(temp_r[3]),.im1(temp_i[3]),.ore0(yr[1]),.oim0(yi[1]),.ore1(yr[3]),.oim1(yi[3]));
    butterfly2 b2 (.re0(temp_r[4]),.im0(temp_i[4]),.re1(temp_r[6]),.im1(temp_i[6]),.ore0(yr[4]),.oim0(yi[4]),.ore1(yr[6]),.oim1(yi[6]));
    butterfly2 b3 (.re0(temp_r[5]),.im0(temp_i[5]),.re1(temp_r[7]),.im1(temp_i[7]),.ore0(yr[5]),.oim0(yi[5]),.ore1(yr[7]),.oim1(yi[7]));
endmodule


module fft8_stage3 (
    input  wire [127:0] in_re,
    input  wire [127:0] in_im,
    output wire [127:0] out_re,
    output wire [127:0] out_im
);

    // Match C signed division semantics used by the course golden model.
    // Arithmetic right shift rounds negative values toward -infinity, while
    // signed integer division by 1024 truncates toward zero.
    function automatic signed [15:0] q10_trunc_zero;
        input signed [31:0] value;
        reg signed [31:0] magnitude;
        begin
            if (value < 0) begin
                magnitude = -value;
                q10_trunc_zero = -(magnitude >>> 10);
            end else begin
                q10_trunc_zero = value >>> 10;
            end
        end
    endfunction


    wire signed [15:0] xr [0:7];
    wire signed [15:0] xi [0:7];
    wire signed [15:0] temp_r [0:7];
    wire signed [15:0] temp_i [0:7];
    wire signed [15:0] yr [0:7];
    wire signed [15:0] yi [0:7];

    genvar gi;
    generate
        for (gi = 0; gi < 8; gi = gi + 1) begin : sl
            assign xr[gi] = in_re[16*gi+15 : 16*gi];
            assign xi[gi] = in_im[16*gi+15 : 16*gi];
            assign out_re[16*gi+15 : 16*gi] = yr[gi];
            assign out_im[16*gi+15 : 16*gi] = yi[gi];
        end
    endgenerate

    assign temp_r[0]=xr[0]; assign temp_i[0]=xi[0];
    assign temp_r[1]=xr[1]; assign temp_i[1]=xi[1];
    assign temp_r[2]=xr[2]; assign temp_i[2]=xi[2];
    assign temp_r[3]=xr[3]; assign temp_i[3]=xi[3];
    assign temp_r[4]=xr[4]; assign temp_i[4]=xi[4];       // W8^0 = 1

    // W8^1
    wire signed [16:0] sum_5r = xr[5] + xi[5];
    wire signed [16:0] sum_5i = xi[5] - xr[5];
    wire signed [31:0] product_5r = 32'sd724 * sum_5r;
    wire signed [31:0] product_5i = 32'sd724 * sum_5i;
    assign temp_r[5] = q10_trunc_zero(product_5r);
    assign temp_i[5] = q10_trunc_zero(product_5i);

    assign temp_r[6]=xi[6]; assign temp_i[6]=-xr[6];      // W8^2 = -j

    // W8^3
    wire signed [16:0] sum_7r = xi[7] - xr[7];
    wire signed [16:0] sum_7i = -xr[7] - xi[7];
    wire signed [31:0] product_7r = 32'sd724 * sum_7r;
    wire signed [31:0] product_7i = 32'sd724 * sum_7i;
    assign temp_r[7] = q10_trunc_zero(product_7r);
    assign temp_i[7] = q10_trunc_zero(product_7i);

    butterfly2 b0 (.re0(temp_r[0]),.im0(temp_i[0]),.re1(temp_r[4]),.im1(temp_i[4]),.ore0(yr[0]),.oim0(yi[0]),.ore1(yr[4]),.oim1(yi[4]));
    butterfly2 b1 (.re0(temp_r[1]),.im0(temp_i[1]),.re1(temp_r[5]),.im1(temp_i[5]),.ore0(yr[1]),.oim0(yi[1]),.ore1(yr[5]),.oim1(yi[5]));
    butterfly2 b2 (.re0(temp_r[2]),.im0(temp_i[2]),.re1(temp_r[6]),.im1(temp_i[6]),.ore0(yr[2]),.oim0(yi[2]),.ore1(yr[6]),.oim1(yi[6]));
    butterfly2 b3 (.re0(temp_r[3]),.im0(temp_i[3]),.re1(temp_r[7]),.im1(temp_i[7]),.ore0(yr[3]),.oim0(yi[3]),.ore1(yr[7]),.oim1(yi[7]));
endmodule
