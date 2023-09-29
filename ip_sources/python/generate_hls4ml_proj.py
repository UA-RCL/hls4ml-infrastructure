from datetime import datetime
import json
import sys
import os
import numpy as np

import hls4ml

# from hls import make_architecture
# from qkeras.utils import load_qmodel

from tensorflow.keras.models import Sequential
from tensorflow.keras.layers import Dense, Conv2D, Flatten, MaxPooling2D, Dropout, Input, BatchNormalization, Activation
from tensorflow.keras import models, optimizers, losses

from qkeras.qlayers import QDense, QActivation
from qkeras.qconvolutional import QConv2D
from qkeras.quantizers import quantized_bits, quantized_relu

#### environment variables

project_path = os.getenv('HLS4ML_PROJECT_PATH', '../hls/hls4ml_network')
weights_path = os.getenv('HLS4ML_WEIGHTS_PATH', './weights/weights.h5')
# What should the word/int widths be for the I/O of this neural network?
interface_word_width = int(os.getenv('HLS4ML_WORD_WIDTH', 12))
interface_int_width  = int(os.getenv('HLS4ML_INT_WIDTH', 2))
interface_frac_width = interface_word_width - interface_int_width
assert(interface_frac_width > 0, f"interface_frac_width should be greater than zero but was {interface_frac_width}")
# When generating, what quantizers should we modify (comma separated w/ no spaces) and what should we set them to?
quantizers_to_modify = os.getenv('HLS4ML_QUANTIZERS_TO_MODIFY', '')
modified_quantizer   = os.getenv('HLS4ML_BIG_QUANTIZER', 'ap_fixed<12, 2, AP_RND_CONV, AP_SAT>')
# What word/int widths were used when training this neural network?
training_word_width = 12
training_int_width  = 1
training_frac_width = training_word_width - training_int_width
assert(training_frac_width > 0, f"training_frac_width should be greater than zero but was {training_frac_width}")

vivado_path  = os.getenv('VIVADO_BIN_DIR', '/path/to/vivado/version/bin')
os.environ['PATH'] = f"{vivado_path}:{os.environ['PATH']}"

# Should we test the network and save metrics into the project directory?
test_data_path = os.getenv('HLS4ML_TEST_DATA_PATH', './inputs/test_data.npz')
execute_network_testing = test_data_path != ''

# Should we synthesize the resulting network as it's generated?
execute_hls_csynth = os.getenv('HLS4ML_EXECUTE_CSYNTH', 'False')
execute_hls_vsynth = os.getenv('HLS4ML_EXECUTE_VSYNTH', 'False')

execute_hls_csynth = execute_hls_csynth == 'True' or execute_hls_vsynth == 'True'
execute_hls_vsynth = execute_hls_vsynth == 'True'

#### hls4ml parameters

default_reuse_factor = 1
default_strategy     = 'Latency'
io_type              = 'io_stream'
fpga_part            = 'xczu9eg-ffvb1156-2-e'

interface_precision  = f'ap_fixed<{interface_word_width}, {interface_int_width}>'
default_precision    = f'ap_fixed<12, 4>'

if quantizers_to_modify != ['']:
  quantizers_to_modify = quantizers_to_modify.split(',')
else:
  quantizers_to_modify = []

# how well (in percent) do the keras and hls4ml networks need to match to move forward with synthesis?
keras_hls4ml_match_threshold = 75.0

#### neural network generation

def generate_hls4ml_config(model, output_dir = project_path):
  print(f"Will modify quantizers: {quantizers_to_modify} and make them use {modified_quantizer}")

  layer_cfg = hls4ml.utils.config_from_keras_model(model, granularity='name')
  layer_cfg['Model']['ReuseFactor'] = default_reuse_factor
  layer_cfg['Model']['Precision']   = default_precision
  layer_cfg['Model']['Strategy']    = default_strategy

  # TODO: make sure the input_key and output_key variables match what are used by the network under test
  # Or update the code in this part to be smarter about detecting input/output layers of the architecture (layers with no parents/children, etc)
  input_key  = 'input_layer'
  output_key = 'output_layer'
  print(f"Setting input_layer and output_layer precision to {interface_precision}")
  layer_cfg['LayerName'][input_key ]['Precision'] = interface_precision
  layer_cfg['LayerName'][output_key]['Precision'] = interface_precision
  layer_cfg['LayerName'][output_key]['Strategy']  = 'Stable'

  for layer in layer_cfg['LayerName'].keys():
    # If this layer config has a precision attribute we can modify
    if isinstance(layer_cfg['LayerName'][layer]['Precision'], dict):
      if 'result' in quantizers_to_modify and 'result' in layer_cfg['LayerName'][layer]['Precision']:
        layer_cfg['LayerName'][layer]['Precision']['result'] = modified_quantizer
      if 'accum' in quantizers_to_modify:
        layer_cfg['LayerName'][layer]['Precision']['accum']  = modified_quantizer
  
  hls4ml_cfg = hls4ml.converters.create_config(backend='Vivado')
  hls4ml_cfg['IOType']     = io_type
  hls4ml_cfg['HLSConfig']  = layer_cfg
  hls4ml_cfg['KerasModel'] = model
  hls4ml_cfg['OutputDir']  = output_dir
  hls4ml_cfg['XilinxPart'] = fpga_part

  return hls4ml_cfg

# Probably stolen from stackoverflow somewhere along the line. It recursively prints dictionaries in a nice way
def print_cfg_dict(d, indent=0, file=sys.stdout):
  align=20
  for key, val in d.items():
    print('  ' * indent + str(key), end='', file=file)
    if isinstance(val, dict):
      print(file=file)
      print_cfg_dict(val, indent+1, file=file)
    else:
      print(':' + ' ' * (20 - len(key) - 2 * indent) + str(val), file=file) 

def generate_hls4ml_model(keras_model, output_dir=project_path):
  print("Setting up HLS project with hls4ml...")

  hls4ml_cfg = generate_hls4ml_config(keras_model, output_dir=output_dir)
  hls_model = hls4ml.converters.keras_to_hls(hls4ml_cfg)
  hls_model.compile()
  sys.stdout.flush()
  sys.stderr.flush()

  print(f'Dumping initial parameter settings to {output_dir}/.project_info')

  params_dict = {
    "interface_word_width" : interface_word_width,
    "interface_int_width"  : interface_int_width,
    "training_word_width"  : training_word_width,
    "training_int_width"   : training_int_width,
    "interface_precision"  : interface_precision,
    "default_precision"    : default_precision,
    "quantizers_to_modify" : quantizers_to_modify,
    "modified_quantizer"   : modified_quantizer,
    "default_reuse_factor" : default_reuse_factor,
    "default_strategy"     : default_strategy,
    "io_type"              : io_type
  }

  with open(f"{output_dir}/.project_info", "w") as fp:
    fp.write(f"Project generated via {sys.argv[0]} for FPGA part {fpga_part} at {datetime.now()}\n\n")

    fp.write(f"The neural network was initialized with {weights_path} and had the following architecture summary:\n")
    keras_model.summary(print_fn=lambda str: print(str, file=fp))
    fp.write("\n\n")

    fp.write(f"The corresponding hls4ml configuration dictionary was:\n")
    print_cfg_dict(hls4ml_cfg, file=fp)

    fp.write(f"The hls4ml parameters used were:\n")
    fp.write(f"{json.dumps(params_dict, indent=2)}")
    fp.write("\n\n")
  
  return hls_model

def load_model(weights_path):
  raise NotImplemented("This method needs to be defined for a particular neural network model/architecture")
  
  # An approximation of a working QKeras-based network is below
  in_shape = (26, 26, 1)
  out_shape = (10, 1)

  quant_relu   = quantized_relu(training_word_width)
  kernel_quant = quantized_bits(training_word_width, training_int_width, symmetric=0, alpha=1)
  bias_quant   = quantized_bits(training_word_width, training_int_width, symmetric=0, alpha=1)

  in_layer = Input(in_shape)
  x = in_layer
  x = QConv2D(filters=8,
              kernel_size=5,
              strides=2,
              padding='valid',
              kernel_quantizer=kernel_quant,
              bias_quantizer=bias_quant,
              kernel_initializer='glorot_uniform',
              name='input_layer')(x)
  x = QActivation(activation=quant_relu)(x)
  x = MaxPooling2D(pool_size=2, padding='valid')(x)
  x = Dropout(rate=0.5)(x)
  x = Flatten()(x)
  x = QDense(8, kernel_quantizer=kernel_quant, bias_quantizer=bias_quant)(x)
  x = QActivation(activation=quant_relu)(x)
  x = Dropout(rate=0.5)(x)
  x = QDense(out_shape[0], kernel_quantizer=kernel_quant, bias_quantizer=bias_quant)(x)
  x = Activation(activation='softmax', name='output_layer')(x)
  out_layer = x

  model = models.Model(in_layer, out_layer)
  model.loss_func = losses.CategoricalCrossentropy()
  model.opt = optimizers.Adam(learning_rate=0.001)

  model.build(in_shape)

  return model

def load_data(test_data_path):
  raise NotImplemented("This method needs to be defined based on a particular set of test data")

def compare_predictions(predicted_classes, baseline_classes):
  raise NotImplemented("This method needs to be defined based on a particular set of test data")

def test_networks(test_data_path, keras_model, hls_model):
  print("Loading test data...", flush=True)
  samples, true_classes = load_data(test_data_path)
  num_outputs = len(true_classes)
  
  print("Performing inference with the keras model", flush=True)
  keras_pred = keras_model.predict(samples)
  keras_classes = np.argmax(keras_pred, axis=1)

  print("Performing inference with the hls4ml model", flush=True)
  hls4ml_pred = hls_model.predict(samples)
  hls4ml_classes = np.argmax(hls4ml_pred, axis=1)

  match_pct_keras  = compare_predictions(keras_classes, true_classes)
  match_pct_hls4ml = compare_predictions(hls4ml_classes, true_classes)
  match_pct_keras_hls4ml = compare_predictions(hls4ml_classes, keras_classes)

  # TODO: Optionally, do something to compare or serialize failing matches to disk

  print(f"Num samples: {num_outputs}, Keras: {match_pct_keras:.2f}%, hls4ml: {match_pct_hls4ml:.2f}%, Keras-hls4ml: {match_pct_keras_hls4ml:.2f}%", flush=True)
  return num_outputs, match_pct_keras, match_pct_hls4ml, match_pct_keras_hls4ml

if __name__ == "__main__":
  print("Beginning generation of hls4ml C++ project")

  print()
  print("Plan: ")
  print("\t - Load keras model")
  print("\t - Generate the hls4ml network")
  if execute_network_testing:
    print(f"\t - Test Keras and hls4ml models against the data in {test_data_path}")
  if execute_hls_csynth:
    print(f"\t - Execute C++ to Verilog HLS synthesis")
  if execute_hls_vsynth:
    print(f"\t - Execute Verilog RTL synthesis")
  print(f"\t - Serialize the results to {project_path}/.project_info")
  print()

  print("Relevant environment variables:")
  print()
  print(f"Vivado Path: {vivado_path}")
  print(f"Project Path: {project_path}")
  print(f"Weights Path: {weights_path}")
  print()

  print("Generating neural network")

  model = load_model(weights_path)

  print("Neural network generated")

  hls_model = generate_hls4ml_model(model, output_dir=project_path)

  if execute_network_testing:
    print("Received a non-null test data path. Testing networks prior to synthesis")
    num_samples, keras_pct, hls4ml_pct, keras_hls4ml_pct = test_networks(test_data_path, model, hls_model)

    with open(f"{project_path}/.project_info", "a") as fp:
      fp.write(f"Both models were tested against {num_samples} test samples")
      fp.write(f"The keras model achieved an accuracy of: {keras_pct:.2f}%\n")
      fp.write(f"The hls4ml model achieved an accuracy of: {hls4ml_pct:.2f}%\n")
      fp.write(f"The hls4ml model matched the keras model {keras_hls4ml_pct:.2f}% of the time\n")

      if keras_hls4ml_pct <= keras_hls4ml_match_threshold:
        fp.write(f"Network fails to meet match threshold of {keras_hls4ml_match_threshold}%. Skipping build of network")
        sys.exit(0)
    
  print("Calling hls_model.build(...)")

  hls_model.build(reset=True, csim=False, synth=execute_hls_csynth, cosim=False, validation=False, export=False, vsynth=execute_hls_vsynth)
  sys.stdout.flush()
  sys.stderr.flush()

  print(f"hls_model.build(...) is complete. Serializing results to {project_path}/.project_info if csynth or vsynth were run")

  with open(f"{project_path}/.project_info", "a") as fp:
    if execute_hls_csynth:
      fp.write("C++ to Verilog HLS synthesis was performed\n")
      fp.write("Dumping HLS csynth report:\n\n")
      with open(f"{project_path}/myproject_prj/solution1/syn/report/myproject_csynth.rpt", "r") as csynth_fp:
        fp.write(csynth_fp.read())
      fp.write("\n\n")
    
    if execute_hls_vsynth:
      fp.write("Verilog synthesis was performed\n")
      fp.write("Dumping Vivado synthesis report:\n\n")
      with open(f"{project_path}/vivado_synth.rpt", "r") as vsynth_fp:
        fp.write(vsynth_fp.read())
      fp.write("\n\n")