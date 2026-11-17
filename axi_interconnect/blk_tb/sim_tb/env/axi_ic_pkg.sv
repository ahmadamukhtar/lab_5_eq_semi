// Interconnect UVM package: env (scoreboard, coverage, vseqr), virtual sequences and tests.

package axi_ic_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import axi4l_pkg::*;

    `include "axi_ic_cfg.sv"
    `include "axi_ic_scoreboard.sv"
    `include "axi_ic_coverage.sv"
    `include "axi_ic_vseqr.sv"
    `include "axi_ic_env.sv"
    `include "axi_ic_vseq_lib.sv"

    `include "axi_ic_base_test.sv"
    `include "axi_ic_smoke_test.sv"
    `include "axi_ic_vseq_tests.sv"
endpackage
