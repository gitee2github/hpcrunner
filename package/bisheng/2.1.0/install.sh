#!/bin/bash
set -e
. ${DOWNLOAD_TOOL} -u https://mirrors.huaweicloud.com/kunpeng/archive/compiler/bisheng_compiler/bisheng-compiler-2.1.0-aarch64-linux.tar.gz
cd ${JARVIS_TMP}
. $CHECK_ROOT && yum -y install libatomic libstdc++ libstdc++-devel
tar xzvf ${JARVIS_DOWNLOAD}/bisheng-compiler-2.1.0-aarch64-linux.tar.gz -C $1 --strip-components=1