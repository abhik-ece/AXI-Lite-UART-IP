module sync_fifo #(
    parameter WIDTH = 8,
    parameter AW    = 4                
    input              clk,
    input              rst_n,
    input              clr,
    input              push,
    input  [WIDTH-1:0] wdata,
    input              pop,
    output [WIDTH-1:0] rdata,
    output             full,
    output             empty,
    output [AW:0]      level
);
    localparam DEPTH = 1 << AW;

    reg [WIDTH-1:0] mem [0:DEPTH-1];
    reg [AW:0]      wptr;
    reg [AW:0]      rptr;

    assign level = wptr - rptr;
    assign full  = (level == DEPTH[AW:0]);
    assign empty = (wptr == rptr);

    wire do_push = push && !full;
    wire do_pop  = pop  && !empty;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wptr <= {(AW+1){1'b0}};
            rptr <= {(AW+1){1'b0}};
        end else if (clr) begin
            wptr <= {(AW+1){1'b0}};
            rptr <= {(AW+1){1'b0}};
        end else begin
            if (do_push) wptr <= wptr + 1'b1;
            if (do_pop)  rptr <= rptr + 1'b1;
        end
    end

    always @(posedge clk) begin
        if (do_push && !clr)
            mem[wptr[AW-1:0]] <= wdata;
    end

    assign rdata = mem[rptr[AW-1:0]];
endmodule
