# Vendored third-party code

Copied verbatim (only `include/`, `src/`, `LICENSE` and `Bender.yml`) so that the repository builds without network access or a package manager.

| Directory | Upstream | Tag | Commit | Licence |
|---|---|---|---|---|
| `axi/` | https://github.com/pulp-platform/axi | v0.39.11 | 42ca270ebd8bbbc1c64ddc0ca712e722eb9e3f06 | Solderpad Hardware License 0.51 |
| `common_cells/` | https://github.com/pulp-platform/common_cells | v1.39.0 | 9ca8a7655f741e7dd5736669a20a301325194c28 | Solderpad Hardware License 0.51 |

`common_cells` v1.39.0 is the version required by `axi` v0.39.11 (`axi/Bender.yml`). Modules are resolved through `-y` search paths in `rtl/files.f`; only the packages are listed explicitly. Do not edit these files; update by re-copying a newer tag and adjusting this table.

## Data taken from other projects

| Path | Upstream | Version | Licence | Notes |
|---|---|---|---|---|
| `data/patterns/` | https://github.com/lenia-org/Lenia-Tutorial (`Tutorial_From_Conway_to_Lenia.ipynb`, cell 5) | commit 2642cf995b90f4f37788aba440450098e36aa798 | MIT, Copyright (c) 2021 Open Science Lenia (`data/patterns/LICENSE`) | Orbium, Hydrogeminium and Smooth wanderer, extracted on 2026-10-31 by parsing the notebook as data (never executed); `m`, `s`, `b` renamed to `mu`, `sigma`, `beta`. |
