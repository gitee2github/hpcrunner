#!/bin/bash
set -e
cd ${JARVIS_TMP}
tar -xvf ${JARVIS_DOWNLOAD}/fftw-3.3.8.tar.gz
cd fftw-3.3.8
./configure --prefix=$1 MPICC=mpicc --enable-shared --enable-threads --enable-openmp --enable-mpi
make -j install