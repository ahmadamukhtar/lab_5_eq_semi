#!/usr/bin/env bash

/clean.sh
rm -f xrun.log
xrun -64bit -f sources.f -top top -access +rwc "$@" 2>&1 | tee xrun.log
grep -q 'MEMORY_CLEAR_PASS checks=32' xrun.log
grep -q 'MEMORY_ADDRESS_PASS checks=32' xrun.log
grep -q 'LAB5_MEMORY_INTERFACE_PASS total_checks=64' xrun.log
echo "LAB 5 ACTIVITY 2: PASS"
