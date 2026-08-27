`timescale 1ns / 1ps

module fft8_pl (
    input  wire         clk,
    input  wire         rst,
    input  wire         start,
    input  wire [127:0] in_re,
    input  wire [127:0] in_im,
    output wire [127:0] out_re,
    output wire [127:0] out_im,
    output reg          done
);
    reg [127:0] r0_re, r0_im;   
    reg [127:0] r1_re, r1_im;   
    reg [127:0] r2_re, r2_im;   
    reg [127:0] r3_re, r3_im;   
    reg [2:0]   vpipe;          

    wire [127:0] s1_re, s1_im, s2_re, s2_im, s3_re, s3_im;

    fft8_stage1 u_s1 (.in_re(r0_re), .in_im(r0_im), .out_re(s1_re), .out_im(s1_im));
    fft8_stage2 u_s2 (.in_re(r1_re), .in_im(r1_im), .out_re(s2_re), .out_im(s2_im));
    fft8_stage3 u_s3 (.in_re(r2_re), .in_im(r2_im), .out_re(s3_re), .out_im(s3_im));

    always @(posedge clk) begin
        if (rst) begin
            r0_re <= 128'd0; r0_im <= 128'd0;
            r1_re <= 128'd0; r1_im <= 128'd0;
            r2_re <= 128'd0; r2_im <= 128'd0;
            r3_re <= 128'd0; r3_im <= 128'd0;
            vpipe <= 3'd0;
            done  <= 1'b0;
        end else begin
            if (start) begin
                r0_re <= in_re;
                r0_im <= in_im;
            end
            r1_re <= s1_re;  r1_im <= s1_im;   
            r2_re <= s2_re;  r2_im <= s2_im;   
            r3_re <= s3_re;  r3_im <= s3_im;   
            vpipe <= {vpipe[1:0], start};
            done  <= vpipe[2];
        end
    end

    assign out_re = r3_re;
    assign out_im = r3_im;
endmodule
