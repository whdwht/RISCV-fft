#!/usr/bin/env bash

# dc/compile.sh

make -C icc clean
make -C icc ic

make -C pt clean
make -C pt sta
make -C pt verify_sta