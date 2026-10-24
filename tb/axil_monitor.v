`timescale 1ns/1ps
module axil_monitor #(
    parameter AW      = 8,
    parameter TIMEOUT = 200
) (
    input             clk,
    input             rst_n,
    input  [AW-1:0]   awaddr,
    input             awvalid,
    input             awready,
    input  [31:0]     wdata,
    input  [3:0]      wstrb,
    input             wvalid,
    input             wready,
    input  [1:0]      bresp,
    input             bvalid,
    input             bready,
    input  [AW-1:0]   araddr,
    input             arvalid,
    input             arready,
    input  [31:0]     rdata,
    input  [1:0]      rresp,
    input             rvalid,
    input             rready,
    output reg [31:0] errors
);
    reg         aw_pend, w_pend, ar_pend, b_pend, r_pend;
    reg [AW-1:0] awaddr_p, araddr_p;
    reg [31:0]  wdata_p, rdata_p;
    reg [3:0]   wstrb_p;
    reg [1:0]   bresp_p, rresp_p;
    integer     aw_cnt, w_cnt, b_cnt, ar_cnt, r_cnt;
    integer     wr_wait, rd_wait;

    initial errors = 0;

    task err;
        input [8*48-1:0] msg;
        begin
            errors = errors + 1;
            $display("[%0t] AXI MONITOR ERROR: %0s", $time, msg);
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_pend <= 0; w_pend <= 0; ar_pend <= 0; b_pend <= 0; r_pend <= 0;
            aw_cnt = 0; w_cnt = 0; b_cnt = 0; ar_cnt = 0; r_cnt = 0;
            wr_wait = 0; rd_wait = 0;
        end else begin
            if ((^{awvalid, awready, wvalid, wready, bvalid, bready,
                   arvalid, arready, rvalid, rready}) === 1'bx)
                err("X/Z on a handshake signal");

            if (aw_pend && !(awvalid && awaddr == awaddr_p))
                err("AW changed or dropped before ready");
            if (w_pend && !(wvalid && wdata == wdata_p && wstrb == wstrb_p))
                err("W changed or dropped before ready");
            if (ar_pend && !(arvalid && araddr == araddr_p))
                err("AR changed or dropped before ready");
            if (b_pend && !(bvalid && bresp == bresp_p))
                err("B changed or dropped before ready");
            if (r_pend && !(rvalid && rdata == rdata_p && rresp == rresp_p))
                err("R changed or dropped before ready");

            if (bvalid && !(aw_cnt > b_cnt && w_cnt > b_cnt))
                err("BVALID before AW and W were accepted");
            if (rvalid && !(ar_cnt > r_cnt))
                err("RVALID before AR was accepted");
            if (bvalid && bresp == 2'b01) err("EXOKAY on B");
            if (rvalid && rresp == 2'b01) err("EXOKAY on R");

            if ((aw_cnt != b_cnt || w_cnt != b_cnt) && !bvalid) wr_wait = wr_wait + 1;
            else wr_wait = 0;
            if (ar_cnt != r_cnt && !rvalid) rd_wait = rd_wait + 1;
            else rd_wait = 0;
            if (wr_wait > TIMEOUT) begin err("write response timeout"); wr_wait = 0; end
            if (rd_wait > TIMEOUT) begin err("read response timeout");  rd_wait = 0; end

            aw_pend <= awvalid && !awready;  awaddr_p <= awaddr;
            w_pend  <= wvalid  && !wready;   wdata_p  <= wdata;  wstrb_p <= wstrb;
            ar_pend <= arvalid && !arready;  araddr_p <= araddr;
            b_pend  <= bvalid  && !bready;   bresp_p  <= bresp;
            r_pend  <= rvalid  && !rready;   rdata_p  <= rdata;  rresp_p <= rresp;

            if (awvalid && awready) aw_cnt = aw_cnt + 1;
            if (wvalid  && wready)  w_cnt  = w_cnt  + 1;
            if (bvalid  && bready)  b_cnt  = b_cnt  + 1;
            if (arvalid && arready) ar_cnt = ar_cnt + 1;
            if (rvalid  && rready)  r_cnt  = r_cnt  + 1;
        end
    end
endmodule
