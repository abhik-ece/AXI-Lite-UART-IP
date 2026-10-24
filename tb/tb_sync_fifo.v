`timescale 1ns/1ps
module tb_sync_fifo;
    localparam W = 8, AW = 3, DEPTH = 8;

    reg          clk = 0, rst_n = 0;
    reg          clr = 0, push = 0, pop = 0;
    reg  [W-1:0] wdata = 0;
    wire [W-1:0] rdata;
    wire         full, empty;
    wire [AW:0]  level;

    sync_fifo #(.WIDTH(W), .AW(AW)) dut (
        .clk(clk), .rst_n(rst_n), .clr(clr), .push(push), .wdata(wdata),
        .pop(pop), .rdata(rdata), .full(full), .empty(empty), .level(level)
    );

    always #5 clk = ~clk;

    reg [W-1:0] model [0:DEPTH-1];
    integer m_rd = 0, m_cnt = 0;
    integer errors = 0, cycle = 0, seed = 1;
    integer p_push = 50, p_pop = 50;
    integer hit_full = 0, hit_empty = 0, hit_pop_empty = 0, hit_push_full = 0, hit_clr_push = 0;
    reg     do_push, do_pop;

    always @(negedge clk) begin
        cycle = cycle + 1;
        if (cycle % 400 == 0) begin             
            case (({$random(seed)}) % 4)
                0: begin p_push = 80; p_pop = 20; end
                1: begin p_push = 20; p_pop = 80; end
                2: begin p_push = 50; p_pop = 50; end
                default: begin p_push = 95; p_pop = 95; end
            endcase
        end
        push  = ({$random(seed)} % 100) < p_push;
        pop   = ({$random(seed)} % 100) < p_pop;
        clr   = ({$random(seed)} % 200) == 0;
        wdata = $random(seed);
    end
    always @(posedge clk) begin
        if (rst_n) begin
            if (level !== m_cnt[AW:0]) begin
                errors = errors + 1; $display("[%0t] level %0d, model %0d", $time, level, m_cnt);
            end
            if (full !== (m_cnt == DEPTH)) begin
                errors = errors + 1; $display("[%0t] full flag wrong", $time);
            end
            if (empty !== (m_cnt == 0)) begin
                errors = errors + 1; $display("[%0t] empty flag wrong", $time);
            end
            if (m_cnt != 0 && rdata !== model[m_rd % DEPTH]) begin
                errors = errors + 1;
                $display("[%0t] rdata %h, model %h", $time, rdata, model[m_rd % DEPTH]);
            end

            if (m_cnt == DEPTH) hit_full = hit_full + 1;
            if (m_cnt == 0)     hit_empty = hit_empty + 1;
            if (pop  && m_cnt == 0)     hit_pop_empty = hit_pop_empty + 1;
            if (push && m_cnt == DEPTH) hit_push_full = hit_push_full + 1;
            if (push && clr)            hit_clr_push  = hit_clr_push + 1;

            if (clr) begin
                m_rd = 0;
                m_cnt = 0;
            end else begin
                do_push = push && (m_cnt != DEPTH);
                do_pop  = pop  && (m_cnt != 0);
                if (do_push) model[(m_rd + m_cnt) % DEPTH] = wdata;
                if (do_pop)  begin m_rd = m_rd + 1; m_cnt = m_cnt - 1; end
                if (do_push) m_cnt = m_cnt + 1;
            end
        end
    end

    initial begin
        if (!$value$plusargs("seed=%d", seed)) seed = 1;
        repeat (4) @(posedge clk);
        #1 rst_n = 1;
        repeat (30000) @(posedge clk);

        $display("fifo cycles: full=%0d empty=%0d pop_on_empty=%0d push_on_full=%0d clr+push=%0d",
                 hit_full, hit_empty, hit_pop_empty, hit_push_full, hit_clr_push);
        if (hit_full == 0 || hit_empty == 0 || hit_pop_empty == 0 ||
            hit_push_full == 0 || hit_clr_push == 0) begin
            errors = errors + 1;
            $display("coverage hole in fifo test");
        end
        if (errors == 0) $display("TEST PASSED (sync_fifo)");
        else             $display("TEST FAILED: %0d error(s) (sync_fifo)", errors);
        $finish;
    end
endmodule
