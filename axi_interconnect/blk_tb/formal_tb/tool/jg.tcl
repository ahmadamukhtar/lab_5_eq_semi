# Progressive JasperGold run for axi4_lite_2x9_interconnect.
# Env vars: FV_PROFILE (p0..p7, default p7), FV_DEFS (extra defines, space separated),
#           FV_TIME (prove time limit, default 600s)

proc env_or {name def} {
    if {[info exists ::env($name)] && $::env($name) ne ""} { return $::env($name) }
    return $def
}

set profile [env_or FV_PROFILE p7]
set extra   [env_or FV_DEFS ""]
set tlimit  [env_or FV_TIME 600s]

set asrt "FV_ASRT_PROTO FV_ASRT_ARB FV_ASRT_ROUTE FV_ASRT_RESP FV_COVER"

switch $profile {
    p0 { set d "FV_ONE_MGR FV_NO_READ FV_ONE_TARGET FV_MAPPED_ONLY FV_SUB_NO_STALL FV_SUB_FAST_RSP FV_MGR_RSP_READY FV_SUB_NO_ERR" }
    p1 { set d "FV_ONE_MGR FV_NO_READ FV_MAPPED_ONLY FV_SUB_NO_STALL FV_SUB_FAST_RSP FV_MGR_RSP_READY FV_SUB_NO_ERR" }
    p2 { set d "FV_ONE_MGR FV_NO_WRITE FV_MAPPED_ONLY FV_SUB_NO_STALL FV_SUB_FAST_RSP FV_MGR_RSP_READY FV_SUB_NO_ERR" }
    p3 { set d "FV_ONE_MGR FV_MAPPED_ONLY FV_SUB_NO_STALL FV_MGR_RSP_READY" }
    p4 { set d "FV_MAPPED_ONLY FV_SUB_NO_STALL FV_SUB_FAST_RSP FV_MGR_RSP_READY FV_SUB_NO_ERR" }
    p5 { set d "FV_MAPPED_ONLY" }
    p6 { set d "FV_UNMAPPED_ONLY" }
    p7 { set d "" }
    default { error "unknown profile $profile" }
}

set defargs {}
foreach x [concat $d $asrt $extra] { lappend defargs +define+$x }

clear -all
analyze -sv12 {*}$defargs \
    tb/fv_ic_pkg.sv \
    ../../../common/modules/axi_lite_if/rtl/axi4_lite_if.sv \
    ../../modules/arbiter/rtl/arbiter.sv \
    ../../modules/axi_1x9_interconnect/rtl/axi4_lite_1x9_interconnect.sv \
    ../../rtl/axi4_lite_2x9_interconnect.sv \
    tb/fv_mgr_assume.sv tb/fv_sub_assume.sv tb/fv_ic_props.sv tb/fv_ic_top.sv

elaborate -top fv_ic_top
clock ACLK
reset -expression {!ARESETn}
prove -all -time_limit $tlimit
report
if {![info exists ::env(FV_GUI)]} { exit }
