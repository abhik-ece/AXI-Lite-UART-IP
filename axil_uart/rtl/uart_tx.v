module uart_tx (
    input             clk,
    input             rst_n,
    input             en,
    input      [15:0] div,
    input             par_en,
    input             par_odd,
    input             stop2,

    input             fifo_empty,
    input      [7:0]  fifo_data,
    output            fifo_pop,

    output reg        txd,
    output            busy,
    output reg        frame_done        
);
    reg        active;
    reg [10:0] shreg;             
    reg [3:0]  bit_idx;
    reg [3:0]  frame_len;
    reg [15:0] div_q;
    reg [15:0] tmr;

    wire start   = !active && en && !fifo_empty;
    wire par_bit = (^fifo_data) ^ par_odd;      

    assign fifo_pop = start;
    assign busy     = active;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active     <= 1'b0;
            txd        <= 1'b1;
            shreg      <= 11'h7FF;
            bit_idx    <= 4'd0;
            frame_len  <= 4'd10;
            div_q      <= 16'd8;
            tmr        <= 16'd0;
            frame_done <= 1'b0;
        end else begin
            frame_done <= 1'b0;

            if (!active) begin
                if (start) begin
                    active    <= 1'b1;
                    txd       <= 1'b0;                    
                    shreg     <= par_en ? {2'b11, par_bit, fifo_data}
                                        : {3'b111, fifo_data};
                    bit_idx   <= 4'd0;
                    frame_len <= 4'd10 + {3'b0, par_en} + {3'b0, stop2};
                    div_q     <= div;
                    tmr       <= div - 16'd1;
                end
            end else if (tmr == 16'd0) begin
                if (bit_idx == frame_len - 4'd1) begin
                    active     <= 1'b0;
                    txd        <= 1'b1;
                    frame_done <= 1'b1;
                end else begin
                    shreg   <= {1'b1, shreg[10:1]};
                    txd     <= shreg[0];
                    bit_idx <= bit_idx + 4'd1;
                    tmr     <= div_q - 16'd1;
                end
            end else begin
                tmr <= tmr - 16'd1;
            end
        end
    end
endmodule
