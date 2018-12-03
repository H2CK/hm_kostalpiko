#!/bin/sh
#
# wrapper script to execute hm_kostalpico in non-daemon
# mode with the possibility to run it a certain amount
# of time by specifying the maximum iterations and
# interval time as command-line options
#
# Example:
# -------
#
# Runs hm_kostalpico only once:
#
# $ /usr/local/addons/hm_kostalpiko/run.sh
#
# Runs hm_kostalpiko 10 times with a waittime of 5
# seconds between each execution:
#
# $ /usr/local/addons/hm_kostalpiko/run.sh 10 5
#
# Copyright (c) 2018 Thorsten Jagel <dev@jagel.net>
#

# directory path to hm_kostalpiko addon dir.
ADDON_DIR=/usr/local/addons/hm_kostalpiko

# set default settings (will be overwritten by config file)
export HM_PROCESSLOG_FILE="/var/log/hm_kostalpiko.log"
export CONFIG_FILE="${ADDON_DIR}/etc/hm_kostalpiko.conf"

# the interval settings can be specified on the command-line
if [ $# -gt 0 ]; then
  export HM_INTERVAL_MAX=${1}
  if [ $# -gt 1 ]; then
    export HM_INTERVAL_TIME=${2}
  else
    export HM_INTERVAL_TIME=15
  fi
else
  # otherwise do one iteration only with no
  # defined interval time
  export HM_INTERVAL_MAX=1
  export HM_INTERVAL_TIME=
fi

# execute hm_kostalpiko in non-daemon mode
export PATH="${ADDON_DIR}/bin:${PATH}"
${ADDON_DIR}/bin/hm_kostalpiko.sh >/dev/null 2>&1
