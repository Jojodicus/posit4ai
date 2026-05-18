#!/bin/sh
cd posit-neuralnet/include
wget -O libtorch.zip https://download.pytorch.org/libtorch/cu130/libtorch-shared-with-deps-2.11.0%2Bcu130.zip
unzip libtorch.zip
rm libtorch.zip
