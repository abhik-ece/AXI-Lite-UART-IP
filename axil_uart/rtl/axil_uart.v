
module axil_uart (
    input         clk,
    input         rst_n,               

    input  [7:0]  s_axil_awaddr,
    input         s_axil_awvalid,
    output        s_axil_awready,
    input  [31:0] s_axil_wdata,
    input  [3:0]  s_axil_wstrb,
    input         s_axil_wvalid,
    output        s_axil_wready,
    output [1:0]  s_axil_bresp,
    output        s_axil_bvalid,
    input         s_axil_bready,
    input  [7:0]  s_axil_araddr,
    input         s_axil_arvalid,
    output        s_axil_arready,
    output [31:0] s_axil_rdata,
    output [1:0]  s_axil_rresp,
    output        s_axil_rvalid,
    input         s_axil_rready,

    input         uart_rxd,
    output        uart_txd,

    output        irq
);
   
    wire        tx_en, rx_en, par_en, par_odd, stop2, loopback;
    wire [15:0] div_cfg;
    wire        tx_push, tx_flush, rx_flush, rx_pop;
    wire [7:0]  tx_wdata;

    wire [15:0] div = (div_cfg < 16'd8) ? 16'd8 : div_cfg;

 
    wire        txf_full, txf_empty, txf_pop;
    wire [7:0]  txf_rdata;
    wire [4:0]  txf_level;
    wire        txd_int, tx_busy, tx_frame_done;

    sync_fifo #(.WIDTH(8), .AW(4)) tx_fifo (
        .clk(clk), .rst_n(rst_n), .clr(tx_flush),
        .push(tx_push), .wdata(tx_wdata),
        .pop(txf_pop), .rdata(txf_rdata),
        .full(txf_full), .empty(txf_empty), .level(txf_level)
    );

    uart_tx u_tx (
        .clk(clk), .rst_n(rst_n), .en(tx_en), .div(div),
        .par_en(par_en), .par_odd(par_odd), .stop2(stop2),
        .fifo_empty(txf_empty), .fifo_data(txf_rdata), .fifo_pop(txf_pop),
        .txd(txd_int), .busy(tx_busy), .frame_done(tx_frame_done)
    );

    assign uart_txd = txd_int;


    wire        rxd_int = loopback ? txd_int : uart_rxd;
    wire        rx_valid, rx_perr, rx_ferr, rx_busy;
    wire [7:0]  rx_data;

    uart_rx u_rx (
        .clk(clk), .rst_n(rst_n), .en(rx_en), .div(div),
        .par_en(par_en), .par_odd(par_odd), .rxd(rxd_int),
        .valid(rx_valid), .data(rx_data), .perr(rx_perr), .ferr(rx_ferr),
        .busy(rx_busy)
    );

    wire        rxf_full, rxf_empty;
    wire [9:0]  rxf_rdata;
    wire [4:0]  rxf_level;
    wire        rx_push = rx_valid && !rxf_full;

    sync_fifo #(.WIDTH(10), .AW(4)) rx_fifo (
        .clk(clk), .rst_n(rst_n), .clr(rx_flush),
        .push(rx_valid), .wdata({rx_ferr, rx_perr, rx_data}),
        .pop(rx_pop), .rdata(rxf_rdata),
        .full(rxf_full), .empty(rxf_empty), .level(rxf_level)
    );
    
    axil_uart_regs #(.AW(8)) regs (
        .clk(clk), .rst_n(rst_n),
        .awaddr(s_axil_awaddr), .awvalid(s_axil_awvalid), .awready(s_axil_awready),
        .wdata(s_axil_wdata), .wstrb(s_axil_wstrb), .wvalid(s_axil_wvalid), .wready(s_axil_wready),
        .bresp(s_axil_bresp), .bvalid(s_axil_bvalid), .bready(s_axil_bready),
        .araddr(s_axil_araddr), .arvalid(s_axil_arvalid), .arready(s_axil_arready),
        .rdata(s_axil_rdata), .rresp(s_axil_rresp), .rvalid(s_axil_rvalid), .rready(s_axil_rready),

        .tx_en(tx_en), .rx_en(rx_en), .par_en(par_en), .par_odd(par_odd),
        .stop2(stop2), .loopback(loopback), .div(div_cfg),

        .tx_push(tx_push), .tx_wdata(tx_wdata), .tx_flush(tx_flush),
        .rx_flush(rx_flush), .rx_pop(rx_pop),

        .tx_full(txf_full), .tx_empty(txf_empty), .rx_full(rxf_full), .rx_empty(rxf_empty),
        .tx_busy(tx_busy), .rx_busy(rx_busy), .rx_rdata(rxf_rdata),
        .tx_level(txf_level), .rx_level(rxf_level),

        .ev_tx_done   (tx_frame_done && txf_empty),
        .ev_rx_done   (rx_push),
        .ev_rx_overrun(rx_valid && rxf_full),
        .ev_perr      (rx_push && rx_perr),
        .ev_ferr      (rx_push && rx_ferr),

        .irq(irq)
    );
endmodule
