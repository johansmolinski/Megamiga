#!/bin/sh
# Megamiga: the network disk - megamiga-eth.device and ethtest (build.sh) plus the Roadshow
# configuration templates. Needs amitools' xdftool (pip install amitools).
set -e; cd "$(dirname "$0")"; X=${XDFTOOL:-xdftool}; A=${1:-Megamiga_Net.adf}; R=${ROADSHOW:-roadshow}
rm -f "$A"
$X "$A" create + format "Megamiga Net" + makedir Devs + makedir Devs/Networks + makedir C \
   + makedir Roadshow \
   + write megamiga-eth.device Devs/Networks/megamiga-eth.device \
   + write ethtest C/ethtest \
   + write "$R/MegamigaEth" Roadshow/MegamigaEth \
   + write "$R/routes" Roadshow/routes \
   + write "$R/name_resolution" Roadshow/name_resolution \
   + write ReadMe.txt ReadMe
$X "$A" list
