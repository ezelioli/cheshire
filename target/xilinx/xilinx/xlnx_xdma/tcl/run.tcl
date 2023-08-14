# Copyright 2023 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Cyril Koenig <cykoenig@iis.ee.ethz.ch>

set partNumber $::env(XILINX_PART)
set boardName  $::env(XILINX_BOARD)

set ipName xlnx_xdma

create_project $ipName . -force -part $partNumber
set_property board_part $boardName [current_project]

create_ip -name xdma -vendor xilinx.com -library ip -version 4.1 -module_name $ipName

if {$::env(BOARD) eq "vcu128"} {
    set_property -dict  [list CONFIG.functional_mode {AXI_Bridge} \
                              CONFIG.mode_selection {Basic} \
                              CONFIG.pcie_blk_locn {PCIE4C_X1Y0} \
                              CONFIG.pl_link_cap_max_link_width {X4} \
                              CONFIG.drp_clk_sel {Internal} \
                              CONFIG.axi_addr_width {48} \
                              CONFIG.axisten_freq {125} \
                              CONFIG.sys_reset_polarity {ACTIVE_LOW} \
                              CONFIG.pf0_device_id {9014} \
                              CONFIG.xdma_axilite_slave {true} \
                              CONFIG.PCIE_BOARD_INTERFACE {pci_express_x4} \
                              CONFIG.en_gt_selection {true} \
                              CONFIG.select_quad {GTY_Quad_227} \
                              CONFIG.pf0_msix_cap_table_bir {BAR_1:0} \
                              CONFIG.pf0_msix_cap_pba_bir {BAR_1:0} \
                              CONFIG.pf0_bar0_size {1} \
                              CONFIG.pf0_bar0_scale {Gigabytes} \
                              CONFIG.pf0_bar0_64bit {true} \
                              CONFIG.pf0_bar2_enabled {false} \
                              CONFIG.bar_indicator {BAR_1:0} \
                              CONFIG.dma_reset_source_sel {User_Reset} \
                              CONFIG.PF0_DEVICE_ID_mqdma {9014} \
                              CONFIG.PF2_DEVICE_ID_mqdma {9214} \
                              CONFIG.PF3_DEVICE_ID_mqdma {9314} \
                              CONFIG.PF0_SRIOV_VF_DEVICE_ID {A034} \
                              CONFIG.PF1_SRIOV_VF_DEVICE_ID {A134} \
                              CONFIG.PF2_SRIOV_VF_DEVICE_ID {A234} \
                              CONFIG.PF3_SRIOV_VF_DEVICE_ID {A334} \
                        ] [get_ips $ipName]
}

generate_target {instantiation_template} [get_files ./$ipName.srcs/sources_1/ip/$ipName/$ipName.xci]
generate_target all [get_files  ./$ipName.srcs/sources_1/ip/$ipName/$ipName.xci]
create_ip_run [get_files -of_objects [get_fileset sources_1] ./$ipName.srcs/sources_1/ip/$ipName/$ipName.xci]
launch_run -jobs 8 ${ipName}_synth_1
wait_on_run ${ipName}_synth_1
