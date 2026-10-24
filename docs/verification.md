# Verification record

## Golden-model experiments (Task 5)

Command: `PYTHONPATH=model python3 -m ca_model.run --config configs/<name>.json --gens 1000 --png-every 250`; outputs in `build/exp/<name>/` (not committed).

| Experiment | Seed | Setting | ms/gen | User verdict |
|---|---|---|---|---|
| hodgepodge29 | hodgepodge29_seed.bmp, white = 251 | N=29 Moore, G=105, K=5, toroidal | pending | pending |
| hodgepodge19 | hodgepodge19_seed.bmp, white = 251 | N=19 Moore, G=48, K=3, toroidal | pending | pending |
| ghm_circle_toroidal | ghm_spirals.bmp (indices) | N=29 circle, T=5, STATES=15, E=1 | pending | pending |
| ghm_vn_toroidal | ghm_spirals.bmp (indices) | N=29 von Neumann, T=5, STATES=15, E=1 | pending | pending |
| ghm_moore_cylindrical | ghm_spirals.bmp (indices) | N=29 Moore, legacy cylindrical | pending | pending |
| ap_toroidal | ap_random.bmp, white = 1 | N=21 legacy AP mask (row, column), interval 20..23 / 59..100 | pending | pending |
