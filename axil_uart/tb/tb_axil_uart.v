`timescale 1ns/1ps
module tb_axil_uart;
    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    always #5 clk = ~clk;

    reg  [7:0]  awaddr = 0;  reg awvalid = 0;  wire awready;
    reg  [31:0] wdata  = 0;  reg [3:0] wstrb = 0;  reg wvalid = 0;  wire wready;
    wire [1:0]  bresp;       wire bvalid;      reg bready = 0;
    reg  [7:0]  araddr = 0;  reg arvalid = 0;  wire arready;
    wire [31:0] rdata;       wire [1:0] rresp; wire rvalid;  reg rready = 0;

    reg         rxd_pin = 1'b1;
    wire        txd_pin;
    wire        irq;

    axil_uart dut (
        .clk(clk), .rst_n(rst_n),
        .s_axil_awaddr(awaddr), .s_axil_awvalid(awvalid), .s_axil_awready(awready),
        .s_axil_wdata(wdata), .s_axil_wstrb(wstrb), .s_axil_wvalid(wvalid), .s_axil_wready(wready),
        .s_axil_bresp(bresp), .s_axil_bvalid(bvalid), .s_axil_bready(bready),
        .s_axil_araddr(araddr), .s_axil_arvalid(arvalid), .s_axil_arready(arready),
        .s_axil_rdata(rdata), .s_axil_rresp(rresp), .s_axil_rvalid(rvalid), .s_axil_rready(rready),
        .uart_rxd(rxd_pin), .uart_txd(txd_pin), .irq(irq)
    );

    wire [31:0] mon_errors;
    axil_monitor #(.AW(8)) mon (
        .clk(clk), .rst_n(rst_n),
        .awaddr(awaddr), .awvalid(awvalid), .awready(awready),
        .wdata(wdata), .wstrb(wstrb), .wvalid(wvalid), .wready(wready),
        .bresp(bresp), .bvalid(bvalid), .bready(bready),
        .araddr(araddr), .arvalid(arvalid), .arready(arready),
        .rdata(rdata), .rresp(rresp), .rvalid(rvalid), .rready(rready),
        .errors(mon_errors)
    );

    localparam A_CTRL = 8'h00, A_DIV = 8'h04, A_STATUS = 8'h08, A_TXDATA = 8'h0C,
               A_RXDATA = 8'h10, A_IRQ_EN = 8'h14, A_IRQ_ST = 8'h18, A_LEVEL = 8'h1C;

    localparam [1:0] OKAY = 2'b00, SLVERR = 2'b10;
    integer errors = 0;
    integer seed   = 1;
    reg     rand_gaps = 1'b0;

    function integer rnd;
        input integer n;
        begin
            rnd = {$random(seed)} % n;
        end
    endfunction

    task fail;
        input [8*56-1:0] msg;
        begin
            errors = errors + 1;
            $display("[%0t] ERROR: %0s", $time, msg);
        end
    endtask

    task check;
        input [8*40-1:0] what;
        input [31:0]     got;
        input [31:0]     exp;
        begin
            if (got !== exp) begin
                errors = errors + 1;
                $display("[%0t] ERROR: %0s: got 0x%08h, expected 0x%08h", $time, what, got, exp);
            end
        end
    endtask
    integer cv_div_min = 0, cv_div_odd = 0, cv_div_big = 0;
    integer cv_par_none = 0, cv_par_even = 0, cv_par_odd = 0;
    integer cv_stop1 = 0, cv_stop2 = 0;
    integer cv_tx_full = 0, cv_rx_full = 0, cv_rx_overrun = 0, cv_tx_overflow = 0;
    integer cv_perr = 0, cv_ferr = 0, cv_break = 0, cv_glitch = 0;
    integer cv_slverr_wr = 0, cv_slverr_rd = 0, cv_irq = 0, cv_loop = 0;
    integer cv_flush_tx = 0, cv_flush_rx = 0, cv_reset_busy = 0, cv_tol = 0;
    integer cv_window = 0, cv_clamp = 0;
    integer cv_wstrb_part = 0, cv_aw_before_w = 0, cv_w_before_aw = 0;

    task axi_write;
        input  [7:0]  a;
        input  [31:0] d;
        input  [3:0]  s;
        output [1:0]  resp;
        integer da, dw;
        begin
            da = rand_gaps ? rnd(4) : 0;
            dw = rand_gaps ? rnd(4) : 0;
            if (da < dw) cv_aw_before_w = cv_aw_before_w + 1;
            if (dw < da) cv_w_before_aw = cv_w_before_aw + 1;
            fork
                begin
                    repeat (da) @(posedge clk);
                    awaddr <= a; awvalid <= 1'b1;
                    @(posedge clk);
                    while (!awready) @(posedge clk);
                    awvalid <= 1'b0;
                end
                begin
                    repeat (dw) @(posedge clk);
                    wdata <= d; wstrb <= s; wvalid <= 1'b1;
                    @(posedge clk);
                    while (!wready) @(posedge clk);
                    wvalid <= 1'b0;
                end
            join
            if (rand_gaps) repeat (rnd(4)) @(posedge clk);
            bready <= 1'b1;
            @(posedge clk);
            while (!bvalid) @(posedge clk);
            resp = bresp;
            bready <= 1'b0;
        end
    endtask

    task axi_read;
        input  [7:0]  a;
        output [31:0] d;
        output [1:0]  resp;
        begin
            if (rand_gaps) repeat (rnd(4)) @(posedge clk);
            araddr <= a; arvalid <= 1'b1;
            @(posedge clk);
            while (!arready) @(posedge clk);
            arvalid <= 1'b0;
            if (rand_gaps) repeat (rnd(4)) @(posedge clk);
            rready <= 1'b1;
            @(posedge clk);
            while (!rvalid) @(posedge clk);
            d = rdata;
            resp = rresp;
            rready <= 1'b0;
        end
    endtask

    task wr;
        input [7:0]  a;
        input [31:0] d;
        reg   [1:0]  r;
        begin
            axi_write(a, d, 4'hF, r);
            if (r !== OKAY) fail("unexpected error response on write");
        end
    endtask
    task rd;
        input  [7:0]  a;
        output [31:0] d;
        reg    [1:0]  r;
        begin
            axi_read(a, d, r);
            if (r !== OKAY) fail("unexpected error response on read");
        end
    endtask

    task rd_check;
        input [8*40-1:0] what;
        input [7:0]  a;
        input [31:0] exp;
        reg   [31:0] d;
        begin
            rd(a, d);
            check(what, d, exp);
        end
    endtask
    reg     mon_abort = 1'b0;       
    reg     dec_busy  = 1'b0;       
    integer cfg_div     = 868;
    reg     cfg_par_en  = 0;
    reg     cfg_par_odd = 0;
    reg     cfg_stop2   = 0;

    task uart_cfg;
        input integer div;
        input         par_en;
        input         par_odd;
        input         stop2;
        input         loop;
        input         tx_en;
        input         rx_en;
        begin
            while (dec_busy) @(posedge clk);
            cfg_div = div; cfg_par_en = par_en; cfg_par_odd = par_odd; cfg_stop2 = stop2;
            wr(A_DIV, div);
            wr(A_CTRL, {24'd0, 2'b11, loop, stop2, par_odd, par_en, rx_en, tx_en});
            wr(A_IRQ_ST, 32'h3F);
            if (div == 8)       cv_div_min = cv_div_min + 1;
            else if (div > 100) cv_div_big = cv_div_big + 1;
            else if (div % 2)   cv_div_odd = cv_div_odd + 1;
            if (!par_en)        cv_par_none = cv_par_none + 1;
            else if (par_odd)   cv_par_odd = cv_par_odd + 1;
            else                cv_par_even = cv_par_even + 1;
            if (stop2) cv_stop2 = cv_stop2 + 1; else cv_stop1 = cv_stop1 + 1;
            if (loop) cv_loop = cv_loop + 1;
        end
    endtask
    reg [7:0] tx_obs [0:8191];
    integer   tx_cnt = 0;
    integer   tx_frame_errors = 0;

    initial begin : txd_decoder
        integer i, c, p, nbits;
        reg     prev, bitval, aborted, par_expect;
        reg [11:0] bits;
        reg     par_cfg_en, par_cfg_odd, stop_cfg;
        prev = 1'b1;
        forever begin
            @(posedge clk);
            if (prev === 1'b1 && txd_pin === 1'b0 && rst_n) begin
                p           = (cfg_div < 8) ? 8 : cfg_div;
                par_cfg_en  = cfg_par_en;
                par_cfg_odd = cfg_par_odd;
                stop_cfg    = cfg_stop2;
                nbits       = 10 + par_cfg_en + stop_cfg;
                aborted     = 1'b0;
                dec_busy    = 1'b1;
                bits        = 12'd0;
                for (i = 0; i < nbits && !aborted; i = i + 1) begin
                    for (c = 0; c < p && !aborted; c = c + 1) begin
                        if (!(i == 0 && c == 0)) @(posedge clk);
                        if (!rst_n || mon_abort) aborted = 1'b1;
                        if (c == 0) begin
                            bitval = txd_pin;
                            bits[i] = txd_pin;
                        end else if (txd_pin !== bitval && !aborted) begin
                            tx_frame_errors = tx_frame_errors + 1;
                            $display("[%0t] ERROR: txd bit %0d not stable for %0d clocks", $time, i, p);
                        end
                    end
                end
                if (!aborted) begin
                    par_expect = (^bits[8:1]) ^ par_cfg_odd;
                    if (bits[0] !== 1'b0) fail("tx start bit not 0");
                    if (par_cfg_en && bits[9] !== par_expect) fail("tx parity bit wrong");
                    if (bits[nbits-1] !== 1'b1) fail("tx stop bit not 1");
                    if (par_cfg_en && stop_cfg && bits[10] !== 1'b1) fail("tx first stop bit not 1");
                    tx_obs[tx_cnt % 8192] = bits[8:1];
                    tx_cnt = tx_cnt + 1;
                end
                dec_busy = 1'b0;
                prev = 1'b1;
            end else begin
                prev = txd_pin;
            end
        end
    end

    task uart_send;
        input [7:0]   d;
        input integer period; 
        input         bad_par;
        input         bad_stop;
        integer i;
        reg     pbit;
        begin
            rxd_pin <= 1'b0;       
            repeat (period) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                rxd_pin <= d[i];
                repeat (period) @(posedge clk);
            end
            if (cfg_par_en) begin
                pbit = (^d) ^ cfg_par_odd ^ bad_par;
                rxd_pin <= pbit;
                repeat (period) @(posedge clk);
            end
            rxd_pin <= bad_stop ? 1'b0 : 1'b1;
            repeat (period) @(posedge clk);
            if (cfg_stop2 && !bad_stop) repeat (period) @(posedge clk);
            rxd_pin <= 1'b1;
        end
    endtask
    task drive_bit_win;
        input         b;
        input integer period;
        input integer hw;
        input         tail_ok;
        begin
            rxd_pin <= ~b;
            repeat (period / 2 - hw) @(posedge clk);
            rxd_pin <= b;
            repeat (2 * hw) @(posedge clk);
            rxd_pin <= tail_ok ? b : ~b;
            repeat (period - period / 2 - hw) @(posedge clk);
        end
    endtask

    task uart_send_win;
        input [7:0]   d;
        input integer period;
        input integer hw;
        integer i;
        begin
            rxd_pin <= 1'b0;                                   
            repeat (period) @(posedge clk);
            for (i = 0; i < 8; i = i + 1)
                drive_bit_win(d[i], period, hw, 1'b0);
            if (cfg_par_en)
                drive_bit_win((^d) ^ cfg_par_odd, period, hw, 1'b0);
            drive_bit_win(1'b1, period, hw, 1'b1);             
            rxd_pin <= 1'b1;
        end
    endtask
    task wait_rx;
        input integer max_cycles;
        reg [31:0] st;
        integer n;
        begin
            n = 0;
            st = 32'h4;
            while (st[2] && n < max_cycles) begin
                rd(A_STATUS, st);
                n = n + 1;
            end
            if (st[2]) fail("timeout waiting for rx data");
        end
    endtask

    task rx_pop_char;
        output [9:0] c;
        reg [31:0] d;
        begin
            wait_rx(2000);
            rd(A_RXDATA, d);
            if (d[31]) fail("RXDATA flagged empty after wait");
            c = d[9:0];
        end
    endtask

    task wait_tx_frames;
        input integer base;
        input integer n;
        input integer max_cycles;
        integer k;
        begin
            k = 0;
            while ((tx_cnt - base) < n && k < max_cycles) begin
                @(posedge clk);
                k = k + 1;
            end
            if ((tx_cnt - base) < n) fail("timeout waiting for tx frames");
        end
    endtask

    task wait_tx_idle;
        reg [31:0] st;
        integer k;
        begin
            st = 32'h0;
            k = 0;
            while (!(st[0] && !st[4]) && k < 5000) begin
                rd(A_STATUS, st);
                k = k + 1;
            end
        end
    endtask
    reg [31:0] d;
    reg [1:0]  r;
    reg [9:0]  c;
    integer    i, j, k, base, n, di, pi, si, per;
    reg [7:0]  exp_q [0:1023];

    task test_reset_and_regs;
        begin
            $display("-- reset values and register access");
            rd_check("CTRL reset",       A_CTRL,   32'h0);
            rd_check("DIV reset",        A_DIV,    32'd868);
            rd_check("STATUS reset",     A_STATUS, 32'h5);          
            rd_check("RXDATA reset",     A_RXDATA, 32'h8000_0000); 
            rd_check("IRQ_EN reset",     A_IRQ_EN, 32'h0);
            rd_check("IRQ_STATUS reset", A_IRQ_ST, 32'h0);
            rd_check("LEVEL reset",      A_LEVEL,  32'h0);

            axi_read(A_TXDATA, d, r);
            check("TXDATA read resp", {30'd0, r}, {30'd0, SLVERR});
            check("TXDATA read data", d, 32'h0);
            cv_slverr_rd = cv_slverr_rd + 1;
            axi_write(A_DIV, 32'hABCD_1234, 4'hF, r);   check("DIV full wr resp", {30'd0, r}, 0);
            rd_check("DIV after full write", A_DIV, 32'h1234);
            axi_write(A_DIV, 32'h0000_00EF, 4'b0001, r);
            rd_check("DIV strb 0001", A_DIV, 32'h12EF);
            axi_write(A_DIV, 32'h0000_AB00, 4'b0010, r);
            rd_check("DIV strb 0010", A_DIV, 32'hABEF);
            axi_write(A_DIV, 32'hFFFF_0000, 4'b1100, r);
            rd_check("DIV strb 1100 (ignored)", A_DIV, 32'hABEF);
            axi_write(A_DIV, 32'h0000_FFFF, 4'b0000, r);
            rd_check("DIV strb 0000", A_DIV, 32'hABEF);
            cv_wstrb_part = cv_wstrb_part + 1;
            wr(A_CTRL, 32'hFF);
            rd_check("CTRL readback", A_CTRL, 32'h3F);
            wr(A_CTRL, 32'h0);
            wr(A_IRQ_EN, 32'hFFFF_FFFF);
            rd_check("IRQ_EN readback", A_IRQ_EN, 32'h3F);
            wr(A_IRQ_EN, 32'h0);
            axi_write(A_STATUS, 32'hFFFF_FFFF, 4'hF, r);
            check("STATUS write resp", {30'd0, r}, {30'd0, SLVERR});
            axi_write(A_RXDATA, 32'h1, 4'hF, r);
            check("RXDATA write resp", {30'd0, r}, {30'd0, SLVERR});
            axi_write(A_LEVEL,  32'h1, 4'hF, r);
            check("LEVEL write resp",  {30'd0, r}, {30'd0, SLVERR});
            cv_slverr_wr = cv_slverr_wr + 3;
            rd_check("STATUS unchanged", A_STATUS, 32'h5);
            axi_write(8'h20, 32'h1, 4'hF, r);  check("wr 0x20 resp", {30'd0, r}, {30'd0, SLVERR});
            axi_write(8'hFC, 32'h1, 4'hF, r);  check("wr 0xFC resp", {30'd0, r}, {30'd0, SLVERR});
            axi_write(8'h06, 32'h5555, 4'hF, r); check("wr 0x06 resp", {30'd0, r}, {30'd0, SLVERR});
            rd_check("DIV not hit by bad write", A_DIV, 32'hABEF);
            axi_read(8'h40, d, r);  check("rd 0x40 resp", {30'd0, r}, {30'd0, SLVERR});
            check("rd 0x40 data", d, 0);
            axi_read(8'h01, d, r);  check("rd 0x01 resp", {30'd0, r}, {30'd0, SLVERR});
            cv_slverr_wr = cv_slverr_wr + 3;
            cv_slverr_rd = cv_slverr_rd + 2;
        end
    endtask
    task test_tx_sweep;
        begin
            $display("-- tx sweep");
            for (di = 0; di < 4; di = di + 1) begin
                case (di)
                    0: per = 8;
                    1: per = 9;
                    2: per = 16;
                    default: per = 37;
                endcase
                for (pi = 0; pi < 3; pi = pi + 1) begin
                    for (si = 0; si < 2; si = si + 1) begin
                        uart_cfg(per, pi != 0, pi == 2, si == 1, 1'b0, 1'b1, 1'b0);
                        n = 1 + rnd(4);
                        base = tx_cnt;
                        for (i = 0; i < n; i = i + 1) begin
                            exp_q[i] = $random(seed);
                            wr(A_TXDATA, {24'd0, exp_q[i]});
                        end
                        wait_tx_frames(base, n, n * 14 * per + 400);
                        for (i = 0; i < n; i = i + 1)
                            check("tx byte", tx_obs[(base + i) % 8192], exp_q[i]);
                        wait_tx_idle;
                        rd(A_IRQ_ST, d);
                        check("tx_done event", d & 32'h2, 32'h2);
                    end
                end
            end
        end
    endtask

    task test_rx_sweep;
        begin
            $display("-- rx sweep");
            for (di = 0; di < 4; di = di + 1) begin
                case (di)
                    0: per = 8;
                    1: per = 9;
                    2: per = 16;
                    default: per = 37;
                endcase
                for (pi = 0; pi < 3; pi = pi + 1) begin
                    for (si = 0; si < 2; si = si + 1) begin
                        uart_cfg(per, pi != 0, pi == 2, si == 1, 1'b0, 1'b0, 1'b1);
                        n = 1 + rnd(5);
                        for (i = 0; i < n; i = i + 1) begin
                            exp_q[i] = $random(seed);
                            uart_send(exp_q[i], per, 1'b0, 1'b0);
                            repeat (rnd(3)) @(posedge clk);        
                        end
                        for (i = 0; i < n; i = i + 1) begin
                            rx_pop_char(c);
                            check("rx data", c[7:0], exp_q[i]);
                            check("rx error flags", c[9:8], 0);
                        end
                        rd_check("rx fifo empty", A_RXDATA, 32'h8000_0000);
                    end
                end
            end
        end
    endtask

    task test_rx_errors;
        begin
            $display("-- rx error handling");
            uart_cfg(16, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1);

            uart_send(8'hA5, 16, 1'b1, 1'b0);                     
            rx_pop_char(c);
            check("perr data", c[7:0], 8'hA5);
            check("perr flags", c[9:8], 2'b01);
            rd(A_IRQ_ST, d); check("perr event", d & 32'h30, 32'h10);
            wr(A_IRQ_ST, 32'h3F);
            cv_perr = cv_perr + 1;

            uart_send(8'h3C, 16, 1'b0, 1'b1);                     
            rx_pop_char(c);
            check("ferr data", c[7:0], 8'h3C);
            check("ferr flags", c[9:8], 2'b10);
            rd(A_IRQ_ST, d); check("ferr event", d & 32'h30, 32'h20);
            wr(A_IRQ_ST, 32'h3F);
            cv_ferr = cv_ferr + 1;

            uart_send(8'h99, 16, 1'b0, 1'b0);                      
            rx_pop_char(c);
            check("recovery data", c[7:0], 8'h99);
            check("recovery flags", c[9:8], 0);

            rxd_pin <= 1'b0;
            repeat (16 * 30) @(posedge clk);
            rxd_pin <= 1'b1;
            repeat (16 * 4) @(posedge clk);
            rx_pop_char(c);
            check("break data", c[7:0], 8'h00);
            check("break ferr", c[9:8] & 2'b10, 2'b10);
            rd(A_LEVEL, d);
            check("break gave only one char", d[12:8], 0);
            wr(A_IRQ_ST, 32'h3F);
            cv_break = cv_break + 1;
            rxd_pin <= 1'b0;
            repeat (4) @(posedge clk);
            rxd_pin <= 1'b1;
            repeat (16 * 14) @(posedge clk);
            rd(A_LEVEL, d);
            check("glitch ignored", d[12:8], 0);
            cv_glitch = cv_glitch + 1;

            uart_send(8'h5A, 16, 1'b0, 1'b0);
            rx_pop_char(c);
            check("post-glitch data", c[7:0], 8'h5A);
        end
    endtask

    task test_fifos;
        begin
            $display("-- fifo full / overflow / overrun");
            uart_cfg(8, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1);
            for (i = 0; i < 16; i = i + 1) begin
                exp_q[i] = 8'h30 + i;
                wr(A_TXDATA, {24'd0, exp_q[i]});
            end
            rd(A_STATUS, d);  check("tx_full status", d[1], 1'b1);
            rd(A_LEVEL,  d);  check("tx level", d[4:0], 16);
            cv_tx_full = cv_tx_full + 1;
            rd(A_IRQ_ST, d);  check("no overflow yet", d & 32'h8, 0);
            wr(A_TXDATA, 32'hEE);
            rd(A_IRQ_ST, d);  check("tx overflow event", d & 32'h8, 32'h8);
            rd(A_LEVEL,  d);  check("tx level after overflow", d[4:0], 16);
            cv_tx_overflow = cv_tx_overflow + 1;
            base = tx_cnt;
            wr(A_CTRL, 32'h03);                                    
            wait_tx_frames(base, 16, 16 * 12 * 8 + 400);
            for (i = 0; i < 16; i = i + 1)
                check("tx fifo order", tx_obs[(base + i) % 8192], exp_q[i]);
            wait_tx_idle;
            repeat (5) @(posedge clk);
            rd(A_STATUS, d);  check("tx drained", d[1:0], 2'b01);
            wr(A_CTRL, 32'h02);

            wr(A_IRQ_ST, 32'h3F);
            for (i = 0; i < 17; i = i + 1) begin
                exp_q[i] = 8'hC0 + i;
                uart_send(exp_q[i], 8, 1'b0, 1'b0);
            end
            repeat (20) @(posedge clk);
            rd(A_STATUS, d);  check("rx_full status", d[3], 1'b1);
            rd(A_LEVEL,  d);  check("rx level", d[12:8], 16);
            rd(A_IRQ_ST, d);  check("rx overrun event", d & 32'h4, 32'h4);
            cv_rx_full = cv_rx_full + 1;
            cv_rx_overrun = cv_rx_overrun + 1;
            for (i = 0; i < 16; i = i + 1) begin
                rx_pop_char(c);
                check("rx fifo order", c[7:0], exp_q[i]);
            end
            rd_check("rx empty again", A_RXDATA, 32'h8000_0000);
            rd(A_STATUS, d);  check("rx_full cleared", d[3], 1'b0);
        end
    endtask

    task test_irq;
        begin
            $display("-- interrupts");
            uart_cfg(16, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1);
            check("irq idle", irq, 1'b0);
            uart_send(8'h42, 16, 1'b0, 1'b0);
            repeat (4) @(posedge clk);
            rd(A_IRQ_ST, d);  check("rx_done set", d & 32'h1, 32'h1);
            check("irq masked", irq, 1'b0);                         
            wr(A_IRQ_EN, 32'h1);
            repeat (2) @(posedge clk);
            check("irq asserted", irq, 1'b1);
            cv_irq = cv_irq + 1;
            wr(A_IRQ_ST, 32'h2);                                   
            wr(A_IRQ_ST, 32'h1);
            repeat (2) @(posedge clk);
            check("irq cleared by W1C", irq, 1'b0);
            rx_pop_char(c);
            check("irq test data", c[7:0], 8'h42);
            wr(A_IRQ_EN, 32'h2);
            wr(A_CTRL, 32'h03);
            base = tx_cnt;
            wr(A_TXDATA, 32'h77);
            k = 0;
            while (!irq && k < 400) begin @(posedge clk); k = k + 1; end
            check("tx_done irq", irq, 1'b1);
            wr(A_IRQ_ST, 32'h2);
            wr(A_IRQ_EN, 32'h0);
            wait_tx_idle;
            wr(A_IRQ_ST, 32'h3F);
            base = tx_cnt;
            wr(A_TXDATA, 32'h11);
            wr(A_TXDATA, 32'h22);
            wait_tx_frames(base, 1, 600);
            repeat (3) @(posedge clk);
            rd(A_IRQ_ST, d);  check("no tx_done with data queued", d & 32'h2, 0);
            wait_tx_frames(base, 2, 600);
            wait_tx_idle;
            rd(A_IRQ_ST, d);  check("tx_done after last frame", d & 32'h2, 32'h2);
        end
    endtask

    task test_div_clamp;
        begin
            $display("-- divider clamp");
            for (j = 0; j < 3; j = j + 1) begin
                per = (j == 0) ? 0 : (j == 1) ? 1 : 5;
                uart_cfg(per, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1);
                base = tx_cnt;
                wr(A_TXDATA, 32'hB4);
                uart_send(8'h2D, 8, 1'b0, 1'b0);
                wait_tx_frames(base, 1, 400);
                check("clamped tx", tx_obs[base % 8192], 8'hB4);
                rx_pop_char(c);
                check("clamped rx", c[7:0], 8'h2D);
                check("clamped rx flags", c[9:8], 0);
                cv_clamp = cv_clamp + 1;
            end
        end
    endtask

    task test_flush;
        begin
            $display("-- flush");
            uart_cfg(8, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1);
            for (i = 0; i < 5; i = i + 1) wr(A_TXDATA, 32'h10 + i);
            rd(A_LEVEL, d);  check("tx level before flush", d[4:0], 5);
            wr(A_CTRL, 32'h42);                                    
            rd(A_LEVEL, d);  check("tx level after flush", d[4:0], 0);
            rd(A_STATUS, d); check("tx_empty after flush", d[0], 1'b1);
            cv_flush_tx = cv_flush_tx + 1;
            for (i = 0; i < 3; i = i + 1) uart_send(8'h20 + i, 8, 1'b0, 1'b0);
            repeat (20) @(posedge clk);
            rd(A_LEVEL, d);  check("rx level before flush", d[12:8], 3);
            wr(A_CTRL, 32'h82);                                     
            rd(A_LEVEL, d);  check("rx level after flush", d[12:8], 0);
            cv_flush_rx = cv_flush_rx + 1;
        end
    endtask

    task test_loopback_random;
        input integer count;
        integer sent, got, inflight, guard;
        reg [7:0] data_q [0:511];
        reg [31:0] st;
        begin
            $display("-- loopback random (%0d bytes)", count);
            rand_gaps = 1'b1;
            per = 8 + rnd(24);
            pi  = rnd(3);
            si  = rnd(2);
            uart_cfg(per, pi != 0, pi == 2, si == 1, 1'b1, 1'b1, 1'b1);
            sent = 0; got = 0; guard = 0;
            while (got < count && guard < 400000) begin
                guard = guard + 1;
                inflight = sent - got;
                if (sent < count && inflight < 12 && rnd(2) == 0) begin
                    data_q[sent] = $random(seed);
                    wr(A_TXDATA, {24'd0, data_q[sent]});
                    sent = sent + 1;
                end else begin
                    rd(A_RXDATA, st);
                    if (!st[31]) begin
                        check("loopback data", st[7:0], data_q[got]);
                        check("loopback flags", st[9:8], 0);
                        got = got + 1;
                    end
                end
            end
            if (got < count) fail("loopback test timed out");
            rand_gaps = 1'b0;
        end
    endtask

    task test_sample_point;
        begin
            $display("-- rx sample point");
            for (j = 0; j < 2; j = j + 1) begin
                per = (j == 0) ? 16 : 40;
                uart_cfg(per, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1);
                for (i = 0; i < 4; i = i + 1) begin
                    exp_q[i] = $random(seed);
                    uart_send_win(exp_q[i], per, (j == 0) ? 2 : 4);
                    repeat (2) @(posedge clk);
                end
                for (i = 0; i < 4; i = i + 1) begin
                    rx_pop_char(c);
                    check("sample point data", c[7:0], exp_q[i]);
                    check("sample point flags", c[9:8], 0);
                end
                cv_window = cv_window + 1;
            end
        end
    endtask
    task test_large_div;
        begin
            $display("-- large divider");
            uart_cfg(300, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1);
            base = tx_cnt;
            wr(A_TXDATA, 32'hD2);
            uart_send(8'h6B, 300, 1'b0, 1'b0);
            wait_tx_frames(base, 1, 300 * 14);
            check("large div tx", tx_obs[base % 8192], 8'hD2);
            rx_pop_char(c);
            check("large div rx", c[7:0], 8'h6B);
            check("large div rx flags", c[9:8], 0);
        end
    endtask

    task test_baud_tolerance;
        begin
            $display("-- baud tolerance");
            uart_cfg(50, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1);
            for (j = 0; j < 2; j = j + 1) begin
                per = (j == 0) ? 49 : 51;  
                for (i = 0; i < 6; i = i + 1) begin
                    exp_q[i] = $random(seed);
                    uart_send(exp_q[i], per, 1'b0, 1'b0);
                    repeat (2) @(posedge clk);
                end
                for (i = 0; i < 6; i = i + 1) begin
                    rx_pop_char(c);
                    check("tolerance data", c[7:0], exp_q[i]);
                    check("tolerance flags", c[9:8], 0);
                end
                cv_tol = cv_tol + 1;
            end
        end
    endtask

    task test_reset_busy;
        begin
            $display("-- reset while busy");
            uart_cfg(16, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1);
            wr(A_TXDATA, 32'hA5);
            repeat (40) @(posedge clk);                             
            mon_abort = 1'b1;
            #3 rst_n = 1'b0;                                        
            #1 check("txd idle in reset", txd_pin, 1'b1);
            repeat (3) @(posedge clk);
            #2 rst_n = 1'b1;
            repeat (3) @(posedge clk);
            mon_abort = 1'b0;
            cv_reset_busy = cv_reset_busy + 1;
            rd_check("DIV back to default", A_DIV, 32'd868);
            rd_check("CTRL back to default", A_CTRL, 32'h0);
            rd_check("STATUS idle", A_STATUS, 32'h5);
            uart_cfg(16, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0);
            base = tx_cnt;
            wr(A_TXDATA, 32'h3C);
            wait_tx_frames(base, 1, 400);
            check("tx after reset", tx_obs[base % 8192], 8'h3C);
        end
    endtask

    integer holes = 0;
    task cov;
        input [8*24-1:0] name;
        input integer    hits;
        begin
            $display("  %-24s %0d%s", name, hits, (hits == 0) ? "   <-- NOT HIT" : "");
            if (hits == 0) holes = holes + 1;
        end
    endtask

    task coverage_report;
        begin
            $display("-- functional coverage");
            cov("div = 8 (minimum)", cv_div_min);
            cov("div odd", cv_div_odd);
            cov("div large", cv_div_big);
            cov("parity none", cv_par_none);
            cov("parity even", cv_par_even);
            cov("parity odd", cv_par_odd);
            cov("1 stop bit", cv_stop1);
            cov("2 stop bits", cv_stop2);
            cov("tx fifo full", cv_tx_full);
            cov("tx overflow", cv_tx_overflow);
            cov("rx fifo full", cv_rx_full);
            cov("rx overrun", cv_rx_overrun);
            cov("parity error", cv_perr);
            cov("framing error", cv_ferr);
            cov("break", cv_break);
            cov("glitch rejected", cv_glitch);
            cov("SLVERR on write", cv_slverr_wr);
            cov("SLVERR on read", cv_slverr_rd);
            cov("partial wstrb", cv_wstrb_part);
            cov("AW before W", cv_aw_before_w);
            cov("W before AW", cv_w_before_aw);
            cov("irq asserted", cv_irq);
            cov("loopback", cv_loop);
            cov("flush tx", cv_flush_tx);
            cov("flush rx", cv_flush_rx);
            cov("baud +-2%", cv_tol);
            cov("rx sample window", cv_window);
            cov("divider clamp", cv_clamp);
            cov("reset while busy", cv_reset_busy);
        end
    endtask


    initial begin
        if (!$value$plusargs("seed=%d", seed)) seed = 1;
        if ($test$plusargs("vcd")) begin
            $dumpfile("sim/wave.vcd");
            $dumpvars(0, tb_axil_uart);
        end
        $display("seed = %0d", seed);

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);

        test_reset_and_regs;
        test_tx_sweep;
        test_rx_sweep;
        test_rx_errors;
        test_fifos;
        test_irq;
        test_flush;
        test_loopback_random(80);
        test_loopback_random(80);
        test_loopback_random(80);
        test_sample_point;
        test_div_clamp;
        test_large_div;
        test_baud_tolerance;
        test_reset_busy;

        coverage_report;

        errors = errors + mon_errors + tx_frame_errors + holes;
        if (errors == 0)
            $display("TEST PASSED (%0d tx frames observed, %0d cycles)", tx_cnt, $time / 10);
        else
            $display("TEST FAILED: %0d error(s) (monitor %0d, tx timing %0d, coverage holes %0d)",
                     errors, mon_errors, tx_frame_errors, holes);
        $finish;
    end

    initial begin
        #200_000_000;
        $display("TEST FAILED: global timeout");
        $finish;
    end
endmodule
