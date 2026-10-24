# Top-level entry points. Run from the repository root.
VERILATOR ?= verilator
PYTHON    ?= python3

# Every module that must lint clean on its own (default parameters).
LINT_TOPS := tb_axi_smoke tb_pkg_funcs ca_delay ca_sync ca_reset_sync ca_gray_xfer ca_async_fifo ca_ram_sdp_asym ca_cell_packer ca_adder_tree ca_div_pipe ca_valid_delay ca_window ca_engine tb_engine lint_engine_ghm ca_line_buffer lint_reader lint_writer lint_regs ca_controller

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
