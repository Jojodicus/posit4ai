#! /bin/sh

if [ ! -f zedboard.xsa ]
then
    echo "XSA missing, implementation was probably not run, running implementation..."
    ./impl.sh
fi

wget -O zedboard.bsp https://github.com/ubfx/zedboard-bsp/releases/download/2024.2/zedboard-2024.2.bsp
