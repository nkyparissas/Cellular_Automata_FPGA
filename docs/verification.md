# Verification record

## Golden-model experiments (Task 5)

Command: `PYTHONPATH=model python3 -m ca_model.run --config configs/<name>.json --gens 1000 --png-every 250`; outputs in `build/exp/<name>/` (not committed). Timings were measured with all six runs in parallel.

| Experiment | Seed | Setting | ms/gen | User verdict (2026-10-24) |
|---|---|---|---|---|
| hodgepodge29 | hodgepodge29_seed.bmp, white = 251 | N=29 Moore, G=105, K=5, toroidal | 1436 | looks right |
| hodgepodge19 | see below | N=19 Moore, G=60, K=3, toroidal | 426 (single run) | first version rejected; re-run pending review |
| ghm_circle_toroidal | ghm_spirals.bmp (indices) | N=29 circle, T=5, STATES=15, E=1 | 957 | looks right |
| ghm_vn_toroidal | ghm_spirals.bmp (indices) | N=29 von Neumann, T=5, STATES=15, E=1 | 956 | looks right |
| ghm_moore_cylindrical | ghm_spirals.bmp (indices) | N=29 Moore, legacy cylindrical | 930 | looks right |
| ap_toroidal | ap_random.bmp, white = 1 | N=21 legacy AP mask (row, column), interval 20..23 / 59..100 | 1573 | looks right |

Hodgepodge 19x19: the first run started from `seed.bmp` (G=48) and did not self-organise, which the legacy `READ ME.txt` also records ("We are yet to find an initial seed that leads to auto-organization. grid_custom works for G = 47 ... 60, G = 60 converges"). The legacy 19x19 result was produced from `grid_custom.txt`, so the configuration now starts from `data/seeds/hodgepodge19_grid_custom.png` (a lossless copy of that text grid) with G=60, K=3; it forms spirals like the legacy result and was run to 2000 generations.

## RTL experiments at full size (Task 16)

Command: `python3 tools/run_rtl_experiment.py --config configs/<name>.json --gens <n> --dump-every <k>`; the core testbench (`sim/tb/tb_core.sv`) runs the 1920x1080 grid with a behavioural AXI memory and compares every dumped generation with the golden model. Outputs in `build/rtl_exp/<name>/`.

| Experiment | Build | s/gen (Verilator, 1 thread, machine shared) | Generations 1-3 |
|---|---|---|---|
| hodgepodge29 | 29 s | 20.1 | MATCH |
| hodgepodge19 | 19 s | 12.5 | MATCH |
| ghm_circle_toroidal | 57 s | 20.1 | MATCH |
| ghm_vn_toroidal | 33 s | 11.5 | MATCH |
| ghm_moore_cylindrical | 36 s | 11.1 | MATCH |
| ap_toroidal | 18 s | 7.5 | MATCH |

1000-generation RTL runs (snapshots every 250 generations, compared with the model): in progress; results are appended here when they finish.
