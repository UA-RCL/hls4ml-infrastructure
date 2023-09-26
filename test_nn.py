#!/usr/bin/env python3

import tempfile
import argparse
import sys
import os
os.environ['CUDA_VISIBLE_DEVICES'] = "-1"

import tensorflow as tf
import qkeras as qk
import numpy as np
np.set_printoptions(precision=2, suppress=True)
import hls4ml

sys.path.insert(0, "ip_sources/python/")

from generate_hls4ml_proj import vivado_path, weights_path, training_word_width, training_int_width, generate_hls4ml_model, print_cfg_dict, compare_predictions, load_model, load_data

tmpdir = tempfile.mkdtemp()

os.environ['PATH'] = f"{vivado_path}:{os.environ['PATH']}"

weights_path = os.path.join('ip_sources/python', weights_path)

def keras_test(model, test_data):
  print("Running keras model predictions")

  keras_predictions = model.predict(test_data)
  keras_classes = np.argmax(keras_predictions, axis=1)

  return keras_classes

def hls4ml_test(keras_model, test_data, synth=False, vsynth=False):
  # FIXME: "Creating the temp directory doesn't work" - Alex
  # with tempfile.TemporaryDirectory() as tmpdirname:
  #   project_path = os.path.abspath(os.path.join(tmpdirname, 'hls4ml_proj'))
  
  project_path = os.path.abspath('./hls4ml_test_proj')
  hls_model = generate_hls4ml_model(keras_model, output_dir=project_path)
  
  if (synth):
    hls_model.build(reset=True, synth=synth, vsynth=vsynth, csim=False, cosim=False, export=False)

  print(f"test data shape: {test_waterfalls.shape}")
  hls4ml_predictions = hls_model.predict(test_data)

  print(f"hls4ml predictions shape: {hls4ml_predictions.shape}")
  hls4ml_classes = np.argmax(hls4ml_predictions, axis=1)

  return hls4ml_classes

def check_sim_results(log_path, num_classes):
  predictions = []
  with open(log_path, 'r') as fp:
    for line in f.readlines():
      split_line = line.strip().split(' ')
      if len(split_line) == num_classes:
        predictions.append(np.argmax([float(p) for p in split_line]))
      else:
        print(f"ERROR: found a line with {len(split_line)} output numbers but expected {actual_classes.shape[0]}")

  return predictions

if __name__ == "__main__":
  parser = argparse.ArgumentParser()
  parser.add_argument("data_path", type=str, help="Path to numpy file with test data")
  # parser.add_argument("classes_path", type=str, "Path to numpy file with ground truth classes")
  parser.add_argument("-n", "--num", type=int, help="Number of samples to test", default=100)
  parser.add_argument("-k", "--keras", help="Test and compare QKeras model", action="store_true")
  parser.add_argument("-p", "--hls4ml", help="Test and compare hls4ml python model", action="store_true")
  parser.add_argument("-c", "--csim", type=str, help="Log file containing output from the C simulation")
  parser.add_argument("-r", "--cosim", type=str, help="Log file containing output from the C/RTL cosimulation")
  parser.add_argument("-s", "--synth", help="Run HLS synthesis of the model", action="store_true")
  parser.add_argument("-v", "--vsynth", help="Run Verilog synthesis of the model", action="store_true")

  args = parser.parse_args()

  if not args.synth and args.vsynth:
    print("HLS synthesis must be enabled in order to run Verilog synthesis")
    exit(os.EX_USAGE)

  if args.keras or args.hls4ml:
    keras_model = load_model(weights_path)

  test_samples, test_classes = load_data(args.data_path)
  num_classes = test_classes.shape[0]

  if args.keras:
    keras_classes = keras_test(keras_model, test_samples)
    keras_match_pct = compare_predictions(keras_classes, test_classes)
    print(f"The keras model matched the ground truth {keras_match_pct:.2f}% of the time")

  if args.hls4ml:
    hls4ml_classes = hls4ml_test(keras_model, test_samples, synth=args.synth, vsynth=args.vsynth)

    if args.keras:
      keras_hls4ml_match_pct = compare_predictions(hls4ml_classes, keras_classes)
      print(f"The hls4ml model matched the keras model {keras_hls4ml_match_pct:.2f}% of the time")

    hls4ml_match_pct = compare_predictions(hls4ml_classes, test_classes)
    print(f"The hls4ml model matched the ground truth {hls4ml_match_pct:.2f}% of the time")

  if args.csim:
    csim_classes = check_sim_results(args.csim, num_classes)

    if args.keras:
      keras_csim_match_pct = compare_classes(csim_classes, keras_classes)
      print(f"The C Simulation matched the keras model {keras_csim_match_pct:.2f}% of the time")

    if args.hls4ml:
      hls4ml_csim_match_pct = compare_classes(csim_classes, hls4ml_classes)
      print(f"The C Simulation matched the hls4ml python model {hls4ml_csim_match_pct:.2f}% of the time")

  if args.cosim:
    cosim_classes = check_sim_results(args.cosim, num_classes)

    if args.keras:
      keras_cosim_match_pct = compare_classes(cosim_classes, keras_classes)
      print(f"The C/RTL cosimulation matched the keras model {keras_cosim_match_pct:.2f}% of the time")

    if args.hls4ml:
      hls4ml_cosim_match_pct = compare_classes(cosim_classes, hls4ml_classes)
      print(f"The C/RTL cosimulation matched the hls4ml model {hls4ml_cosim_match_pct:.2f}% of the time")

    if args.csim:
      csim_cosim_match_pct = compare_classes(cosim_classes, csim_classes)
      print(f"The C/RTL cosimulation matched the csim model {csim_cosim_match_pct:.2f}% of the time")

    cosim_match_pct = compare_classes(cosim_classes, actual_classes)
    print(f"The C/RTL cosimulation matched the ground truth {cosim_match_pct:.2f}% of the time")