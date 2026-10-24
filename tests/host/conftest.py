import numpy as np
import pytest


@pytest.fixture
def small_cfg():
    return {"name": "tiny", "grid": [32, 24], "cell_w": 8, "nbh": 3, "boundary": "toroidal",
            "rule": "hodgepodge", "mask": "moore", "params": {"G": 20, "K": 3}}


@pytest.fixture
def small_seed():
    rng = np.random.default_rng(9)
    return rng.choice([0, 0, 0, 1, 50, 128, 254, 255], size=(24, 32)).astype(np.uint8)
