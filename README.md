## KOSTAL Piko status information for HomeMatic - hm_kostalpiko

[![Release](https://img.shields.io/github/release/H2CK/hm_kostalpiko.svg)](https://github.com/H2CK/hm_kostalpiko/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/H2CK/hm_kostalpiko/latest/total.svg)](https://github.com/H2CK/hm_kostalpiko/releases/latest)
[![Issues](https://img.shields.io/github/issues/H2CK/hm_kostalpiko.svg)](https://github.com/H2CK/hm_kostalpiko/issues)
[![License](http://img.shields.io/:license-lgpl3-blue.svg?style=flat)](http://www.gnu.org/licenses/lgpl-3.0.html)
[![Donate](https://img.shields.io/badge/donate-PayPal-green.svg)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=QRSDVQA2UMJQC&source=url)

This CCU-Addon reads the current status informationen from a KOSTAL Piko inverter an provides these informations as system variables within the HomeMatic CCU environment.

## Features
Following values are requested from a KOSTAL Piko inverter:
* DC-Power (W)
* AC-Power (W)
* Total Output (kW)
* Operational State (0 = off, 1 = idle, 2 = start-up, 3 = feed MPP, 4 = limited, 5 = feed, 6 = ??, 7 = ??, 8 = ??
* Battery - Charge State (%)
* Battery - Load Cycles (Amount)
* Battery - Temperature (celsius°)
* Battery - Voltage (V)
* Battery - Current (A)
* Battery - Charging/Discharging (1=Charging; 0=Discharging)
* Consumed Energy from Energy Provider (W)
* Consumed Energy self generated (W)

## Supported CCU models
* [HomeMatic CCU3](https://www.eq-3.de/produkte/homematic/zentralen-und-gateways/smart-home-zentrale-ccu3.html) / [RaspberryMatic](http://raspberrymatic.de/)
* [HomeMatic CCU2](https://www.eq-3.de/produkt-detail-zentralen-und-gateways/items/homematic-zentrale-ccu-2.html)
* HomeMatic CCU1

## Installation as CCU Addon
1. Download of recent Addon-Release from [Github](https://github.com/H2CK/hm_kostalpiko/releases)
2. Installation of Addon archive (```hm_kostalpiko-X.X.tar.gz```) via WebUI interface of CCU device
3. Configuration of Addon using the WebUI accessible config pages

## Manual Installation as stand-alone script (e.g. on RaspberryPi)
1. Create a new directory for hm_kostalpiko:

        mkdir /opt/hm_kostalpiko

2. Change to new directory: 

        cd /opt/hm_kostalpiko

3. Download latest hm_kostalpiko.sh:

        wget https://github.com/H2CK/hm_kostalpiko/raw/master/hm_kostalpiko.sh

4. Download of sample config:

        wget https://github.com/H2CK/hm_kostalpiko/raw/master/hm_kostalpiko.conf.sample

5. Rename sample config to active one:

        mv hm_kostalpiko.conf.sample hm_kostalpiko.conf

6. Modify configuration according to comments in config file:

        vim hm_kostalpiko.conf

7. Execute hm_kostalpiko manually:

        /opt/hm_kostalpiko/hm_kostalpiko.sh

8. If you want to automatically start hm_kostalpiko on system startup a startup script

## Using 'system.Exec()'
Instead of automatically calling hm_kostalpiko on a predefined interval one can also trigger its execution using the `system.Exec()` command within HomeMatic scripts on the CCU following the following syntax:

        system.Exec("/usr/local/addons/hm_kostalpiko/run.sh <iterations> <waittime> &");
 
Please note the &lt;iterations&gt; and &lt;waittime&gt; which allows to additionally specify how many times hm_kostalpiko should be executed with a certain amount of wait time in between. One example of such an execution can be:

        system.Exec("/usr/local/addons/hm_kostalpiko/run.sh 5 2 &");

This will execute hm_kostalpiko for a total amount of 5 times with a waittime of 2 seconds between each execution.

## Support
In case of problems/bugs or if you have any feature requests please feel free to open a [new ticket](https://github.com/H2CK/hm_kostalpiko/issues) at the Github project pages.

## License
The use and development of this addon is based on version 3 of the LGPL open source license.

## Authors
Copyright (c) 2018 Thorsten Jagel &lt;dev@jagel.net&gt;

## Notice
This Addon uses KnowHow that was developed throughout the following projects:
* https://github.com/jens-maus/hm_pdetect
