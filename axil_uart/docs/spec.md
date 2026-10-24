# axil_uart - design specification

Rev 1.0

## 1. Overview

A UART with an AXI4-Lite slave register interface, meant to be dropped into a
small SoC as a console or debug port.

- Full duplex, 8 data bits, optional even/odd parity, 1 or 2 stop bits
- 16-bit divider: the bit period is exactly `DIV` clocks (minimum 8)
- 16-entry TX FIFO (8 bit) and 16-entry RX FIFO (8 bit data + parity/framing flags)
- Six sticky interrupt sources, one level interrupt output
- Internal loopback, FIFO flush
- Single clock, asynchronous-assert reset

```
            AXI4-Lite                                  serial
 master ===============> +-------------------+
                          |  axil_uart_regs   |
                          |  (bus + registers)|
                          +--+-------------+--+
                 push/flush  |             |  pop/flush
                       +-----v----+   +----v-----+
                       | TX FIFO  |   | RX FIFO  |
                       +-----+----+   +----^-----+
                             |             |
                       +-----v----+   +----+-----+
                       | uart_tx  |   | uart_rx  |<--- 2-flop sync <--- uart_rxd
                       +-----+----+   +----------+
                             |   ^ loopback mux
                             +---+-----------------------> uart_txd
```

## 2. Interface

| Signal              | Dir | Width | Description |
|---------------------|-----|-------|-------------|
| `clk`               | in  | 1     | system clock |
| `rst_n`             | in  | 1     | active-low reset, async assert, release synchronously |
| `s_axil_*`          | -   | -     | AXI4-Lite slave, 8-bit address, 32-bit data |
| `uart_rxd`          | in  | 1     | serial input, asynchronous to `clk` |
| `uart_txd`          | out | 1     | serial output, idles high |
| `irq`               | out | 1     | high while any enabled interrupt status bit is set |

AXI4-Lite behaviour:

- One outstanding write and one outstanding read at a time.
- AW and W may arrive in either order or together; the write is performed once both are in.
- Responses are `OKAY` or `SLVERR`. `EXOKAY`/`DECERR` are never produced. `AWPROT`/`ARPROT` are not part of this interface.
- `SLVERR` is returned for: address outside `0x00-0x1F`, address not word aligned, any write to a read-only register, a read of `TXDATA`. A `SLVERR` write has no side effect; a `SLVERR` read returns 0.
- `WSTRB` is honoured per byte lane for `CTRL`, `DIV` (2 lanes), `TXDATA`, `IRQ_EN`, `IRQ_STATUS`. A register whose relevant lane has no strobe is not written.

## 3. Register map

All registers are 32 bits; unused bits read as 0 and ignore writes.

| Offset | Name       | Access | Reset      | Description |
|--------|------------|--------|------------|-------------|
| 0x00   | CTRL       | RW     | 0x00       | control, see below |
| 0x04   | DIV        | RW     | 868        | bit period in clocks (115200 baud at 100 MHz). Values below 8 behave as 8 |
| 0x08   | STATUS     | RO     | 0x05       | FIFO and engine status |
| 0x0C   | TXDATA     | WO     | -          | write bits 7:0 to queue a byte for transmission |
| 0x10   | RXDATA     | RO     | 0x80000000 | read pops one received byte |
| 0x14   | IRQ_EN     | RW     | 0x00       | interrupt enable mask |
| 0x18   | IRQ_STATUS | W1C    | 0x00       | sticky interrupt events |
| 0x1C   | LEVEL      | RO     | 0x00       | FIFO fill levels |

**CTRL**

| Bit | Name     | Description |
|-----|----------|-------------|
| 0   | TX_EN    | transmitter may start new frames |
| 1   | RX_EN    | receiver looks for start bits |
| 2   | PAR_EN   | parity bit between data and stop |
| 3   | PAR_ODD  | 1 = odd parity, 0 = even (only if PAR_EN) |
| 4   | STOP2    | 2 stop bits on transmit (the receiver always checks one) |
| 5   | LOOPBACK | receiver input is connected to the transmitter output; `uart_txd` still toggles |
| 6   | TX_FLUSH | write 1: empty the TX FIFO. Reads 0 |
| 7   | RX_FLUSH | write 1: empty the RX FIFO. Reads 0 |

**STATUS**: bit 0 TX_EMPTY, 1 TX_FULL, 2 RX_EMPTY, 3 RX_FULL, 4 TX_BUSY (a frame is on the wire), 5 RX_BUSY (a frame is being received).

**RXDATA**: bits 7:0 data, bit 8 PERR (parity error on this byte), bit 9 FERR (stop bit was 0), bit 31 EMPTY. When EMPTY is set the other bits are 0 and nothing is popped.

**IRQ_STATUS / IRQ_EN** (same bit positions):

| Bit | Event |
|-----|-------|
| 0   | RX_DONE: a byte was pushed into the RX FIFO |
| 1   | TX_DONE: a frame finished and the TX FIFO is empty (so not after every frame of a burst) |
| 2   | RX_OVERRUN: a byte arrived with the RX FIFO full and was dropped |
| 3   | TX_OVERFLOW: TXDATA was written with the TX FIFO full; the byte was dropped (the write itself returns OKAY) |
| 4   | PARITY_ERR: a byte with a parity error was received (it is still delivered, flagged) |
| 5   | FRAMING_ERR: a byte with a bad stop bit was received (still delivered, flagged) |

Bits are set by hardware and cleared by writing 1. A new event in the same cycle as a clear wins. `irq = |(IRQ_STATUS & IRQ_EN)`.

**LEVEL**: bits 4:0 TX FIFO level (0-16), bits 12:8 RX FIFO level (0-16).

## 4. Serial behaviour

Frame: start (0), D0..D7 (LSB first), parity (if enabled), stop (1) x1 or x2.
Parity bit = XOR of the data bits for even parity, inverted for odd parity.

**Transmit.** When TX_EN is set and the FIFO is non-empty a frame starts. DIV, parity and stop settings are sampled at the start of the frame, so changing them mid-frame does not corrupt it. Each bit lasts exactly DIV clocks. Clearing TX_EN lets the current frame finish.

**Receive.** `uart_rxd` passes through two flops, a falling edge starts a frame, and each bit is sampled DIV/2 clocks into the bit. A start bit that is no longer low at its midpoint is treated as a glitch and ignored. A bad stop bit sets FERR but the byte is delivered; the receiver then waits for the line to go high before looking for the next start bit, so a break condition yields one byte (0x00, FERR) and not a stream of them. Only one stop bit is checked, even when STOP2 is set.

Bit-rate tolerance of the receiver is verified at +/-2 %.

## 5. Programming notes

1. Pick `DIV = round(f_clk / baud)`. See `sw/axil_uart.h`.
2. Write DIV, then CTRL (with the flush bits if you want clean FIFOs).
3. Do not change DIV/parity/stop while a frame is in flight on the receiver (the receiver reads them live); check RX_BUSY or quiesce the line first.
4. To send: poll TX_FULL (or use LEVEL), write TXDATA. To receive: poll RX_EMPTY or enable RX_DONE, read RXDATA until EMPTY is set.
5. Clear IRQ_STATUS bits you have handled (W1C).

## 6. Clocking, reset, CDC

One clock domain. `uart_rxd` is the only asynchronous input and has a 2-flop synchroniser (`rxd_m`, `rxd_s`) in `uart_rx`. `rst_n` is used as an asynchronous reset on all control flops; FIFO storage arrays are not reset (contents are never observed when empty). The SoC should deassert `rst_n` synchronously.

## 7. Verification

| Item | Where |
|------|-------|
| Lint (Verilator `-Wall`), clean | `make lint` |
| FIFO block test, random with reference model, 30k cycles | `tb/tb_sync_fifo.v`, `make unit` |
| Top-level directed + constrained-random testbench | `tb/tb_axil_uart.v`, `make sim` |
| AXI4-Lite protocol monitor | `tb/axil_monitor.v` |
| Multi-seed regression (default 20 seeds) | `make regress` |
| Gate-level simulation of the synthesised netlist, same testbench | `make gls` |
| C driver compile + host check | `make sw` |

Top-level testbench contents: reset values; byte strobes; SLVERR cases; TX at four dividers x three parity modes x two stop settings with every bit period checked clock-by-clock by an independent decoder; the same matrix on RX (including back-to-back frames); parity error, framing error, break, glitch and recovery; FIFO full, TX overflow, RX overrun; interrupt mask/W1C; flush; random loopback traffic with random AXI idle gaps and AW/W ordering; RX sample-point window test; baud tolerance; divider clamp; reset in the middle of a frame.

Functional coverage is collected in the testbench as counters (about 29 bins); the test fails if any bin is not hit.

The tests were themselves checked by injecting about 30 deliberate bugs into the RTL (wrong parity polarity, off-by-one FIFO full, sample point shifted by a few clocks, missing events, wrong responses, ...). Every bug that changes observable behaviour is caught; a few were missed on the first pass and led to the sample-point, divider-clamp, `tx_done` and FIFO block tests.

## 8. Synthesis (generic, yosys 0.33)

Technology-independent mapping (`make synth`): about 1600 simple gates and 487 flops, of which 288 are FIFO storage. This is a sanity check, not timing signoff. `synth/axil_uart.sdc` is a starting constraint set for a real flow.

## 9. Not implemented

No hardware flow control (RTS/CTS), no 5-7 or 9 bit frames, no break generation, no DMA, no FIFO threshold interrupts, no AXI4-Lite outstanding transactions. Memories are flop-based; swap in a RAM macro for deeper FIFOs.
