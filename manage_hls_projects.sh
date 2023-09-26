#!/bin/bash

CLEAN_FLAG=false
BUILD_FLAG=false
TEST_FLAG=false
EXPORT_FLAG=false
CLEAN_EXPORT_FLAG=false

# These modules should be folders within ip_sources/hls that contain C++ source files + a Vivado HLS build TCL script
HLS_MODULES=${HLS_MODULES:=""}
# If using the --export flag, where should IP be exported to?
HLS_EXPORT_DIR=${HLS_EXPORT_DIR:="$(realpath ip_artifacts)"}

# Where are the HLS module folders located relative to this script?
HLS_MODULE_DIR="$(realpath ip_sources/hls)"

print_usage() {
  echo ""
  echo "Usage: "
cat << EOF

  ${0} [-h|--help]
  ${0} --clean [projects...]
  ${0} --build [projects...]
  ${0} --test [projects...]
  ${0} --export [projects...]
  ${0} --clean-export [projects...]

  This script is used to clean, generate, or export artifacts from the provided Vivado HLS projects.
  If no modules are specified, the following modules will be processed:

    ${HLS_MODULES}

  Options:
    [--clean]
      Used to remove the generated artifacts associated with a given module or set of modules
    [--build]
      Used to build a given module or set of modules. Typically, each module will be "cleaned" prior to building via its TCL script.
    [--test]
      Executes tests for the underlying module or set of modules (if any are specific in their TCL scripts).
    [--export]
      Used to export generated artifacts associated with a given module or set of modules.
      If a given artifact is not build, it triggers a build before exporting.
      The export location is generally expected to be used as a Vivado IP repository folder.
    [--clean-export]
      Used to clean the export directory set by HLS_EXPORT_DIR (current value: ${HLS_EXPORT_DIR})

EOF
}

clean_hls_project() {
  # Do we have enough arguments?
  if [ "$#" -ne 1 ]; then
    echo "${FUNCNAME[0]}: Missing argument <project_name>"
    return 1
  fi

  # Did the one argument we get make sense?
  case $1 in
  -*)
    echo "${FUNCNAME[0]}: Expecting argument to be a folder name"
    return 1
    ;;
  *)
    # Make sure we're trimming a slash if the user put any
    # Since we're going to staple .tcl onto the end
    PROJECT_NAME=$(echo $1 | sed 's:/*$::')
    ;;
  esac

  # Does this argument correspond to a project directory?
  if [ ! -d "${PROJECT_NAME}" ]; then
    echo "${FUNCNAME[0]}: ${PROJECT_NAME} directory does not exist. Giving up!"
    return 1
  fi

  pushd "${PROJECT_NAME}" >/dev/null

  # Does this project have an old project directory?
  if [ -d "${PROJECT_NAME}.proj" ]; then
    echo "${FUNCNAME[0]}: Removing old project directory"
    (set -x; rm -rf "${PROJECT_NAME}.proj")
  else
    echo "${FUNCNAME[0]}: No old project directory to clean"
  fi

  # Any messy log files to clean up?
  if stat -t ${PROJECT_NAME}_*.log >/dev/null 2>&1; then
    echo "${FUNCNAME[0]}: Removing old log files"
    (set -x; rm ${PROJECT_NAME}_*.log)
  else
    echo "${FUNCNAME[0]}: No old log files to remove"
  fi

  popd >/dev/null

  echo ""
  echo "Your project is squeaky clean!"
  return 0;
}

build_hls_project() {
  # Do we have enough arguments?
  if [ "$#" -ne 1 ]; then
    echo "${FUNCNAME[0]}: Missing argument <project_name>"
    return 1
  fi

  # Did the one argument we get make sense?
  case $1 in
  -*)
    echo "${FUNCNAME[0]}: Expecting argument to be a folder name"
    return 1
    ;;
  *)
    # Make sure we're trimming a slash if the user put any
    # Since we're going to staple .tcl onto the end
    PROJECT_NAME=$(echo $1 | sed 's:/*$::')
    ;;
  esac

  # Does this argument correspond to a project directory?
  if [ ! -d "${PROJECT_NAME}" ]; then
    echo "${FUNCNAME[0]}: ${PROJECT_NAME} directory does not exist. Giving up!"
    return 1
  fi

  pushd "${PROJECT_NAME}" >/dev/null

  # Does this project have a TCL script to source?
  if [ ! -f "${PROJECT_NAME}.tcl" ]; then
    echo "${FUNCNAME[0]}: ${PROJECT_NAME}.tcl does not exist"
    return 1
  fi

  # Do we have vivado_hls available?
  if ! type vivado_hls >/dev/null 2>&1; then
    echo "${FUNCNAME[0]}: Vivado HLS is not on the current PATH. Please source the appropriate environment script and try again"
    return 1
  fi

  # Run the build process
  STAMP=$(date "+%Y.%m.%d-%H.%M.%S")
  vivado_hls -f "${PROJECT_NAME}.tcl" -l "${PROJECT_NAME}_build_${STAMP}.log" tclargs "build"
  retval="$?"

  echo -e "\n\n"
  if [ "${retval}" -eq 0 ]; then
    echo -e "${FUNCNAME[0]}: Vivado HLS returned a status code of 0, so everything's probably fine (but check \"${PROJECT_NAME}/${PROJECT_NAME}_build_${STAMP}.log\" for details)\n"
    popd >/dev/null
    return 0
  else
    echo -e "${FUNCNAME[0]}: Vivado HLS returned a non-zero status code. Might want to check \"${PROJECT_NAME}/${PROJECT_NAME}_build_${STAMP}.log\" for details)\n"
    popd >/dev/null
    return 1
  fi
}

test_hls_project() {
  # Do we have enough arguments?
  if [ "$#" -ne 1 ]; then
    echo "${FUNCNAME[0]}: Missing argument <project_name>"
    return 1
  fi

  # Did the one argument we get make sense?
  case $1 in
  -*)
    echo "${FUNCNAME[0]}: Expecting argument to be a folder name"
    return 1
    ;;
  *)
    # Make sure we're trimming a slash if the user put any
    # Since we're going to staple .tcl onto the end
    PROJECT_NAME=$(echo $1 | sed 's:/*$::')
    ;;
  esac

  # Does this argument correspond to a project directory?
  if [ ! -d "${PROJECT_NAME}" ]; then
    echo "${FUNCNAME[0]}: ${PROJECT_NAME} directory does not exist. Giving up!"
    return 1
  fi

  pushd "${PROJECT_NAME}" >/dev/null

  # Does this project have a TCL script to source?
  if [ ! -f "${PROJECT_NAME}.tcl" ]; then
    echo "${FUNCNAME[0]}: ${PROJECT_NAME}.tcl does not exist"
    return 1
  fi

  # Do we have vivado_hls available?
  if ! type vivado_hls >/dev/null 2>&1; then
    echo "${FUNCNAME[0]}: Vivado HLS is not on the current PATH. Please source the appropriate environment script and try again"
    return 1
  fi

  # Run the testing process
  STAMP=$(date "+%Y.%m.%d-%H.%M.%S")
  vivado_hls -f "${PROJECT_NAME}.tcl" -l "${PROJECT_NAME}_build_${STAMP}.log" tclargs "test"
  retval="$?"

  echo -e "\n\n"
  if [ "${retval}" -eq 0 ]; then
    echo -e "${FUNCNAME[0]}: Vivado HLS returned a status code of 0, so everything's probably fine (but check \"${PROJECT_NAME}/${PROJECT_NAME}_build_${STAMP}.log\" for details)\n"
    popd >/dev/null
    return 0
  else
    echo -e "${FUNCNAME[0]}: Vivado HLS returned a non-zero status code. Might want to check \"${PROJECT_NAME}/${PROJECT_NAME}_build_${STAMP}.log\" for details)\n"
    popd >/dev/null
    return 1
  fi
}

export_hls_project() {
  # Do we have enough arguments?
  if [ "$#" -ne 1 ]; then
    echo "${FUNCNAME[0]}: Missing argument <project_name>"
    return 1
  fi

  # Did the one argument we get make sense?
  case $1 in
  -*)
    echo "${FUNCNAME[0]}: Expecting argument to be a folder name"
    return 1
    ;;
  *)
    # Make sure we're trimming a slash if the user put any
    # Since we're going to staple .tcl onto the end
    PROJECT_NAME=$(echo $1 | sed 's:/*$::')
    ;;
  esac

  # Does this argument correspond to a project directory?
  if [ ! -d "${PROJECT_NAME}" ]; then
    echo "${FUNCNAME[0]}: ${PROJECT_NAME} directory does not exist. Giving up!"
    return 1
  fi

  # Does this project have a generated project directory?
  if [ -d "${PROJECT_NAME}/${PROJECT_NAME}.proj" ]; then
    echo "${FUNCNAME[0]}: Project directory exists. No need to build prior to export."
  else
    echo "${FUNCNAME[0]}: Project directory does not exist. Building prior to export."
    build_hls_project ${PROJECT_NAME}
    if [ "$?" -ne 0 ]; then
      echo "${FUNCNAME[0]}: Project build prior to export failed"
      return 1
    fi
  fi

  echo "${FUNCNAME[0]}: Exporting ${PROJECT_NAME} IP to ${HLS_EXPORT_DIR}/${PROJECT_NAME}"

  mkdir -p "${HLS_EXPORT_DIR}/${PROJECT_NAME}"
  (set -x; rsync -a "${PROJECT_NAME}/${PROJECT_NAME}.proj/soln/impl/ip/" "${HLS_EXPORT_DIR}/${PROJECT_NAME}/" --delete)

  echo -e "${FUNCNAME[0]}: IP export complete for ${PROJECT_NAME}\n"

  return 0
}

clean_export_for_module() {
  # Do we have enough arguments?
  if [ "$#" -ne 1 ]; then
    echo "${FUNCNAME[0]}: Missing argument <project_name>"
    return 1
  fi

  # Did the one argument we get make sense?
  case $1 in
  -*)
    echo "${FUNCNAME[0]}: Expecting argument to be a folder name"
    return 1
    ;;
  *)
    # Make sure we're trimming a slash if the user put any
    # Since we're going to staple .tcl onto the end
    PROJECT_NAME=$(echo $1 | sed 's:/*$::')
    ;;
  esac

  # Does this argument correspond to a directory of an exported IP?
  if [ ! -d "${HLS_EXPORT_DIR}/${PROJECT_NAME}" ]; then
    echo "${FUNCNAME[0]}: Directory ${HLS_EXPORT_DIR}/${PROJECT_NAME} does not exist. Nothing to clean..."
  else
    echo "${FUNCNAME[0]}: Removing directory ${HLS_EXPORT_DIR}/${PROJECT_NAME}"
    (set -x; rm -rf ${HLS_EXPORT_DIR}/${PROJECT_NAME})
  fi
  echo ""

  return 0
}

### Main logic of the script ###

if [ "$#" -lt 1 ]; then
  print_usage
  exit 1
fi

while (( "$#" )); do
  case $1 in
    -h|--help)
      print_usage
      exit 0
      ;;
    --build)
      BUILD_FLAG=true
      shift 1
      ;;
    --test)
      TEST_FLAG=true
      shift 1
      ;;
    --clean)
      CLEAN_FLAG=true
      shift 1
      ;;
    --export)
      EXPORT_FLAG=true
      shift 1
      ;;
    --clean-export)
      CLEAN_EXPORT_FLAG=true
      shift 1
      ;;
    *)
      HLS_MODULES="$@"
      break
      ;;
  esac
done

echo "Entering directory ${HLS_MODULE_DIR}"
pushd ${HLS_MODULE_DIR} >/dev/null

if [ "${CLEAN_FLAG}" = true ]; then
  echo ""
  echo "Cleaning modules"
cat <<EOF

    ${HLS_MODULES}

EOF

  for module in ${HLS_MODULES}; do
    clean_hls_project ${module}
    if [ "$?" -ne 0 ]; then
      echo "clean_hls_project returned with an error, exiting..."
      exit 1
    fi
  done
fi

if [ "${BUILD_FLAG}" = true ]; then
  echo ""
  echo "Building modules"
cat <<EOF

    ${HLS_MODULES}

EOF

  for module in ${HLS_MODULES}; do
    build_hls_project ${module}
    if [ "$?" -ne 0 ]; then
      echo "build_hls_project returned with an error, exiting..."
      exit 1
    fi
  done
fi

if [ "${TEST_FLAG}" = true ]; then
  echo ""
  echo "Testing modules"
cat <<EOF

    ${HLS_MODULES}

EOF

  for module in ${HLS_MODULES}; do
    test_hls_project ${module}
    if [ "$?" -ne 0 ]; then
      echo "test_hls_project returned with an error, exiting..."
      exit 1
    fi
  done
fi

if [ "${EXPORT_FLAG}" = true ]; then
  echo ""
  echo "Exporting modules"
cat <<EOF

    ${HLS_MODULES}

EOF

  for module in ${HLS_MODULES}; do
    export_hls_project ${module}
    if [ "$?" -ne 0 ]; then
      echo "export_hls_project returned with an error, exiting..."
      exit 1
    fi
  done
fi

if [ "${CLEAN_EXPORT_FLAG}" = true ]; then
  echo ""
  echo "Cleaning the export directory for modules"
cat <<EOF

    ${HLS_MODULES}

EOF

  for module in ${HLS_MODULES}; do
    clean_export_for_module ${module}
    if [ "$?" -ne 0 ]; then
      echo "clean_export_for_module returned with an error, exiting..."
      exit 1
    fi
  done
fi

popd >/dev/null
exit 0