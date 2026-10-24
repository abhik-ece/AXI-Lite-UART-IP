#ifndef AXIL_UART_H
#define AXIL_UART_H

#include <stdint.h>

#define UART_CTRL        0x00u
#define UART_DIV         0x04u
#define UART_STATUS      0x08u
#define UART_TXDATA      0x0Cu
#define UART_RXDATA      0x10u
#define UART_IRQ_EN      0x14u
#define UART_IRQ_STATUS  0x18u
#define UART_LEVEL       0x1Cu

#define UART_CTRL_TX_EN     (1u << 0)
#define UART_CTRL_RX_EN     (1u << 1)
#define UART_CTRL_PAR_EN    (1u << 2)
#define UART_CTRL_PAR_ODD   (1u << 3)
#define UART_CTRL_STOP2     (1u << 4)
#define UART_CTRL_LOOPBACK  (1u << 5)
#define UART_CTRL_TX_FLUSH  (1u << 6)  
#define UART_CTRL_RX_FLUSH  (1u << 7)  
#define UART_ST_TX_EMPTY    (1u << 0)
#define UART_ST_TX_FULL     (1u << 1)
#define UART_ST_RX_EMPTY    (1u << 2)
#define UART_ST_RX_FULL     (1u << 3)
#define UART_ST_TX_BUSY     (1u << 4)
#define UART_ST_RX_BUSY     (1u << 5)
#define UART_RX_PERR        (1u << 8)
#define UART_RX_FERR        (1u << 9)
#define UART_RX_EMPTY       (1u << 31)
#define UART_IRQ_RX_DONE    (1u << 0)
#define UART_IRQ_TX_DONE    (1u << 1)
#define UART_IRQ_RX_OVERRUN (1u << 2)
#define UART_IRQ_TX_OVERFLOW (1u << 3)
#define UART_IRQ_PARITY     (1u << 4)
#define UART_IRQ_FRAMING    (1u << 5)

#define UART_MIN_DIV        8u

typedef volatile uint32_t *uart_t;     

static inline uint32_t uart_rd(uart_t u, uint32_t off) { return u[off >> 2]; }
static inline void     uart_wr(uart_t u, uint32_t off, uint32_t v) { u[off >> 2] = v; }

static inline uint32_t uart_calc_div(uint32_t clk_hz, uint32_t baud)
{
    return (clk_hz + baud / 2u) / baud;
}
static inline int uart_init(uart_t u, uint32_t clk_hz, uint32_t baud,
                            int parity , int two_stop)
{
    uint32_t div = uart_calc_div(clk_hz, baud);
    uint32_t ctrl = UART_CTRL_TX_EN | UART_CTRL_RX_EN;

    if (div < UART_MIN_DIV || div > 0xFFFFu)
        return -1;

    if (parity)  ctrl |= UART_CTRL_PAR_EN;
    if (parity == 2) ctrl |= UART_CTRL_PAR_ODD;
    if (two_stop) ctrl |= UART_CTRL_STOP2;

    uart_wr(u, UART_DIV, div);
    uart_wr(u, UART_CTRL, ctrl | UART_CTRL_TX_FLUSH | UART_CTRL_RX_FLUSH);
    uart_wr(u, UART_IRQ_STATUS, 0x3Fu);
    return 0;
}

static inline void uart_putc(uart_t u, uint8_t c)
{
    while (uart_rd(u, UART_STATUS) & UART_ST_TX_FULL)
        ;
    uart_wr(u, UART_TXDATA, c);
}

static inline int32_t uart_try_getc(uart_t u)
{
    uint32_t v = uart_rd(u, UART_RXDATA);
    if (v & UART_RX_EMPTY)
        return -1;
    return (int32_t)(v & 0x3FFu);
}

static inline void uart_flush(uart_t u)
{
    while (!(uart_rd(u, UART_STATUS) & UART_ST_TX_EMPTY) ||
            (uart_rd(u, UART_STATUS) & UART_ST_TX_BUSY))
        ;
}

#endif 
