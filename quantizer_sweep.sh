#!/bin/bash

BASE_DIR=`realpath ./`
# Virtual env containing hls4ml
VENV_DIR=`realpath ./venv`
# Where will intermediate hls4ml projects be generated?
SWEEP_DIR=`realpath ./quantizer_sweep_results/2023-09-21`
# What test data should we use?
TEST_DATA_PATH=`realpath ./ip_sources/python/inputs/data.npz`
# What weights file are we using?
WEIGHTS_PATH=`realpath ./ip_sources/python/weights/weights.h5`
# Should we run csynth/vsynth?
EXECUTE_CSYNTH=True
EXECUTE_VSYNTH=True
# How many jobs should GNU Parallel run at once?
PARALLEL_JOBS=6

if [ -d "${SWEEP_DIR}" ]; then
  echo -n "Sweep directory already exists. Should I delete it and make a new one? (Y/N): "
  read -r LEGIT
  if [ "${LEGIT}" = "Y" ] || [ "${LEGIT}" = "y" ]; then
    echo "Okay, removing the old one and recreating"
    rm -rf "${SWEEP_DIR}"
    mkdir -p "${SWEEP_DIR}"
  else
    echo "Leaving the existing directory in place"
  fi
else
  echo "Creating sweep directory"
  mkdir -p "${SWEEP_DIR}"
fi

echo "Starting sweep in 5..."
sleep 1
echo "4..."
sleep 1
echo "3..."
sleep 1
echo "2..."
sleep 1
echo "1..."
sleep 1

gen_design() {
  if [ "$#" -ne 13 ]; then
    echo "Not enough arguments"
    echo "Received args: $@"
    exit 1
  fi

  JOB_NUM="${1}"
  BASE_DIR="${2}"
  VENV_DIR="${3}"
  SWEEP_DIR="${4}"
  TEST_DATA_PATH="${5}"
  WEIGHTS_PATH="${6}"
  EXECUTE_CSYNTH="${7}"
  EXECUTE_VSYNTH="${8}"

  source "${BASE_DIR}/setup_env.sh"
  source "${VENV_DIR}/bin/activate"

  proj_path="${SWEEP_DIR}/job-${JOB_NUM}_hls4ml_ip"
  quantizers_to_modify="${9}"
  int="${10}"
  frac="${11}"
  quant="${12}"
  overflow="${13}"
  big_quantizer="ap_fixed<${int},${frac},${quant},${overflow}>"

  # Generate and test design
  export HLS4ML_PROJECT_PATH="${proj_path}"
  export HLS4ML_QUANTIZERS_TO_MODIFY="${quantizers_to_modify}"
  export HLS4ML_BIG_QUANTIZER="${big_quantizer}"
  export HLS4ML_TEST_DATA_PATH="${TEST_DATA_PATH}"
  export HLS4ML_WEIGHTS_PATH="${WEIGHTS_PATH}"
  export HLS4ML_EXECUTE_CSYNTH="${EXECUTE_CSYNTH}"
  export HLS4ML_EXECUTE_VSYNTH="${EXECUTE_VSYNTH}"

  python "${BASE_DIR}/ip_sources/python/generate_hls4ml_proj.py" > "${SWEEP_DIR}/job-${JOB_NUM}.log" 2>&1
}
export -f gen_design

# Job number
# Base directory of this repository
# Base directory of venv containing hls4ml
# Base directory to store logs & generated projects in
# Path to test data (.npz)
# Path to weights (h5 or SavedModel)
# Whether to run CSYNTH
# Whether to run VSYNTH
# Which quantizers to modify
# int width of the modified quantizer
# frac width of the modified quantizer (paired up with the int-width line via the '+')
# quantization mode of the modified quantizer
# overflow mode of the modified quantizer

parallel --seqreplace "{jobnum}" --joblog "${SWEEP_DIR}/parallel.joblog" --resume-failed --eta --jobs ${PARALLEL_JOBS} --delay 15s \
  gen_design {jobnum} "${BASE_DIR}" "${VENV_DIR}" "${SWEEP_DIR}" \
             "${TEST_DATA_PATH}" "${WEIGHTS_PATH}" "${EXECUTE_CSYNTH}" "${EXECUTE_VSYNTH}" \
             {} \
             :::  "" "accum" "result" "accum,result" \
             :::  12 12 12 12 14 16 18 20 24 28 32 36 40 44 48 64 \
             :::+ 2  4  6  8  8  8  10 12 16 20 24 28 32 32 32 32 \
             :::  "AP_RND_CONV" \
             :::  "AP_SAT"