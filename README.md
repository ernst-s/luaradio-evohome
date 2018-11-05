# luaradio-evohome

## Description

Simple Honeywell Evohome receiver based on LuaRadio http://luaradio.io
Uses an RTL-SDR as input and outputs raw frames to localhost on UDP port 8888 and decoded frames on 8889.
These UDP packets can then be further processed to decode the data e.g. honeymon https://github.com/jrosser/honeymon/wiki

## Usage:

luaradio evohome.lua or luaradio -v evohome.lua for debugging output

