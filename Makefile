# Top-level entry points. Run from the repository root.
VERILATOR ?= verilator
PYTHON    ?= python3

# Every module that must lint clean on its own (default parameters).
LINT_TOPS := tb_axi_smoke tb_pkg_funcs ca_delay ca_sync ca_reset_sync ca_gray_xfer ca_async_fifo

LINT_FLAGS := --lint-only -Wall --timing rtl/lint.vlt -f rtl/files.f -y sim/tb -y sim/models

.PHONY: lint test clean
lint:
	@set -e; for t in $(LINT_TOPS); do \
	  echo "lint $$t"; \
	  f=$$(find rtl sim -name "$$t.sv" | head -1); \
	  $(VERILATOR) $(LINT_FLAGS) --top-module $$t $$f; \
	done

test:
	$(PYTHON) -m pytest -q

clean:
	rm -rf build sim_build
