#download from https://support.hdfgroup.org/ftp/HDF5/releases/hdf5-1.10/hdf5-1.10.1/src/hdf5-1.10.1.tar.gz
#!/bin/bash
set -x
set -e

cd ${JARVIS_TMP}
tar -xvf ${JARVIS_DOWNLOAD}/hdf5-1.10.1.tar.gz
cd hdf5-1.10.1
#CC=mpicc CXX=mpicxx FC=mpifort F77=mpifort -Wno-incompatible-pointer-types-discards-qualifiers
./configure --prefix=$1 --build=aarch64-unknown-linux-gnu --build=aarch64-unknown-linux-gnu --enable-fortran --enable-static=yes --enable-parallel --enable-shared CFLAGS="-O3 -fPIC -Wno-incompatible-pointer-types-discards-qualifiers -Wno-non-literal-null-conversion" FCFLAGS="-O3 -fPIC" LDFLAGS="-Wl,--build-id"
sed -i '11835c wl="-Wl,"' libtool
make -j
make install