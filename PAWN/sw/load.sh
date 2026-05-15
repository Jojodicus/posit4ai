#!/bin/bash
mkdir -p /lib/firmware
echo 0 > /sys/class/fpga_manager/fpga0/flags

if [ -z $1 ];
then
        cp /home/root/pawn/zynq_accel_top.bin /lib/firmware/
        echo zynq_accel_top.bin > /sys/class/fpga_manager/fpga0/firmware
else
        echo $(basename $1) > /sys/class/fpga_manager/fpga0/firmware
fi
devmem 0xF8000008 32 0xDF0D   # SLCR unlock
devmem 0xF8000240 32 0x0      # deassert PL resets
devmem 0xF8000004 32 0x767B   # SLCR lock
sleep 2
