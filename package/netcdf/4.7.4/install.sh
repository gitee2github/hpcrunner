#!/bin/bash

set -x
set -e
netcdf_c_version='4.7.4'
netcdf_f_version='4.5.3'
. ${DOWNLOAD_TOOL} -u https://codeload.github.com/Unidata/netcdf-fortran/tar.gz/refs/tags/v${netcdf_f_version} -f netcdf-fortran-${netcdf_f_version}.tar.gz
. ${DOWNLOAD_TOOL} -u https://codeload.github.com/Unidata/netcdf-c/tar.gz/refs/tags/v${netcdf_c_version} -f netcdf-c-${netcdf_c_version}.tar.gz 
cd ${JARVIS_TMP}
rm -rf netcdf-c-${netcdf_c_version} netcdf-fortran-${netcdf_f_version}
tar -xvf ${JARVIS_DOWNLOAD}/netcdf-c-${netcdf_c_version}.tar.gz
tar -xvf ${JARVIS_DOWNLOAD}/netcdf-fortran-${netcdf_f_version}.tar.gz
cd netcdf-c-${netcdf_c_version}
if [ x"$(arch)" = xaarch64 ];then
    build_type='--build=aarch64-unknown-linux-gnu'
else
    build_type=''
fi
HDF5_DIR=${1%/*/*}/hdf5/1.8.12
PNETCDF_DIR=${1%/*/*}/pnetcdf/1.11.2
./configure --prefix=$1 ${build_type} --disable-shared --enable-netcdf-4 --disable-dap --with-pic --disable-doxygen --enable-static --enable-pnetcdf --enable-largefile CPPFLAGS="-O3 -I${HDF5_DIR}/include -I${PNETCDF_DIR}/include" LDFLAGS="-L${HDF5_DIR}/lib -L${PNETCDF_DIR}/lib -Wl,-rpath=${HDF5_DIR}/lib -Wl,-rpath=${PNETCDF_DIR}/lib" CFLAGS="-O3 -L${HDF5_DIR}/lib -L${PNETCDF_DIR}/lib -I${HDF5_DIR}/include -I${PNETCDF_DIR}/include"

make -j16
make install

export PATH=$1/bin:$PATH
export LD_LIBRARY_PATH=$1/lib:$LD_LIBRARY_PATH
export NETCDF=${1}

cd ../netcdf-fortran-${netcdf_f_version}
./configure --prefix=$1 ${build_type} --disable-shared --with-pic --disable-doxygen --enable-largefile --enable-static CPPFLAGS="-O3 -I${HDF5_DIR}/include -I${1}/include" LDFLAGS="-L${HDF5_DIR}/lib -L${1}/lib -Wl,-rpath=${HDF5_DIR}/lib -Wl,-rpath=${1}/lib" CFLAGS="-O3 -L${HDF5_DIR}/HDF5/lib -L${1}/lib -I${HDF5_DIR}/include -I${1}/include" CXXFLAGS="-O3 -L${HDF5_DIR}/lib -L${1}/lib -I${HDF5_DIR}/include -I${1}/include" FCFLAGS="-O3 -L${HDF5_DIR}/lib -L${1}/lib -I${HDF5_DIR}/include -I${1}/include"
make -j16
make install
