// ==============================================================================
// Copyright (c) Empty Quarter Semiconductor Co. - EQSemi
// All rights reserved.
// EQSEMI CONFIDENTIAL -- do not copy, disclose or distribute without written permission.
// ------------------------------------------------------------------------------
// Project       : edge-ai-eqsemi
// File          : verif/uvm/common/axi4l_uvc/axi4l_pkg.sv
// ==============================================================================
// Reusable AXI4-Lite UVC (full-word variant, no WSTRB/PROT) built on
// design/common/modules/axi_lite_if/rtl/axi4_lite_if.sv.
//
// Compile axi4_lite_if.sv before this package and add this directory to the
// include path (+incdir+). Widths are compile-time: +define+AXI4L_ADDR_W=<n>
// +define+AXI4L_DATA_W=<n> (default 32/32) and must match the interface.
// ==============================================================================

`ifndef AXI4L_ADDR_W
  `define AXI4L_ADDR_W 32
`endif
`ifndef AXI4L_DATA_W
  `define AXI4L_DATA_W 32
`endif

package axi4l_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "axi4l_types.sv"
    `include "axi4l_item.sv"
    `include "axi4l_event.sv"
    `include "axi4l_agent_cfg.sv"
    `include "axi4l_sequencer.sv"
    `include "axi4l_master_driver.sv"
    `include "axi4l_slave_driver.sv"
    `include "axi4l_monitor.sv"
    `include "axi4l_agent.sv"
    `include "axi4l_seq_lib.sv"
endpackage
