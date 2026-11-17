./run.sh
xrun -f file.f -top tb_axi_lite_2x9 -access +rwc -timescale 1ns/1ps -input "@database -open waves -shm -default; probe -create -all -depth all; run; exit"
