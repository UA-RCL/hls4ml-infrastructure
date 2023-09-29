#!/bin/bash

source setup_env.sh

# bash amgic for "set this variable to this val" if it isn't already set
# note: this path is defined relative to ip_sources/python, not the top-level folder!
: "${HLS4ML_PROJECT_NAME:=hls4ml_project_name}"
: "${HLS4ML_PROJECT_PATH:=../hls/hls4ml_project_name}"

: "${HLS4ML_WEIGHTS_PATH:=./weights/weights.h5}"
# : "${HLS4ML_TEST_DATA_PATH:=./inputs/data.npz}"
: "${HLS4ML_TEST_DATA_PATH:=}"
: "${HLS4ML_EXECUTE_CSYNTH:=False}"
: "${HLS4ML_EXECUTE_VSYNTH:=False}"
: "${HLS4ML_QUANTIZERS_TO_MODIFY:=}"
: "${HLS4ML_BIG_QUANTIZER:=ap_fixed<64,32,AP_RND_CONV,AP_SAT>}"

export HLS4ML_PROJECT_NAME \
       HLS4ML_PROJECT_PATH \
       HLS4ML_WEIGHTS_PATH \
       HLS4ML_TEST_DATA_PATH \
       HLS4ML_EXECUTE_CSYNTH \
       HLS4ML_EXECUTE_VSYNTH \
       HLS4ML_QUANTIZERS_TO_MODIFY \
       HLS4ML_BIG_QUANTIZER

pushd ip_sources/python >/dev/null

# assumes that whatever is calling this script has sourced appropriate venvs
python3 generate_hls4ml_proj.py

# Before we leave this directory, our HLS4ML Project Path is defined relative to this folder (tpyically)
# So we should store the "realpath" in a variable that makes sense back at the repo-root
hls_proj_realpath=`realpath ${HLS4ML_PROJECT_PATH}`
hls_proj_basename=`basename ${hls_proj_realpath}`

popd >/dev/null

# We don't want the zipped up project folder, it just clutters things
if [ -f ip_sources/hls/${hls_proj_basename}.tar.gz ]; then
  rm ip_sources/hls/${hls_proj_basename}.tar.gz
fi

# We want to use our own (much less fancy) project TCL script than theirs as it doesn't play nice with "manage_hls_projects.sh"
cp ip_sources/python/hls4ml_ip.tcl ${hls_proj_realpath}/${hls_proj_basename}.tcl
# And we don't want their project folder
if [ -d ${hls_proj_realpath}/myproject_prj ]; then
  rm -rf ${hls_proj_realpath}/myproject_prj
fi