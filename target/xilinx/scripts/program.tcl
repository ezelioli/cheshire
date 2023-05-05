# Copyright 2018 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Author: Florian Zaruba <zarubaf@iis.ee.ethz.ch>
# Description: Program Genesys II

open_hw_manager

connect_hw_server -url $::env(HOST):$::env(PORT)
open_hw_target $::env(HOST):$::env(PORT)/$::env(FPGA_PATH)

if {$::env(BOARD) eq "genesys2"} {
  set hw_device [get_hw_devices xc7k325t_0]
}
if {$::env(BOARD) eq "vcu128"} {
  set hw_device [get_hw_devices xcvu37p_0]
}

current_hw_device $hw_device
set_property PROGRAM.FILE $::env(BIT) $hw_device
program_hw_devices $hw_device
refresh_hw_device [lindex $hw_device 0]
