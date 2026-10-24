"""CAController on the simulated device equals the golden model."""
import numpy as np

from ca_host.controller import CAController
from ca_host.simdev import SimDevice
from ca_model.step import step


def test_controller_sim_matches_model(small_cfg, small_seed):
    dev = SimDevice(small_cfg)
    ctl = CAController(dev, small_cfg)
    assert ctl.info()["grid_x"] == 32 and ctl.info()["cell_w"] == 8
    ctl.load_grid(small_seed)
    ctl.set_frame_repeat(0)
    ctl.start()
    exp = small_seed
    for g in range(1, 6):
        ctl.request_frame()
        assert ctl.wait_frame(timeout=1.0) == g
        exp = step(exp, small_cfg)
        assert np.array_equal(ctl.read_frame(), exp)


def test_frame_repeat_cadence(small_cfg, small_seed):
    dev = SimDevice(small_cfg)
    ctl = CAController(dev, small_cfg)
    ctl.load_grid(small_seed)
    ctl.set_frame_repeat(2)
    ctl.start()
    gens = []
    for _ in range(6):
        ctl.request_frame()
        gens.append(ctl.wait_frame(timeout=1.0))
    assert gens == [0, 0, 1, 1, 1, 2]


def test_pause_and_fast_forward(small_cfg, small_seed):
    dev = SimDevice(small_cfg)
    ctl = CAController(dev, small_cfg)
    ctl.load_grid(small_seed)
    ctl.set_frame_repeat(0)
    ctl.set_gens_per_frame(4)
    ctl.start()
    ctl.request_frame()
    assert ctl.wait_frame(timeout=1.0) == 4
    ctl.set_pause(True)
    ctl.request_frame()
    assert ctl.wait_frame(timeout=1.0) == 4
    exp = small_seed
    for _ in range(4):
        exp = step(exp, small_cfg)
    assert np.array_equal(ctl.read_frame(), exp)


def test_params_reach_device(small_cfg, small_seed):
    dev = SimDevice(small_cfg)
    ctl = CAController(dev, small_cfg)
    ctl.set_params({"G": 33, "K": 2})
    cfg2 = dict(small_cfg, params={"G": 33, "K": 2})
    ctl.load_grid(small_seed)
    ctl.set_frame_repeat(0)
    ctl.start()
    ctl.request_frame()
    ctl.wait_frame(timeout=1.0)
    assert np.array_equal(ctl.read_frame(), step(small_seed, cfg2))
