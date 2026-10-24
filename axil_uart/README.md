# axil_uart

UART with an AXI4-Lite register interface, written in Verilog-2005, with the
verification and synthesis checks you would expect before handing an IP block
to someone else.

```
rtl/        sync_fifo  uart_tx  uart_rx  axil_uart_regs  axil_uart (top)
tb/         tb_axil_uart (top-level), axil_monitor (protocol checker), tb_sync_fifo (unit)
synth/      synth.ys (yosys), axil_uart.sdc (constraints)
sw/         axil_uart.h (bare-metal driver), uart_test.c (host check)
docs/       spec.md (interface, register map, behaviour, verification plan)
```

## Quick start

Needs `iverilog`, `verilator`, `yosys`, `gcc`, `make`.

```
make all        # lint, unit test, sim, 20-seed regression, synthesis, gate-level sim, C driver
make sim SEED=5 # one run with a chosen seed
make wave       # sim with a VCD dump (sim/wave.vcd)
```

Each step is also its own target; the list is at the top of the Makefile.

## What the flow checks

| Step | Tool | Result |
|------|------|--------|
| lint | Verilator `-Wall` | clean |
| FIFO unit test | Icarus | pass |
| top-level test, 29 coverage bins | Icarus | pass, no coverage holes |
| regression | Icarus, 20 seeds | 20/20 |
| synthesis | yosys, generic gates | ~1600 cells, 487 flops |
| gate-level sim | Icarus + yosys cell models | pass |
| C driver | gcc `-Wall -Wextra -Werror` | pass |

Details, register map and behavioural notes are in [docs/spec.md](docs/spec.md).

## Caveats

- Simulation is zero-delay; no timing numbers are claimed. The SDC has not been run through a commercial STA tool.
- Verification is plain Verilog with a hand-written scoreboard and counters rather than UVM/SVA, so that everything runs on open-source tools.
- The GitHub Actions file in `.github/` has not been run.
