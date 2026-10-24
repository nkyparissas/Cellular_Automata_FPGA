"""Command-line tools: argument checks that need no simulation."""
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]


def test_rtl_runs_limited_to_200_generations(monkeypatch, capsys):
    import rtlsim
    import run_rtl_experiment

    def no_build(*a, **k):
        raise AssertionError("the simulation was started")

    monkeypatch.setattr(rtlsim, "build", no_build)
    monkeypatch.setattr(run_rtl_experiment.rtlsim, "build", no_build)
    with pytest.raises(SystemExit) as e:
        run_rtl_experiment.main(["--config", str(ROOT / "configs/ap_toroidal.json"), "--gens", "201"])
    assert e.value.code != 0 and "200" in capsys.readouterr().err
