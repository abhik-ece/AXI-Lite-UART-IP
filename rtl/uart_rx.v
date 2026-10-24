module uart_rx (
    input             clk,
    input             rst_n,
    input             en,
    input      [15:0] div,
    input             par_en,
    input             par_odd,
    input             rxd,

    output reg        valid,           
    output reg [7:0]  data,
    output reg        perr,
    output reg        ferr,
    output            busy
);
    localparam [2:0] S_IDLE  = 3'd0,
                     S_START = 3'd1,
                     S_DATA  = 3'd2,
                     S_PAR   = 3'd3,
                     S_STOP  = 3'd4;

    reg [2:0]  state;
    reg [15:0] tmr;
    reg [2:0]  cnt;
    reg [7:0]  shreg;
    reg        perr_q;
    reg        rxd_m, rxd_s, rxd_p;     
    assign busy = (state != S_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rxd_m <= 1'b1;
            rxd_s <= 1'b1;
            rxd_p <= 1'b1;
        end else begin
            rxd_m <= rxd;
            rxd_s <= rxd_m;
            rxd_p <= rxd_s;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state  <= S_IDLE;
            tmr    <= 16'd0;
            cnt    <= 3'd0;
            shreg  <= 8'd0;
            perr_q <= 1'b0;
            valid  <= 1'b0;
            data   <= 8'd0;
            perr   <= 1'b0;
            ferr   <= 1'b0;
        end else begin
            valid <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (en && rxd_p && !rxd_s) begin
                        state <= S_START;
                        tmr   <= {1'b0, div[15:1]} - 16'd2;
                    end
                end

                S_START: begin
                    if (tmr == 16'd0) begin
                        if (!rxd_s) begin               
                            state  <= S_DATA;
                            tmr    <= div - 16'd1;
                            cnt    <= 3'd0;
                            perr_q <= 1'b0;
                        end else begin
                            state <= S_IDLE;          
                        end
                    end else begin
                        tmr <= tmr - 16'd1;
                    end
                end

                S_DATA: begin
                    if (tmr == 16'd0) begin
                        shreg <= {rxd_s, shreg[7:1]};
                        tmr   <= div - 16'd1;
                        cnt   <= cnt + 3'd1;
                        if (cnt == 3'd7)
                            state <= par_en ? S_PAR : S_STOP;
                    end else begin
                        tmr <= tmr - 16'd1;
                    end
                end

                S_PAR: begin
                    if (tmr == 16'd0) begin
                        perr_q <= (rxd_s != ((^shreg) ^ par_odd));
                        tmr    <= div - 16'd1;
                        state  <= S_STOP;
                    end else begin
                        tmr <= tmr - 16'd1;
                    end
                end

                S_STOP: begin
                    if (tmr == 16'd0) begin
                        valid <= 1'b1;
                        data  <= shreg;
                        perr  <= perr_q;
                        ferr  <= !rxd_s;
                        state <= S_IDLE;
                    end else begin
                        tmr <= tmr - 16'd1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
