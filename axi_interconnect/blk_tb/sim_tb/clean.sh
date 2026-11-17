#!/bin/bash
# Remove simulation outputs.
cd "$(dirname "$0")" || exit 1
rm -rf cov_work xcelium.d waves.shm xrun.history xrun.log xrun_*.log xrun_*.history .simvision *.key
