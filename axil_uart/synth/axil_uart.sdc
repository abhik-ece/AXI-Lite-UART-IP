# Timing constraints for axil_uart (starting point for a real flow).
# Written for a 100 MHz target; adjust the period and I/O budgets to your SoC.
# NOTE: not run through a commercial STA tool in this repo - review before use.

create_clock -name clk -period 10.0 [get_ports clk]
set_clock_uncertainty 0.3 [get_clocks clk]

# AXI4-Lite is synchronous to clk: budget 40% of the cycle on each side
set axi_in  [get_ports {s_axil_aw* s_axil_w* s_axil_b_ready s_axil_ar* s_axil_rready}]
set axi_out [get_ports {s_axil_*ready s_axil_*valid s_axil_bresp s_axil_rdata s_axil_rresp}]
set_input_delay  -clock clk -max 4.0 $axi_in
set_input_delay  -clock clk -min 0.5 $axi_in
set_output_delay -clock clk -max 4.0 $axi_out
set_output_delay -clock clk -min 0.0 $axi_out

# Serial pins and interrupt are asynchronous to clk. rxd goes through a 2-flop
# synchroniser inside uart_rx, so it is a false path for timing purposes.
set_false_path -from [get_ports uart_rxd]
set_output_delay -clock clk -max 2.0 [get_ports {uart_txd irq}]

# Reset: rst_n is asserted asynchronously and must be released synchronously
# to clk by the SoC reset controller. Leave recovery/removal checks enabled.
# (Do not false-path it unless your reset tree is constrained elsewhere.)
