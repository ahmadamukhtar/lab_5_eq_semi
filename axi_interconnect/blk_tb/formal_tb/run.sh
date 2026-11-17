#!/bin/bash
# Usage: ./run.sh [-p p0..p7] [-d "EXTRA DEFINES"] [-g]   (-g = GUI)
JG=${JG:-/home/icdesign/cadence/installs/Jasper_2019/bin/jg}
cd "$(dirname "$0")"
export FV_PROFILE=p7 FV_DEFS=""
GUI=0
while getopts "p:d:g" o; do
  case $o in p) FV_PROFILE=$OPTARG;; d) FV_DEFS=$OPTARG;; g) GUI=1;; esac
done
export FV_PROFILE FV_DEFS
B="-batch"; [ $GUI = 1 ] && { B=""; export FV_GUI=1; }
$JG -fpv -allow_unsupported_OS $B tool/jg.tcl -proj jg_run/$FV_PROFILE 2>&1 | tee jg_$FV_PROFILE.log
