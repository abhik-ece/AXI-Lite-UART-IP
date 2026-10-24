module axil_uart_regs #(
    parameter AW = 8
)(
    input             clk,
    input             rst_n,

    input  [AW-1:0]   awaddr,
    input             awvalid,
    output            awready,
    input  [31:0]     wdata,
    input  [3:0]      wstrb,
    input             wvalid,
    output            wready,
    output [1:0]      bresp,
    output            bvalid,
    input             bready,
    input  [AW-1:0]   araddr,
    input             arvalid,
    output            arready,
    output [31:0]     rdata,
    output [1:0]      rresp,
    output            rvalid,
    input             rready,
    output            tx_en,
    output            rx_en,
    output            par_en,
    output            par_odd,
    output            stop2,
    output            loopback,
    output [15:0]     div,

    output            tx_push,
    output [7:0]      tx_wdata,
    output            tx_flush,
    output            rx_flush,
    output            rx_pop,

    input             tx_full,
    input             tx_empty,
    input             rx_full,
    input             rx_empty,
    input             tx_busy,
    input             rx_busy,
    input  [9:0]      rx_rdata, 
    input  [4:0]      tx_level,
    input  [4:0]      rx_level,

    input             ev_tx_done,
    input             ev_rx_done,
    input             ev_rx_overrun,
    input             ev_perr,
    input             ev_ferr,

    output            irq
);
    localparam [2:0] R_CTRL = 3'd0, R_DIV = 3'd1, R_STATUS = 3'd2, R_TXDATA = 3'd3,
                     R_RXDATA = 3'd4, R_IRQ_EN = 3'd5, R_IRQ_STATUS = 3'd6, R_LEVEL = 3'd7;

    localparam [1:0] RESP_OKAY = 2'b00, RESP_SLVERR = 2'b10;

   
    reg [5:0]  ctrl;
    reg [15:0] div_r;
    reg [5:0]  irq_en;
    reg [5:0]  irq_status;

    assign tx_en    = ctrl[0];
    assign rx_en    = ctrl[1];
    assign par_en   = ctrl[2];
    assign par_odd  = ctrl[3];
    assign stop2    = ctrl[4];
    assign loopback = ctrl[5];
    assign div      = div_r;

    assign irq = |(irq_status & irq_en);

    wire unused_ok = &{1'b0, wdata[31:16], wstrb[3:2]};

   
    reg         aw_got, w_got, bvalid_r;
    reg [AW-1:0] awaddr_q;
    reg [15:0]  wdata_q;   
    reg [1:0]   wstrb_q;
    reg [1:0]   bresp_r;

    assign awready = !aw_got && !bvalid_r;
    assign wready  = !w_got  && !bvalid_r;
    assign bvalid  = bvalid_r;
    assign bresp   = bresp_r;

    wire do_write = aw_got && w_got && !bvalid_r;

    wire [2:0] widx    = awaddr_q[4:2];
    wire       w_inmap = (awaddr_q[AW-1:5] == 0) && (awaddr_q[1:0] == 2'b00);
    wire       w_ro    = (widx == R_STATUS) || (widx == R_RXDATA) || (widx == R_LEVEL);
    wire       w_ok    = w_inmap && !w_ro;

    wire wr_ctrl   = do_write && w_ok && (widx == R_CTRL)       && wstrb_q[0];
    wire wr_div_lo = do_write && w_ok && (widx == R_DIV)        && wstrb_q[0];
    wire wr_div_hi = do_write && w_ok && (widx == R_DIV)        && wstrb_q[1];
    wire wr_tx     = do_write && w_ok && (widx == R_TXDATA)     && wstrb_q[0];
    wire wr_irqen  = do_write && w_ok && (widx == R_IRQ_EN)     && wstrb_q[0];
    wire wr_irqclr = do_write && w_ok && (widx == R_IRQ_STATUS) && wstrb_q[0];

    assign tx_push  = wr_tx;
    assign tx_wdata = wdata_q[7:0];
    assign tx_flush = wr_ctrl && wdata_q[6];
    assign rx_flush = wr_ctrl && wdata_q[7];

    wire ev_tx_overflow = wr_tx && tx_full;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_got   <= 1'b0;
            w_got    <= 1'b0;
            bvalid_r <= 1'b0;
            bresp_r  <= RESP_OKAY;
            awaddr_q <= {AW{1'b0}};
            wdata_q  <= 16'd0;
            wstrb_q  <= 2'd0;
        end else begin
            if (awvalid && awready) begin
                aw_got   <= 1'b1;
                awaddr_q <= awaddr;
            end
            if (wvalid && wready) begin
                w_got   <= 1'b1;
                wdata_q <= wdata[15:0];
                wstrb_q <= wstrb[1:0];
            end
            if (do_write) begin
                aw_got   <= 1'b0;
                w_got    <= 1'b0;
                bvalid_r <= 1'b1;
                bresp_r  <= w_ok ? RESP_OKAY : RESP_SLVERR;
            end
            if (bvalid_r && bready)
                bvalid_r <= 1'b0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl   <= 6'd0;
            div_r  <= 16'd868;           
            irq_en <= 6'd0;
        end else begin
            if (wr_ctrl)   ctrl <= wdata_q[5:0];
            if (wr_div_lo) div_r[7:0]  <= wdata_q[7:0];
            if (wr_div_hi) div_r[15:8] <= wdata_q[15:8];
            if (wr_irqen)  irq_en <= wdata_q[5:0];
        end
    end


    wire [5:0] ev_set = {ev_ferr, ev_perr, ev_tx_overflow, ev_rx_overrun, ev_tx_done, ev_rx_done};
    wire [5:0] ev_clr = wr_irqclr ? wdata_q[5:0] : 6'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) irq_status <= 6'd0;
        else        irq_status <= (irq_status & ~ev_clr) | ev_set;
    end

    reg         rvalid_r;
    reg [31:0]  rdata_r;
    reg [1:0]   rresp_r;

    assign arready = !rvalid_r;
    assign rvalid  = rvalid_r;
    assign rdata   = rdata_r;
    assign rresp   = rresp_r;

    wire [2:0] ridx    = araddr[4:2];
    wire       r_inmap = (araddr[AW-1:5] == 0) && (araddr[1:0] == 2'b00);
    wire       r_ok    = r_inmap && (ridx != R_TXDATA);
    wire       ar_hs   = arvalid && arready;

    assign rx_pop = ar_hs && r_inmap && (ridx == R_RXDATA) && !rx_empty;

    reg [31:0] rd_mux;
    always @(*) begin
        case (ridx)
            R_CTRL:       rd_mux = {26'd0, ctrl};
            R_DIV:        rd_mux = {16'd0, div_r};
            R_STATUS:     rd_mux = {26'd0, rx_busy, tx_busy, rx_full, rx_empty, tx_full, tx_empty};
            R_RXDATA:     rd_mux = rx_empty ? 32'h8000_0000 : {22'd0, rx_rdata};
            R_IRQ_EN:     rd_mux = {26'd0, irq_en};
            R_IRQ_STATUS: rd_mux = {26'd0, irq_status};
            R_LEVEL:      rd_mux = {19'd0, rx_level, 3'd0, tx_level};
            default:      rd_mux = 32'd0;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rvalid_r <= 1'b0;
            rdata_r  <= 32'd0;
            rresp_r  <= RESP_OKAY;
        end else begin
            if (ar_hs) begin
                rvalid_r <= 1'b1;
                rdata_r  <= r_ok ? rd_mux : 32'd0;
                rresp_r  <= r_ok ? RESP_OKAY : RESP_SLVERR;
            end else if (rvalid_r && rready) begin
                rvalid_r <= 1'b0;
            end
        end
    end
endmodule
