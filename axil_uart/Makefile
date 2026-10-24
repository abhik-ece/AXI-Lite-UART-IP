IVERILOG ?= iverilog
VVP      ?= vvp
VERILATOR?= verilator
YOSYS    ?= yosys
CC       ?= gcc

SEED   ?= 1
NSEEDS ?= 20

RTL := rtl/sync_fifo.v rtl/uart_tx.v rtl/uart_rx.v rtl/axil_uart_regs.v rtl/axil_uart.v
TB  := tb/axil_monitor.v tb/tb_axil_uart.v
IVFLAGS := -g2005 -Wall -Wno-timescale -s tb_axil_uart

SIMCELLS ?= $(firstword $(wildcard $(shell $(YOSYS)-config --datdir 2>/dev/null)/simcells.v /usr/share/yosys/simcells.v /usr/local/share/yosys/simcells.v))

.PHONY: all lint unit sim regress synth gls sw wave clean

all: lint unit sim regress synth gls sw
	@echo "ALL CHECKS PASSED"

lint:
	$(VERILATOR) --lint-only -Wall --top-module axil_uart $(RTL)
	@echo "lint clean"

sim/fifo.vvp: rtl/sync_fifo.v tb/tb_sync_fifo.v
	@mkdir -p sim
	$(IVERILOG) -g2005 -Wall -Wno-timescale -s tb_sync_fifo -o $@ $^

unit: sim/fifo.vvp
	@$(VVP) -n sim/fifo.vvp +seed=$(SEED) | tee sim/fifo.log | grep -E "TEST|ERROR|fifo|hole"
	@grep -q "TEST PASSED" sim/fifo.log

sim/rtl.vvp: $(RTL) $(TB)
	@mkdir -p sim
	$(IVERILOG) $(IVFLAGS) -o $@ $(RTL) $(TB)

sim: sim/rtl.vvp
	@$(VVP) -n sim/rtl.vvp +seed=$(SEED) | tee sim/run_$(SEED).log | grep -E "ERROR|NOT HIT|TEST|seed"
	@grep -q "TEST PASSED" sim/run_$(SEED).log

wave: sim/rtl.vvp
	$(VVP) -n sim/rtl.vvp +seed=$(SEED) +vcd > /dev/null
	@echo "wrote sim/wave.vcd"

regress: sim/rtl.vvp
	@fail=0; for s in $$(seq 1 $(NSEEDS)); do \
	    $(VVP) -n sim/rtl.vvp +seed=$$s > sim/run_$$s.log; \
	    if grep -q "TEST PASSED" sim/run_$$s.log; then r=pass; else r=FAIL; fail=$$((fail+1)); fi; \
	    echo "seed $$s: $$r"; \
	done; \
	echo "regression: $$(($(NSEEDS)-fail))/$(NSEEDS) passed"; test $$fail -eq 0

synth/out/axil_uart_syn.v: $(RTL) synth/synth.ys
	@mkdir -p synth/out
	$(YOSYS) -q -l synth/out/yosys.log synth/synth.ys
	@grep -A40 "Number of cells" synth/out/yosys.log | head -45

synth: synth/out/axil_uart_syn.v

sim/gls.vvp: synth/out/axil_uart_syn.v $(TB)
	@mkdir -p sim
	$(IVERILOG) -g2005 -Wno-timescale -s tb_axil_uart -o $@ $(SIMCELLS) synth/out/axil_uart_syn.v $(TB)

gls: sim/gls.vvp
	@$(VVP) -n sim/gls.vvp +seed=$(SEED) | tee sim/gls.log | grep -E "ERROR|NOT HIT|TEST"
	@grep -q "TEST PASSED" sim/gls.log

sw:
	$(CC) -std=c99 -Wall -Wextra -Werror -fsyntax-only sw/uart_test.c
	$(CC) -std=c99 -Wall -Wextra -Werror -o sim/driver_test sw/uart_test.c && ./sim/driver_test

clean:
	rm -rf sim/* synth/out
