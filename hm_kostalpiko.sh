#!/usr/bin/env bash
#
# A HomeMatic script which can be regularly executed (e.g. via cron on a separate
# Linux system) and remotely queries a KOSTAL Piko Inverter for current state 
# information.
#
# This script can be found at https://github.com/H2CK/hm_kostalpiko
#
# The script will set several system variables for the current status of the
# KOSTAL Piko inverter.
#
# Copyright (C) 2018-2020 Thorsten Jagel <dev@jagel.net>
#
# This script is based on similar functionality and combines the functionality of
# these projects into a single script:
#
# https://github.com/jens-maus/hm_pdetect
#

VERSION="0.2"
VERSION_DATE="Jan 19 2020"

#####################################################
# Main script starts here, don't modify from here on

# before we read in default values we have to find
# out which HM_* variables the user might have specified
# on the command-line himself
USERVARS=$(set -o posix; set | grep "HM_.*=" 2>/dev/null)

# IP addresses/hostnames of KOSTAL Piko devices
HM_PIKO_IP=${HM_PIKO_IP:-"piko"}

# IP address/hostname of CCU2
HM_CCU_IP=${HM_CCU_IP:-"homematic-raspi"}

# Port settings for ReGa communications
HM_CCU_REGAPORT=${HM_CCU_REGAPORT:-"8181"}

# Name of the CCU variable prefix used
HM_CCU_PIKO_VAR=${HM_CCU_PIKO_VAR:-"Piko"}

# number of seconds to wait between iterations
# (will run hm_kostakpiko in an endless loop)
HM_INTERVAL_TIME=${HM_INTERVAL_TIME:-}

# maximum number of iterations if running in interval mode
# (default: 0=unlimited)
HM_INTERVAL_MAX=${HM_INTERVAL_MAX:-0}

# where to save the process ID in case hm_kostalpiko runs as
# a daemon
HM_DAEMON_PIDFILE=${HM_DAEMON_PIDFILE:-"/var/run/hm_kostalpiko.pid"}

# Processing logfile output name
# (default: no output)
HM_PROCESSLOG_FILE=${HM_PROCESSLOG_FILE:-}

# maximum number of lines the logfile should contain
# (default: 500 lines)
HM_PROCESSLOG_MAXLINES=${HM_PROCESSLOG_MAXLINES:-500}

# the config file path
# (default: 'hm_kostalpiko.conf' in path where hm_kostalpiko.sh script resists)
CONFIG_FILE=${CONFIG_FILE:-"$(cd "${0%/*}"; pwd)/hm_kostalpiko.conf"}

# global return status variables
RETURN_FAILURE=1
RETURN_SUCCESS=0

###############################
# now we check all dependencies first. That means we
# check that we have the right bash version and third-party tools
# installed
#

# bash check
if [[ $(echo ${BASH_VERSION} | cut -d. -f1) -lt 4 ]]; then
  echo "ERROR: this script requires a bash shell of version 4 or higher. Please install."
  exit ${RETURN_FAILURE}
fi

# wget check
if [[ ! -x $(which wget) ]]; then
  echo "ERROR: 'wget' tool missing. Please install."
  exit ${RETURN_FAILURE}
fi

# iconv check
if [[ ! -x $(which iconv) ]]; then
  echo "ERROR: 'iconv' tool missing. Please install."
  exit ${RETURN_FAILURE}
fi

# md5sum check
if [[ ! -x $(which md5sum) ]]; then
  echo "ERROR: 'md5sum' tool missing. Please install."
  exit ${RETURN_FAILURE}
fi

###############################
# lets check if config file was specified as a cmdline arg
if [[ ${#} -gt 0        && \
      ${!#} != "child"  && \
      ${!#} != "daemon" && \
      ${!#} != "start"  && \
      ${!#} != "stop" ]]; then
  CONFIG_FILE="${!#}"
fi

if [[ ! -e ${CONFIG_FILE} ]]; then
  echo "WARNING: config file '${CONFIG_FILE}' doesn't exist. Using default values."
  CONFIG_FILE=
fi

# lets source the config file a first time
if [[ -n ${CONFIG_FILE} ]]; then
  source "${CONFIG_FILE}"
  if [[ $? -ne 0 ]]; then
    echo "ERROR: couldn't source config file '${CONFIG_FILE}'. Please check config file syntax."
    exit ${RETURN_FAILURE}
  fi

  # lets eval the user overridden variables
  # so that they take priority
  eval ${USERVARS}
fi

###############################
# run hm_kostalpiko as a real daemon by using setsid
# to fork and deattach it from a terminal.
PROCESS_MODE=normal
if [[ ${#} -gt 0 ]]; then
  FILE=${0##*/}
  DIR=$(cd "${0%/*}"; pwd)

  # lets check the supplied command
  case "${1}" in

    start) # 1. lets start the child
      shift
      exec "${DIR}/${FILE}" child "${CONFIG_FILE}" &
      exit 0
    ;;

    child) # 2. We are the child. We need to fork the daemon now
      shift
      umask 0
      echo
      echo "Starting hm_kostalpiko in daemon mode."
      exec setsid ${DIR}/${FILE} daemon "${CONFIG_FILE}" </dev/null >/dev/null 2>/dev/null &
      exit 0
    ;;

    daemon) # 3. We are the daemon. Lets continue with the real stuff
      shift
      # save the PID number in the specified PIDFILE so that we 
      # can kill it later on using this file
      if [[ -n ${HM_DAEMON_PIDFILE} ]]; then
        echo $$ >${HM_DAEMON_PIDFILE}
      fi

      # if we end up here we are in daemon mode and
      # can continue normally but make sure we don't allow any
      # input
      exec 0</dev/null

      # make sure PROCESS_MODE is set to daemon
      PROCESS_MODE=daemon
    ;;

    stop) # 4. stop the daemon if requested
      if [[ -f ${HM_DAEMON_PIDFILE} ]]; then
        echo "Stopping hm_kostalpiko (pid: $(cat ${HM_DAEMON_PIDFILE}))"
        kill $(cat ${HM_DAEMON_PIDFILE}) >/dev/null 2>&1
        rm -f ${HM_DAEMON_PIDFILE} >/dev/null 2>&1
      fi
      exit 0
    ;;

  esac
fi
 
###############################
# function returning the current state of a homematic variable
# and returning success/failure if the variable was found/not
function getVariableState()
{
  local name="$1"

  local result=$(wget -q -O - "http://${HM_CCU_IP}:${HM_CCU_REGAPORT}/rega.exe?state=dom.GetObject(ID_SYSTEM_VARIABLES).Get('${name}').Value()")
  if [[ ${result} =~ \<state\>(.*)\</state\> ]]; then
    result="${BASH_REMATCH[1]}"
    if [[ ${result} != "null" ]]; then
      echo ${result}
      return ${RETURN_SUCCESS}
    fi
  fi

  echo ${result}
  return ${RETURN_FAILURE}
}

# function setting the state of a homematic variable in case it
# it different to the current state and the variable exists
function setVariableState()
{
  local name="$1"
  local newstate="$2"

  # before we going to set the variable state we
  # query the current state and if the variable exists or not
  curstate=$(getVariableState "${name}")
  if [[ ${curstate} == "null" ]]; then
    return ${RETURN_FAILURE}
  fi

  # only continue if the current state is different to the new state
  if [[ ${curstate} == ${newstate//\'} ]]; then
    return ${RETURN_SUCCESS}
  fi

  # the variable should be set to a new state, so lets do it
  echo -n "  Setting CCU variable '${name}': '${newstate//\'}'... "
  local result=$(wget -q -O - "http://${HM_CCU_IP}:${HM_CCU_REGAPORT}/rega.exe?state=dom.GetObject(ID_SYSTEM_VARIABLES).Get('${name}').State(${newstate})")
  if [[ ${result} =~ \<state\>(.*)\</state\> ]]; then
    result="${BASH_REMATCH[1]}"
  else
    result=""
  fi

  # if setting the variable succeeded the result will be always
  # 'true'
  if [[ ${result} == "true" ]]; then
    echo "ok."
    return ${RETURN_SUCCESS}
  fi

  echo "ERROR."
  return ${RETURN_FAILURE}
}

# function to check if a certain boolean system variable exists
# at a CCU and if not creates it accordingly
function createVariable()
{
  local vaname=$1
  local vatype=$2
  local comment=$3
  local valist=$4

  # first we find out if the variable already exists and if
  # the value name/list it contains matches the value name/list
  # we are expecting
  local postbody=""
  if [[ ${vatype} == "enum" ]]; then
    local result=$(wget -q -O - "http://${HM_CCU_IP}:${HM_CCU_REGAPORT}/rega.exe?valueList=dom.GetObject(ID_SYSTEM_VARIABLES).Get('${vaname}').ValueList()")
    if [[ ${result} =~ \<valueList\>(.*)\</valueList\> ]]; then
      result="${BASH_REMATCH[1]}"
    fi

    # make sure result is not empty and not null
    if [[ -n ${result} && ${result} != "null" ]]; then
      if [[ ${result} != ${valist} ]]; then
        echo -n "  Modifying CCU variable '${vaname}' (${vatype})... "
        postbody="string v='${vaname}';dom.GetObject(ID_SYSTEM_VARIABLES).Get(v).ValueList('${valist}')"
      fi
    else
      echo -n "  Creating CCU variable '${vaname}' (${vatype})... "
      postbody="string v='${vaname}';boolean f=true;string i;foreach(i,dom.GetObject(ID_SYSTEM_VARIABLES).EnumUsedIDs()){if(v==dom.GetObject(i).Name()){f=false;}};if(f){object s=dom.GetObject(ID_SYSTEM_VARIABLES);object n=dom.CreateObject(OT_VARDP);n.Name(v);s.Add(n.ID());n.ValueType(ivtInteger);n.ValueSubType(istEnum);n.DPInfo('${comment}');n.ValueList('${valist}');n.State(0);dom.RTUpdate(false);}"
    fi
  elif [[ ${vatype} == "string" ]]; then
    getVariableState "${vaname}" >/dev/null
    if [[ $? -eq 1 ]]; then
      echo -n "  Creating CCU variable '${vaname}' (${vatype})... "
      postbody="string v='${vaname}';boolean f=true;string i;foreach(i,dom.GetObject(ID_SYSTEM_VARIABLES).EnumUsedIDs()){if(v==dom.GetObject(i).Name()){f=false;}};if(f){object s=dom.GetObject(ID_SYSTEM_VARIABLES);object n=dom.CreateObject(OT_VARDP);n.Name(v);s.Add(n.ID());n.ValueType(ivtString);n.ValueSubType(istChar8859);n.DPInfo('${comment}');n.State('');dom.RTUpdate(false);}"
    fi
  elif [[ ${vatype} == "integer" ]]; then
    getVariableState "${vaname}" >/dev/null
    if [[ $? -eq 1 ]]; then
      echo -n "  Creating CCU variable '${vaname}' (${vatype})... "
      postbody="string v='${vaname}';boolean f=true;string i;foreach(i,dom.GetObject(ID_SYSTEM_VARIABLES).EnumUsedIDs()){if(v==dom.GetObject(i).Name()){f=false;}};if(f){object s=dom.GetObject(ID_SYSTEM_VARIABLES);object n=dom.CreateObject(OT_VARDP);n.Name(v);s.Add(n.ID());n.ValueType(ivtInteger);n.ValueSubType(istGeneric);n.ValueMin(0);n.ValueMax(65000);n.DPInfo('${comment}');n.State('');dom.RTUpdate(false);}"
    fi
  fi

  # if postbody is empty there is nothing to do
  # and the variable exists with correct value name/list
  if [[ -z ${postbody} ]]; then
    return ${RETURN_SUCCESS}
  fi

  # use wget to post the tcl script to tclrega.exe
  local result=$(wget -q -O - --post-data "${postbody}" "http://${HM_CCU_IP}:${HM_CCU_REGAPORT}/tclrega.exe")
  if [[ ${result} =~ \<v\>${vaname}\</v\> ]]; then
    echo "ok."
    return ${RETURN_SUCCESS}
  else
    echo "ERROR: could not create system variable '${vaname}'."
    return ${RETURN_FAILURE}
  fi
}

# function that logs into a KOSTAL Piko device and stores all devices
# in an associative array which have to bre created before calling this function
function retrieveKostalPikoInfo()
{
  local ip=$1
  local user=$2
  local secret=$3
  local uri=${ip}

  # check if "ip" starts with a "http(s)://" URL scheme
  # identifier or if we have to add it ourself
  if [[ ! ${ip} =~ ^http(s)?:\/\/ ]]; then
    uri="http://${ip}"
  fi
  
  # retrieve the current state information from the KOSTAL Piko inverter using a
  # specific call.
  data=$(wget -q -O - --max-redirect=0 --no-check-certificate --user="${user}" --password="${secret}" "${uri}/api/dxs.json?dxsEntries=33556736&dxsEntries=67109120&dxsEntries=251658753&dxsEntries=16780032&dxsEntries=33556229&dxsEntries=33556228&dxsEntries=33556227&dxsEntries=33556226&dxsEntries=33556238&dxsEntries=33556230&dxsEntries=83886848&dxsEntries=83888128")
  if [[ $? -ne 0 || -z ${data} ]]; then
    return ${RETURN_FAILURE}
  fi

  echo "Raw data: ${data}"
  #return ${RETURN_SUCCESS}
  
  # prepare the regular expressions
  local re_dc_power=".*33556736,\"value\"\:([0-9]+)"
  local re_ac_power=".*67109120,\"value\"\:([0-9]+)"
  local re_overall_output=".*251658753,\"value\"\:([0-9]+)"
  local re_op_state=".*16780032,\"value\"\:([0-9]+)"
  local re_bat_charge=".*33556229,\"value\"\:([0-9]+)"
  local re_bat_cycles=".*33556228,\"value\"\:([0-9]+)"
  local re_bat_temprature=".*33556227,\"value\"\:([0-9]+)"
  local re_bat_voltage=".*33556226,\"value\"\:([0-9]+)"
  local re_bat_current=".*33556238,\"value\"\:([0-9]+)"
  local re_bat_state=".*33556230,\"value\"\:([0-9]+)"
  local re_consuption_external=".*83886848,\"value\"\:([0-9]+)"
  local re_consumption_internal=".*83888128,\"value\"\:([0-9]+)"
  
  local dc_power=0
  local ac_power=0
  local overall_output=0
  local op_state=0
  local bat_charge=0
  local bat_cycles=0
  local bat_temprature=0
  local bat_voltage=0
  local bat_current=0
  local bat_state=0
  local consumption_external=0
  local consumption_internal=0
  
  if [[ $data =~ $re_dc_power ]]; then
      dc_power="${BASH_REMATCH[1]}"
  fi
  if [[ $data =~ $re_ac_power ]]; then
    ac_power="${BASH_REMATCH[1]}"
  fi
  if [[ $data =~ $re_overall_output ]]; then
    overall_output="${BASH_REMATCH[1]}"
  fi
  if [[ $data =~ $re_op_state ]]; then
    op_state="${BASH_REMATCH[1]}"
  fi
  if [[ $data =~ $re_bat_charge ]]; then
    bat_charge="${BASH_REMATCH[1]}"
  fi
  if [[ $data =~ $re_bat_cycles ]]; then
    bat_cycles="${BASH_REMATCH[1]}"
  fi
  if [[ $data =~ $re_bat_temprature ]]; then
    bat_temprature="${BASH_REMATCH[1]}"
  fi
  if [[ $data =~ $re_bat_voltage ]]; then
    bat_voltage="${BASH_REMATCH[1]}"
  fi
  if [[ $data =~ $re_bat_current ]]; then
    bat_current="${BASH_REMATCH[1]}"
  fi
  if [[ $data =~ $re_bat_state ]]; then
    bat_state="${BASH_REMATCH[1]}"
  fi
  if [[ $data =~ $re_consuption_external ]]; then
    consumption_external="${BASH_REMATCH[1]}"
  fi
  if [[ $data =~ $re_consumption_internal ]]; then
    consumption_internal="${BASH_REMATCH[1]}"
  fi
  
  echo " DC-Power: ${dc_power} W"
  echo " AC-Power: ${ac_power} W"
  echo " Overall Output: ${overall_output} kW"
  echo " Operational State: ${op_state}"
  echo " Battery Charged: ${bat_charge} %"
  echo " Battery Cycles: ${bat_cycles}"
  echo " Battery Temprature: ${bat_temprature} celsius"
  echo " Battery Voltage: ${bat_voltage} V"
  echo " Battery Current: ${bat_current} A"
  echo " Battery State: ${bat_state}"
  echo " Consumption external: ${consumption_external} W"
  echo " Consumption internal: ${consumption_internal} W"
  
  # set status in homematic CCU
  createVariable "${HM_CCU_PIKO_VAR}-${ip}.DCPower" integer "DC-Power @ ${ip}"
  setVariableState "${HM_CCU_PIKO_VAR}-${ip}.DCPower" ${dc_power}
  createVariable "${HM_CCU_PIKO_VAR}-${ip}.ACPower" integer "AC-Power @ ${ip}"
  setVariableState "${HM_CCU_PIKO_VAR}-${ip}.ACPower" ${ac_power}
  createVariable "${HM_CCU_PIKO_VAR}-${ip}.TotalOutput" integer "Overall Output @ ${ip}"
  setVariableState "${HM_CCU_PIKO_VAR}-${ip}.TotalOutput" ${overall_output}
  createVariable "${HM_CCU_PIKO_VAR}-${ip}.OpState" integer "Operational State @ ${ip}"
  setVariableState "${HM_CCU_PIKO_VAR}-${ip}.OpState" ${op_state}
  createVariable "${HM_CCU_PIKO_VAR}-${ip}.BatCharge" integer "Battery charged @ ${ip}"
  setVariableState "${HM_CCU_PIKO_VAR}-${ip}.BatCharge" ${bat_charge}
  createVariable "${HM_CCU_PIKO_VAR}-${ip}.BatCycles" integer "Battery Cycles @ ${ip}"
  setVariableState "${HM_CCU_PIKO_VAR}-${ip}.BatCycles" ${bat_cycles}
  createVariable "${HM_CCU_PIKO_VAR}-${ip}.BatTemp" integer "Battery Temprature @ ${ip}"
  setVariableState "${HM_CCU_PIKO_VAR}-${ip}.BatTemp" ${bat_temprature}
  createVariable "${HM_CCU_PIKO_VAR}-${ip}.BatVoltage" integer "Battery Voltage @ ${ip}"
  setVariableState "${HM_CCU_PIKO_VAR}-${ip}.BatVoltage" ${bat_voltage}
  createVariable "${HM_CCU_PIKO_VAR}-${ip}.BatCurrent" integer "Battery Current @ ${ip}"
  setVariableState "${HM_CCU_PIKO_VAR}-${ip}.BatCurrent" ${bat_current}
  createVariable "${HM_CCU_PIKO_VAR}-${ip}.BatState" integer "Battery State @ ${ip}"
  setVariableState "${HM_CCU_PIKO_VAR}-${ip}.BatState" ${bat_state}
  createVariable "${HM_CCU_PIKO_VAR}-${ip}.ConsumptionExt" integer "Consumption External @ ${ip}"
  setVariableState "${HM_CCU_PIKO_VAR}-${ip}.ConsumptionExt" ${consumption_external}
  createVariable "${HM_CCU_PIKO_VAR}-${ip}.ConsumptionInt" integer "Consumption Internal @ ${ip}"
  setVariableState "${HM_CCU_PIKO_VAR}-${ip}.ConsumptionInt" ${consumption_internal}
  
  return ${RETURN_SUCCESS}
}

function run_kostalpiko()
{
  # output time/date of execution
  echo "== $(date) ==================================="

  # lets retrieve all mac<>ip addresses of currently
  # active devices in our network
  echo -n "Querying KOSTAL Piko devices:"
  i=0
  for ip in ${HM_PIKO_IP[@]}; do
    echo -n " ${ip}"
    retrieveKostalPikoInfo ${ip} "${HM_PIKO_USER}" "${HM_PIKO_SECRET}"
    if [[ $? -eq 0 ]]; then
      ((i = i + 1))
    fi
  done
  
  # check that we were able to connect to at least one device
  if [[ ${i} -eq 0 ]]; then
    echo "ERROR: couldn't connect to any specified KOSTAL Piko device."
    return ${RETURN_FAILURE}
  fi
  
  echo "== $(date) ==================================="
  echo
  
  return ${RETURN_SUCCESS}
}

################################################
# main processing starts here
#
echo "hm_kostalpiko ${VERSION} - a HomeMatic script to query current state information from KOSTAL Piko Inverter"
echo "(${VERSION_DATE}) Copyright (C) 2018-2020 Thorsten Jagel <dev@jagel.net>"
echo

# lets enter an endless loop to implement a
# daemon-like behaviour
result=-1
iteration=0
while true; do

  # lets source the config file again
  if [[ -n ${CONFIG_FILE} ]]; then
    source "${CONFIG_FILE}"
    if [[ $? -ne 0 ]]; then
      echo "ERROR: couldn't source config file '${CONFIG_FILE}'. Please check config file syntax."
      result=${RETURN_FAILURE}
    fi

    # lets eval the user overridden variables
    # so that they take priority
    eval ${USERVARS}
  fi

  # lets wait until the next execution round in case
  # the user wants to run it as a daemon
  if [[ ${result} -ge 0 ]]; then
    ((iteration = iteration + 1))
    if [[ -n ${HM_INTERVAL_TIME}    && \
          ${HM_INTERVAL_TIME} -gt 0 && \
          ( -z ${HM_INTERVAL_MAX} || ${HM_INTERVAL_MAX} -eq 0 || ${iteration} -lt ${HM_INTERVAL_MAX} ) ]]; then
      sleep ${HM_INTERVAL_TIME}
      if [[ $? -eq 1 ]]; then
        result=${RETURN_FAILURE}
        break
      fi
    else 
      break
    fi
  fi

  # perform one kostalpiko run and in case we are running in daemon
  # mode and having the processlogfile enabled output to the logfile instead.
  if [[ -n ${HM_PROCESSLOG_FILE} ]]; then
    output=$(run_kostalpiko)
    result=$?
    echo "${output}" | cat - ${HM_PROCESSLOG_FILE} | head -n ${HM_PROCESSLOG_MAXLINES} >/tmp/hm_kostalpiko-$$.tmp && mv /tmp/hm_kostalpiko-$$.tmp ${HM_PROCESSLOG_FILE}
  else
    # run kostalpiko with normal stdout processing
    run_kostalpiko
    result=$?
  fi

done

exit ${result}
