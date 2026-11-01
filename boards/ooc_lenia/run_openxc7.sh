#!/usr/bin/env bash
# Open-source synthesis, placement and routing of the Lenia datapath on the
# Nexys 4 DDR part (xc7a100tcsg324-1) with Yosys (OSS CAD Suite, yosys-slang)
# and openXC7 nextpnr-xilinx, reporting resources and routed timing.
#
# Usage (from anywhere, with the OSS CAD Suite environment active):
#   boards/ooc_lenia/run_openxc7.sh [N [CELL_W [FREQ_MHZ]]]      # default 27 16 200
# nextpnr-xilinx is taken from $OPENXC7/bin (default ~/openxc7, the unpacked
# openXC7 release). Do not source the release's environment script for this:
# it points VERILATOR_ROOT at a Verilator the release does not contain.
# Outputs in build/openxc7_lenia_n<N>_c<CELL_W>/: yosys.log, nextpnr.log,
# utilization.txt, report.json (with detailed timing), placement.json,
# routed.json, and the pictures floorplan.png, critical_path.png and
# congestion.png (plot_pnr.py). With SKIP_SYNTH=1 an existing lenia.json is
# placed and routed again; PNR_ARGS replaces the extra nextpnr-xilinx options
# (default "--placer static": the default heap placer cannot legalise one carry
# chain of the 27x27 build; other examples: "--placer sa" or
# "--placer static --seed 2").
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
n=${1:-27}
cw=${2:-16}
freq=${3:-200}
out=$root/build/openxc7_lenia_n${n}_c${cw}
nextpnr=${OPENXC7:-$HOME/openxc7}/bin/nextpnr-xilinx
mkdir -p "$out"

(cd "$root" && python3 tools/gen_filelist.py --top lenia_pnr_top --extra-dir boards/ooc_lenia --out "$out/files.f" >/dev/null)
files=$(sed "s|^|$root/|" "$out/files.f" | tr '\n' ' ')

echo "[progress] 1/3 synthesis (yosys synth_xilinx)"
[ "${SKIP_SYNTH:-0}" = 1 ] || yosys -m slang -q -l "$out/yosys.log" -p "
  read_slang -I $root/third_party/axi/include -I $root/third_party/common_cells/include \
    -G N=$n -G CELL_W=$cw --top lenia_pnr_top $files;
  synth_xilinx -flatten -abc9 -arch xc7 -top lenia_pnr_top;
  tee -o $out/utilization.txt stat;
  write_json $out/lenia.json"

echo "[progress] 2/3 place and route (nextpnr-xilinx, $freq MHz)"
"$nextpnr" --device xc7a100tcsg324-1 --json "$out/lenia.json" -o xdc="$here/lenia_pnr_nexys4ddr.xdc" \
  -o placement="$out/placement.json" --write "$out/routed.json" \
  --freq "$freq" --timing-allow-fail --report "$out/report.json" --detailed-timing-report \
  ${PNR_ARGS:---placer static} -l "$out/nextpnr.log"

echo "[progress] 3/3 pictures"
python3 "$here/plot_pnr.py" "$out"
grep -E "Max frequency for clock|Max delay" "$out/nextpnr.log" | tail -4
echo "[done] reports in $out"
