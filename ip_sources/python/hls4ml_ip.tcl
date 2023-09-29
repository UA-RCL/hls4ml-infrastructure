# Create project
open_project $env(HLS4ML_PROJECT_NAME).proj
set_top myproject

# Add files to the project
add_files firmware/myproject.cpp -cflags "-std=c++0x"
add_files -tb myproject_test.cpp -cflags "-std=c++0x"
add_files -tb firmware/weights
add_files -tb tb_data

# Open a "solution" and configure synthesis parameterse
open_solution "soln"
config_array_partition -maximum_size 8192
config_compile -name_max_length 60
set_part {xczu9eg-ffvb1156-2-e}
create_clock -period 5 -name default

set received_tclargs 0

if { $argc > 0 } {
  foreach arg $argv {
    # For whatever reason, our argv array also includes all the arguments to vivado_hls. Ignore those.
    # Continue until we get a "tclargs" flag at which point these are our arguments
    if { $arg != "tclargs" && $received_tclargs == 0 } {
      continue
    }
    if { $arg == "tclargs" } {
      set received_tclargs 1
      continue
    }
    puts "Received arg: $arg"
    if { $arg == "build" } {
      puts "Building and (locally) exporting an IP for design: hls4ml IP"
      config_rtl -reset state
      csynth_design
      export_design -rtl verilog \
                    -format ip_catalog \
                    -description "An IP generated via hls4ml" \
                    -vendor "UA" \
                    -library "UA-Lib" \
                    -version "1.$env(NN_VERSION)" \
                    -ipname  "hls4ml_nn" \
                    -display_name "hls4ml_nn"
    }
    if { $arg == "test" } {
      puts "Executing tests for generated hls4ml IP design via C simulation and C/RTL co-simulation"
      csim_design
      # Just add the file again with -DRTL_SIM I guess and then it works? It's what the hls4ml peoples' default TCL script does for csim vs cosim
      add_files -tb myproject_test -cflags "-std=c++0x -DRTL_SIM"
      cosim_design
    }
  }
}

# Exit so that vivado_hls doesn't quit to an interactive session
exit