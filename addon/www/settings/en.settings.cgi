#!/usr/bin/env tclsh
source [file join [file dirname [info script]] inc/settings.tcl]

parseQuery

if { $args(command) == "defaults" } {
  set args(HM_PIKO_IP) ""
  set args(HM_PIKO_USER) ""
  set args(HM_PIKO_SECRET) ""
  set args(HM_CCU_PIKO_VAR) ""
  set args(HM_INTERVAL_TIME) ""
  
  # force save of data
  set args(command) "save"
} 

if { $args(command) == "save" } {
	saveConfigFile
} 

set HM_PIKO_IP ""
set HM_PIKO_USER ""
set HM_PIKO_SECRET ""
set HM_CCU_PIKO_VAR ""
set HM_INTERVAL_TIME ""

loadConfigFile
set content [loadFile en.settings.html]
source [file join [file dirname [info script]] inc/settings1.tcl]
