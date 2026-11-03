#!/usr/bin/env bash
# Rotation-continuation bench of the ADF read service (AExp issue #40, Apidya):
# tb_adf_rotation.vhd (taken over from upstream AExp 748f162, WIP-V2-B3) runs
# the real CORE/vhdl/adf_track_engine.vhd against a cycle-level model of
# Paula's receiver. Upstream runs these cells inside run_fdd_regression.sh with
# nvc; Megamiga keeps only this bench, so this runner runs its five cells on
# their own, with nvc if it is installed and ghdl otherwise.
#
# Usage: CORE/sim/floppy/run_adf_rotation.sh [workdir]
# Exit status: the number of failed cells (0 = all pass).
#
# Red control (2026-11-03): Megamiga's first fix (0cf240b) fails
# rotation_throttle (0 3 ...), the engine without any fix fails rotation_step
# (0 2 ...) and rotation_throttle.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
W="${1:-$(mktemp -d "${TMPDIR:-/tmp}/megamiga-rot.XXXXXX")}"
mkdir -p "$W" || exit 2
W="$(cd "$W" && pwd)"
echo "work dir: $W"

CELLS=(
  "rotation_step|-gG_DSKLEN=33310 -gG_SLOT_CYC=8 -gG_NDMA=12"
  "rotation_tiny|-gG_DSKLEN=32769 -gG_WORDSYNC=false -gG_NDMA=12"
  "rotation_sync3|-gG_DSKLEN=33312 -gG_EXPECT=2 -gG_SLOT_CYC=8 -gG_NDMA=12"
  "rotation_abort|-gG_DSKLEN=32769 -gG_ABORT_AT=700 -gG_NDMA=9"
  "rotation_throttle|-gG_DSKLEN=33854 -gG_EXPECT=3 -gG_NDMA=12"
)
SRCS="$ROOT/CORE/vhdl/adf_track_engine.vhd $HERE/tb_adf_rotation.vhd"

if command -v nvc >/dev/null; then
  NVC="nvc --std=2008 --work=work:$W/work -L $W"
  # shellcheck disable=SC2086
  $NVC -a $SRCS > "$W/analyse.log" 2>&1 || { echo "analysis failed, see $W/analyse.log"; exit 99; }
  run_cell() { ( cd "$W" && $NVC -e tb_adf_rotation $1 && $NVC -r tb_adf_rotation ); }
else
  O="--std=08 -frelaxed --workdir=$W"
  # shellcheck disable=SC2086
  { ghdl -a $O $SRCS && ghdl -e $O tb_adf_rotation; } > "$W/analyse.log" 2>&1 \
    || { echo "analysis failed, see $W/analyse.log"; exit 99; }
  run_cell() { ( cd "$W" && ghdl -r $O tb_adf_rotation $1 ); }
fi

fails=0
for c in "${CELLS[@]}"; do
  tag="${c%%|*}"; gens="${c#*|}"; log="$W/$tag.log"
  run_cell "$gens" > "$log" 2>&1
  if grep -q "TB_ADF_ROTATION: ALL PASS" "$log" && ! grep -qiE "failure|error" "$log"; then
    echo "PASS  $tag"
  else
    echo "FAIL  $tag   ($(grep -m1 -iE 'failure|error' "$log" | cut -c1-120))"
    fails=$((fails + 1))
  fi
done
exit "$fails"
