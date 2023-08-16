// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Cyril Koenig <cykoenig@iis.ee.ethz.ch>


`include "cheshire/typedef.svh"
`include "phy_definitions.svh"
`include "common_cells/registers.svh"

module pcie_wrapper #(
    parameter type axi_soc_aw_chan_t = logic,
    parameter type axi_soc_w_chan_t  = logic,
    parameter type axi_soc_b_chan_t  = logic,
    parameter type axi_soc_ar_chan_t = logic,
    parameter type axi_soc_r_chan_t  = logic,
    parameter type axi_soc_req_t     = logic,
    parameter type axi_soc_resp_t    = logic
) (
    // System reset
    input                 sys_rst_i,
    input                 pcie_clk_i,
    // Controller reset
    input                 soc_resetn_i,
    input                 soc_clk_i,
    // Phy interfaces
    output wire [3 : 0]  pci_exp_txp,
    output wire [3 : 0]  pci_exp_txn,
    input  wire [3 : 0]  pci_exp_rxp,
    input  wire [3 : 0]  pci_exp_rxn,
    // Axi interface
    input  axi_soc_req_t   soc_pcie_req_i,
    output axi_soc_resp_t  soc_pcie_rsp_o,
    output axi_soc_req_t   pcie_soc_req_o,
    input  axi_soc_resp_t  pcie_soc_rsp_i
);

  ////////////////////////////////////
  // Configurations and definitions //
  ////////////////////////////////////

  typedef struct packed {
    bit EnSpill0;
    bit EnResizer;
    bit EnCDC;
    bit EnSpill1;
    integer IdWidth;
    integer AddrWidth;
    integer DataWidth;
    integer StrobeWidth;
  } pcie_cfg_t;

`ifdef TARGET_VCU128
  localparam pcie_cfg_t cfg = '{
    EnSpill0      : 0,
    EnResizer     : 0,
    EnCDC         : 1, // 125 MHz axi
    EnSpill1      : 0,
    IdWidth       : 4,
    AddrWidth     : 32,
    DataWidth     : 64,
    StrobeWidth   : 8
  };
`endif

  // Define type after resizer (PCIE AXI)
  `AXI_TYPEDEF_ALL(axi_ddr, logic[$bits(soc_pcie_req_i.ar.addr)-1:0], logic[$bits(soc_pcie_req_i.ar.id)-1:0],
                   logic[cfg.DataWidth-1:0], logic[cfg.StrobeWidth-1:0],
                   logic[$bits(soc_pcie_req_i.ar.user)-1:0])

  // Clock on which is clocked the PCIE AXI
  logic pcie_axi_clk, pcie_rstn;

  // SoC -> PCIe
  axi_soc_req_t  soc_spill_req, spill_resizer_req;
  axi_soc_resp_t soc_spill_rsp, spill_resizer_rsp;
  axi_ddr_req_t  resizer_cdc_req, cdc_spill_req, spill_pcie_req;
  axi_ddr_resp_t resizer_cdc_rsp, cdc_spill_rsp, spill_pcie_rsp;
  // SoC <- PCIe
  axi_ddr_req_t  pcie_spill_req, spill_cdc_req, cdc_resizer_req;
  axi_soc_req_t  resizer_spill_req, spill_soc_req;
  axi_ddr_resp_t pcie_spill_rsp, spill_cdc_rsp, cdc_resizer_rsp;
  axi_soc_resp_t resizer_spill_rsp, spill_soc_rsp;

  // Entry signals
  assign soc_spill_req = soc_pcie_req_i;
  assign soc_pcie_rsp_o = soc_spill_rsp;
  // Exit signals
  assign pcie_soc_req_o = spill_soc_req;
  assign spill_soc_rsp = pcie_soc_rsp_i;

  //////////////////////////
  // Instianciate Spill 0 //
  //////////////////////////

  if (cfg.EnSpill0) begin : gen_spill_0
    // AXI CUT (spill register) between the AXI CDC and the MIG to
    // reduce timing pressure
    axi_cut #(
        .Bypass    (1'b0),
        .aw_chan_t (axi_soc_aw_chan_t),
        .w_chan_t  (axi_soc_w_chan_t),
        .b_chan_t  (axi_soc_b_chan_t),
        .ar_chan_t (axi_soc_ar_chan_t),
        .r_chan_t  (axi_soc_r_chan_t),
        .axi_req_t (axi_soc_req_t),
        .axi_resp_t(axi_soc_resp_t)
    ) i_axi_cut_0 (
        .clk_i (soc_clk_i),
        .rst_ni(soc_resetn_i),
        .slv_req_i (soc_spill_req),
        .slv_resp_o(soc_spill_rsp),
        .mst_req_o (spill_resizer_req),
        .mst_resp_i(spill_resizer_rsp)
    );
  end else begin : gen_no_spill_0
    // PCIe slave
    assign spill_resizer_req = soc_spill_req;
    assign soc_spill_rsp = spill_resizer_rsp;
    // PCIe master
    assign spill_soc_req = resizer_spill_req;
    assign resizer_spill_rsp = spill_soc_rsp;
  end

  /////////////////////////////////////
  // Instianciate data width resizer //
  /////////////////////////////////////

  if (cfg.EnResizer) begin : gen_dw_converter
    axi_dw_converter #(
        .AxiMaxReads        (8),
        .AxiSlvPortDataWidth($bits(spill_resizer_req.w.data)),
        .AxiMstPortDataWidth($bits(resizer_cdc_req.w.data)),
        .AxiAddrWidth       ($bits(spill_resizer_req.ar.addr)),
        .AxiIdWidth         ($bits(spill_resizer_req.ar.id)),
        // Common aw, ar, b
        .aw_chan_t          (axi_soc_aw_chan_t),
        .b_chan_t           (axi_soc_b_chan_t),
        .ar_chan_t          (axi_soc_ar_chan_t),
        // Master w, r
        .mst_w_chan_t       (axi_ddr_w_chan_t),
        .mst_r_chan_t       (axi_ddr_r_chan_t),
        .axi_mst_req_t      (axi_ddr_req_t),
        .axi_mst_resp_t     (axi_ddr_resp_t),
        // Slave w, r
        .slv_w_chan_t       (axi_soc_w_chan_t),
        .slv_r_chan_t       (axi_soc_r_chan_t),
        .axi_slv_req_t      (axi_soc_req_t),
        .axi_slv_resp_t     (axi_soc_resp_t)
    ) axi_dw_converter_ddr4 (
        .clk_i(soc_clk_i),
        .rst_ni(soc_resetn_i),
        .slv_req_i(spill_resizer_req),
        .slv_resp_o(spill_resizer_rsp),
        .mst_req_o(resizer_cdc_req),
        .mst_resp_i(resizer_cdc_rsp)
    );
  end else begin : gen_no_dw_converter
    assign resizer_cdc_req   = spill_resizer_req;
    assign spill_resizer_rsp = resizer_cdc_rsp;
    //
    assign resizer_spill_req = cdc_resizer_req;
    assign cdc_resizer_rsp = spill_resizer_rsp;
  end


  //////////////////////
  // Instianciate CDC //
  //////////////////////

  if (cfg.EnCDC) begin : gen_cdc
    axi_cdc #(
        .aw_chan_t (axi_ddr_aw_chan_t),
        .w_chan_t  (axi_ddr_w_chan_t),
        .b_chan_t  (axi_ddr_b_chan_t),
        .ar_chan_t (axi_ddr_ar_chan_t),
        .r_chan_t  (axi_ddr_r_chan_t),
        .axi_req_t (axi_ddr_req_t),
        .axi_resp_t(axi_ddr_resp_t),
        .LogDepth  (3)
    ) i_axi_cdc_pcie_slv (
        .src_clk_i (soc_clk_i),
        .src_rst_ni(soc_resetn_i),
        .src_req_i (resizer_cdc_req),
        .src_resp_o(resizer_cdc_rsp),
        .dst_clk_i (pcie_axi_clk),
        .dst_rst_ni(pcie_rstn),
        .dst_req_o (cdc_spill_req),
        .dst_resp_i(cdc_spill_rsp)
    );
    axi_cdc #(
        .aw_chan_t (axi_ddr_aw_chan_t),
        .w_chan_t  (axi_ddr_w_chan_t),
        .b_chan_t  (axi_ddr_b_chan_t),
        .ar_chan_t (axi_ddr_ar_chan_t),
        .r_chan_t  (axi_ddr_r_chan_t),
        .axi_req_t (axi_ddr_req_t),
        .axi_resp_t(axi_ddr_resp_t),
        .LogDepth  (3)
    ) i_axi_cdc_pcie_mst (
        .src_clk_i (pcie_axi_clk),
        .src_rst_ni(pcie_rstn),
        .src_req_i (spill_cdc_req),
        .src_resp_o(spill_cdc_rsp),
        .dst_clk_i (soc_clk_i),
        .dst_rst_ni(soc_resetn_i),
        .dst_req_o (cdc_resizer_req),
        .dst_resp_i(cdc_resizer_rsp)
    );
  end else begin : gen_no_cdc
    assign cdc_spill_req   = resizer_cdc_req;
    assign resizer_cdc_rsp = cdc_spill_rsp;
  end

  //////////////////////////
  // Instianciate Spill 1 //
  //////////////////////////

  if (cfg.EnSpill1) begin : gen_spill_1

  end else begin : gen_no_spill_1
    //
    assign spill_pcie_req = cdc_spill_req;
    assign cdc_spill_rsp  = spill_pcie_rsp;
    //
    assign spill_cdc_req = pcie_spill_req;
    assign pcie_spill_rsp = spill_cdc_rsp;
  end

  /////////////////
  // ID resizer  //
  /////////////////

  // Padding when SoC id > PCIe id
  localparam IdPadding = $bits(spill_pcie_req.aw.id) - cfg.IdWidth;

  // Resize awid and arid before sending to the DDR
  logic [cfg.IdWidth-1:0] spill_pcie_req_awid, spill_pcie_rsp_bid;
  logic [cfg.IdWidth-1:0] spill_pcie_req_arid, spill_pcie_rsp_rid;
  logic [cfg.IdWidth-1:0] pcie_spill_req_awid, pcie_spill_rsp_bid;
  logic [cfg.IdWidth-1:0] pcie_spill_req_arid, pcie_spill_rsp_rid;

  // Process ids
  if (IdPadding > 0) begin : gen_downsize_ids
    // SoC -> PCIe downsizing
    // NOT SUPPORTED

    // PCIe -> SoC upsizing
    assign pcie_spill_req.ar.id = {{-IdPadding{1'b0}}, pcie_spill_req_arid};
    assign pcie_spill_req.aw.id = {{-IdPadding{1'b0}}, pcie_spill_req_awid};
    assign pcie_spill_rsp.r.id = pcie_spill_rsp_rid;
    assign pcie_spill_rsp.b.id = pcie_spill_rsp_bid;

  end else begin : gen_upsize_ids
    // NOT SUPPORTED
    do_not_enter_here i_error();
  end

  ///////////////////////
  // User and address  //
  ///////////////////////

  ///////////////////////
  // Instianciate XDMA //
  ///////////////////////

  xlnx_xdma i_xdma (
    .sys_clk(pcie_clk_i),
    .sys_clk_gt(pcie_clk_i),
    .sys_rst_n(soc_resetn_i),
    .axi_aclk(pcie_axi_clk),
    .axi_aresetn(pcie_rstn),
    // PCIe in AXI
    .m_axib_awid    ( pcie_spill_req_awid     ),
    .m_axib_awaddr  ( pcie_spill_req.aw.addr  ),
    .m_axib_awlen   ( pcie_spill_req.aw.len   ),
    .m_axib_awsize  ( pcie_spill_req.aw.size  ),
    .m_axib_awburst ( pcie_spill_req.aw.burst ),
    .m_axib_awprot  ( pcie_spill_req.aw.prot  ),
    .m_axib_awvalid ( pcie_spill_req.aw_valid ),
    .m_axib_awready ( pcie_spill_rsp.aw_ready ),
    .m_axib_awlock  ( pcie_spill_req.aw.lock  ),
    .m_axib_awcache ( pcie_spill_req.aw.cache ),
    .m_axib_wdata   ( pcie_spill_req.w.data   ),
    .m_axib_wstrb   ( pcie_spill_req.w.strb   ),
    .m_axib_wlast   ( pcie_spill_req.w.last   ),
    .m_axib_wvalid  ( pcie_spill_req.w_valid  ),
    .m_axib_wready  ( pcie_spill_rsp.w_ready  ),
    .m_axib_bid     ( pcie_spill_rsp_bid      ),
    .m_axib_bresp   ( pcie_spill_rsp.b.resp   ),
    .m_axib_bvalid  ( pcie_spill_rsp.b.valid  ),
    .m_axib_bready  ( pcie_spill_req.b.ready  ),
    .m_axib_arid    ( pcie_spill_req_arid     ),
    .m_axib_araddr  ( pcie_spill_req.ar.addr  ),
    .m_axib_arlen   ( pcie_spill_req.ar.len   ),
    .m_axib_arsize  ( pcie_spill_req.ar.size  ),
    .m_axib_arburst ( pcie_spill_req.ar.burst ),
    .m_axib_arprot  ( pcie_spill_req.ar.prot  ),
    .m_axib_arvalid ( pcie_spill_req.ar_valid ),
    .m_axib_arready ( pcie_spill_rsp.ar_ready ),
    .m_axib_arlock  ( pcie_spill_req.ar.lock  ),
    .m_axib_arcache ( pcie_spill_req.ar.cache ),
    .m_axib_rid     ( pcie_spill_rsp_rid      ),
    .m_axib_rdata   ( pcie_spill_rsp.r.data   ),
    .m_axib_rresp   ( pcie_spill_rsp.r.resp   ),
    .m_axib_rlast   ( pcie_spill_rsp.r.last   ),
    .m_axib_rvalid  ( pcie_spill_rsp.r_valid  ),
    .m_axib_rready  ( pcie_spill_req.r_ready  ),
    // PCIe out AXI
    .s_axib_awid      (),
    .s_axib_awaddr    (),
    .s_axib_awregion  (),
    .s_axib_awlen     (),
    .s_axib_awsize    (),
    .s_axib_awburst   (),
    .s_axib_awvalid   (),
    .s_axib_wdata     (),
    .s_axib_wstrb     (),
    .s_axib_wlast     (),
    .s_axib_wvalid    (),
    .s_axib_bready    (),
    .s_axib_arid      (),
    .s_axib_araddr    (),
    .s_axib_arregion  (),
    .s_axib_arlen     (),
    .s_axib_arsize    (),
    .s_axib_arburst   (),
    .s_axib_arvalid   (),
    .s_axib_rready    (),
    .s_axib_awready   (),
    .s_axib_wready    (),
    .s_axib_bid       (),
    .s_axib_bresp     (),
    .s_axib_bvalid    (),
    .s_axib_arready   (),
    .s_axib_rid       (),
    .s_axib_rdata     (),
    .s_axib_rresp     (),
    .s_axib_rlast     (),
    .s_axib_rvalid    (),
    // PCIe PHY
    .pci_exp_txp      (),
    .pci_exp_txn      (),
    .pci_exp_rxp      (),
    .pci_exp_rxn      ()
  );


endmodule
