"""Precision regression (design spec 2026-10-31, Section 9.2): the fixed-point
model with 16-bit cells, 6-bit weights and a 12-bit table index tracks the
floating-point update of the Lenia tutorial on two creatures."""
import numpy as np

from ca_model import lenia
from ca_model.neigh import Boundary

STEPS = 500


def float_kernel(R, beta, size):
    """The tutorial's kernel on a size x size torus, normalised and centred at (0, 0)."""
    mid = size // 2
    i = np.arange(size) - mid
    D = np.sqrt(i[:, None] ** 2 + i[None, :] ** 2) / R * len(beta)
    K = (D < len(beta)) * np.asarray(beta)[np.minimum(D.astype(int), len(beta) - 1)] * lenia.bell(D % 1, 0.5, 0.15)
    return np.fft.rfft2(np.fft.fftshift(K / K.sum()))


def centre_of_mass(A):
    """Toroidal centre of mass (row, column)."""
    out = []
    for axis, n in ((1, A.shape[0]), (0, A.shape[1])):
        phase = np.exp(2j * np.pi * np.arange(n) / n)
        out.append(np.angle((A.sum(axis=axis) * phase).sum()) * n / (2 * np.pi) % n)
    return np.array(out)


def gyration(A):
    """Radius of gyration of A after moving its centre of mass to the middle."""
    c = centre_of_mass(A)
    A = np.roll(A, (int(round(A.shape[0] / 2 - c[0])), int(round(A.shape[1] / 2 - c[1]))), axis=(0, 1))
    yy, xx = np.mgrid[0:A.shape[0], 0:A.shape[1]]
    r2 = (yy - A.shape[0] / 2) ** 2 + (xx - A.shape[1] / 2) ** 2
    return np.sqrt((A * r2).sum() / max(A.sum(), 1e-12))


def track(states):
    """Mass per step, step lengths of the centre of mass, and gyration every 10 steps."""
    mass = np.array([s.sum() for s in states])
    pos = [centre_of_mass(s) for s in states]
    shape = np.array(states[0].shape)
    steps = [np.linalg.norm((b - a + shape / 2) % shape - shape / 2) for a, b in zip(pos, pos[1:])]
    return mass, np.array(steps), np.array([gyration(s) for s in states[::10]])


def run_both(name, size, at):
    p = lenia.load_pattern(name)
    A0 = np.zeros((size, size))
    cells = p["cells"]
    A0[at:at + cells.shape[0], at:at + cells.shape[1]] = cells
    fK = float_kernel(p["R"], p["beta"], size)
    A, flt = A0.copy(), [A0.copy()]
    for _ in range(STEPS):
        U = np.fft.irfft2(fK * np.fft.rfft2(A), s=A.shape)
        A = np.clip(A + (2 * lenia.bell(U, p["mu"], p["sigma"]) - 1) / p["T"], 0, 1)
        flt.append(A)
    nbh = 2 * p["R"] + 1
    cfg = {"nbh": nbh, "cell_w": 16, "weight_w": 6, "lut_idx_w": 12,
           "params": {k: p[k] for k in lenia.LENIA_PARAMS}}
    w, table, sh = lenia.cfg_kernel(cfg)
    q = np.clip(np.rint(A0 * 65536), 0, 65535).astype(np.uint16)
    fix = [q / 65536.0]
    for _ in range(STEPS):
        q = lenia.step_lenia(q, w, table, sh, nbh, 16, Boundary.TOROIDAL)
        fix.append(q / 65536.0)
    return track(fix), track(flt)


def test_orbium_precision():
    (m, sp, _), (mf, spf, _) = run_both("orbium", 128, 20)
    assert 0.3 * m[0] < m[-1] < 3 * m[0]
    assert np.mean(np.abs(m - mf)) / np.mean(mf) < 0.03
    half = len(sp) // 2
    assert abs(np.mean(sp[half:]) / np.mean(spf[half:]) - 1) < 0.02


def test_hydrogeminium_precision():
    (m, sp, rg), (mf, spf, rgf) = run_both("hydrogeminium", 192, 30)
    assert 0.3 * m[0] < m[-1] < 3 * m[0]
    half, hg = len(sp) // 2, len(rg) // 2
    assert abs(np.mean(sp[half:]) / np.mean(spf[half:]) - 1) < 0.03
    assert abs(np.mean(rg[hg:]) / np.mean(rgf[hg:]) - 1) < 0.03
