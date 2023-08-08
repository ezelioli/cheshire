// Copyright 2023 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Nicole Narr <narrn@student.ethz.ch>
// Christopher Reinwardt <creinwar@student.ethz.ch>
// Thomas Benz <tbenz@iis.ee.ethz.ch>
//
// Simple payload to test AXI-RT

#include "regs/cheshire.h"
#include "dif/clint.h"
#include "dif/uart.h"
#include "axirt.h"
#include "regs/axi_rt.h"
#include "params.h"
#include "util.h"

int main(void) {
    char str[] = "Hello AXI-RT!\r\n";
    uint32_t rtc_freq = *reg32(&__base_regs, CHESHIRE_RTC_FREQ_REG_OFFSET);
    uint64_t reset_freq = clint_get_core_freq(rtc_freq, 2500);

    // enable and configure axi rt
    __axirt_claim(1, 1);
    for (int m = 0; m < AXI_RT_PARAM_NUM_MRG; m++) {
        __axirt_set_len_limit(8, m);
        __axirt_set_region(0,           0xffffffff,         0, m);
        __axirt_set_region(0x100000000, 0xffffffffffffffff, 1, m);
        __axirt_set_budget(0x10000000, 0, m);
        __axirt_set_budget(0x10000000, 1, m);
        __axirt_set_period(0x10000000, 0, m);
        __axirt_set_period(0x10000000, 1, m);
    }
    __axirt_enable(0xffffffff);

    // configure uart and write msg
    uart_init(&__base_uart, reset_freq, 115200);
    uart_write_str(&__base_uart, str, sizeof(str));
    uart_write_flush(&__base_uart);
    return 0;
}
