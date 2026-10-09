#!/bin/sh
# Megamiga: the RTG install disk - MiSTer.card (build.sh) plus MiSTer's monitor and Picasso96
# settings files from the Minimig submodule's MiSTer_RTG.lha. Needs lha and amitools' xdftool
# (pip install amitools).
set -e; cd "$(dirname "$0")"; X=${XDFTOOL:-xdftool}; A=${1:-Megamiga_RTG.adf}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
(cd "$T" && lha -xq "$OLDPWD/../Minimig_MiSTerMEGA65/extra/rtg_driver/MiSTer_RTG.lha")
rm -f "$A"
$X "$A" create + format "Megamiga RTG" + makedir Libs + makedir Libs/Picasso96 + makedir Devs \
   + makedir Devs/Monitors \
   + write MiSTer.card Libs/Picasso96/MiSTer.card \
   + write "$T/Devs/Monitors/MiSTer" Devs/Monitors/MiSTer \
   + write "$T/Devs/Monitors/MiSTer.info" Devs/Monitors/MiSTer.info \
   + write "$T/Devs/Picasso96Settings" Devs/Picasso96Settings \
   + write ReadMe.txt ReadMe
$X "$A" list
