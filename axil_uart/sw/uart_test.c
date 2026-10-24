#include <stdio.h>
#include "axil_uart.h"

static int failures;

#define CHECK(cond) do { if (!(cond)) { \
    printf("FAIL line %d: %s\n", __LINE__, #cond); failures++; } } while (0)

int main(void)
{
    static volatile uint32_t regs[8];
    uart_t u = regs;

    CHECK(uart_calc_div(100000000u, 115200u) == 868u);
    CHECK(uart_calc_div(100000000u, 9600u)   == 10417u);
    CHECK(uart_calc_div(50000000u, 3000000u) == 17u);

    CHECK(uart_init(u, 100000000u, 115200u, 1, 1) == 0);
    CHECK(regs[UART_DIV >> 2] == 868u);
    CHECK(regs[UART_CTRL >> 2] ==
          (UART_CTRL_TX_EN | UART_CTRL_RX_EN | UART_CTRL_PAR_EN | UART_CTRL_STOP2 |
           UART_CTRL_TX_FLUSH | UART_CTRL_RX_FLUSH));
    CHECK(regs[UART_IRQ_STATUS >> 2] == 0x3Fu);

    uart_init(u, 100000000u, 115200u, 2, 0);
    CHECK((regs[UART_CTRL >> 2] & UART_CTRL_PAR_ODD) != 0);
    CHECK((regs[UART_CTRL >> 2] & UART_CTRL_STOP2) == 0);

    CHECK(uart_init(u, 1000000u, 500000u, 0, 0) == -1);    
    CHECK(uart_init(u, 100000000u, 1u, 0, 0) == -1);       

    regs[UART_STATUS >> 2] = UART_ST_TX_EMPTY | UART_ST_RX_EMPTY;
    uart_putc(u, 0x55);
    CHECK(regs[UART_TXDATA >> 2] == 0x55u);

    regs[UART_RXDATA >> 2] = UART_RX_EMPTY;
    CHECK(uart_try_getc(u) == -1);
    regs[UART_RXDATA >> 2] = UART_RX_PERR | 0xA5u;
    CHECK(uart_try_getc(u) == (int32_t)(UART_RX_PERR | 0xA5u));

    regs[UART_STATUS >> 2] = UART_ST_TX_EMPTY | UART_ST_RX_EMPTY;
    uart_flush(u);

    if (failures) {
        printf("driver test: %d failure(s)\n", failures);
        return 1;
    }
    printf("driver test passed\n");
    return 0;
}
