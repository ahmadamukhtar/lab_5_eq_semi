#!/bin/bash
# UVM run: ./run.sh [-t TEST] [-s SEED] [-v VERBOSITY] [-w] [-g]
#   -t  UVM test name   (default axi_ic_smoke_test)
#   -s  random seed     (default 1)
#   -v  UVM verbosity   (default UVM_MEDIUM)
#   -w  dump SHM waves  (waves.shm)
#   -g  open SimVision GUI
# Functional coverage is always collected (cov_work/); view with: imc -load cov_work/scope/$TEST  or  ./run.sh then imc
# Widths: export AXI4L_ADDR_W / AXI4L_DATA_W before running (default 32 / 32).
cd "$(dirname "$0")" || exit 1

TEST=axi_ic_smoke_test
SEED=1
VERB=UVM_MEDIUM
WAVES=0
GUI=0
while getopts "t:s:v:wg" o; do
    case $o in
        t) TEST=$OPTARG ;;
        s) SEED=$OPTARG ;;
        v) VERB=$OPTARG ;;
        w) WAVES=1 ;;
        g) GUI=1 ;;
        *) exit 1 ;;
    esac
done

ARGS=(-f file.f -uvm -uvmhome CDNS-1.2 -top axi_ic_tb_top
      -access +rwc -timescale 1ns/1ps -sv
      -coverage functional -covoverwrite -covtest "$TEST"
      +UVM_TESTNAME=$TEST +UVM_VERBOSITY=$VERB -svseed "$SEED"
      -define AXI4L_ADDR_W=${AXI4L_ADDR_W:-32} -define AXI4L_DATA_W=${AXI4L_DATA_W:-32}
      -l "xrun_${TEST}.log")

if [ "$GUI" = 1 ]; then
    ARGS+=(-gui)
elif [ "$WAVES" = 1 ]; then
    ARGS+=(-input "@database -open waves -shm -default; probe -create -all -depth all; run; exit")
else
    ARGS+=(-input "@run; exit")
fi

xrun "${ARGS[@]}"
