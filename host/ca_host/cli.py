"""Run a CA configuration on hardware (XDMA or UART) or on the simulated device.

Examples:
    python3 -m ca_host.cli --transport xdma --config configs/hodgepodge29.json
    python3 -m ca_host.cli --transport uart --port /dev/ttyUSB1 --config configs/ghm_circle_toroidal.json
    python3 -m ca_host.cli --transport sim --config configs/ap_toroidal.json --frames 10 --headless --out frames

Host-paced cores (XDMA, sim) run one pass per frame the host requests and show
every frame. On display boards (UART) the display requests the passes, so the
CLI loads and starts the run and then takes commands on stdin: '+' faster,
'-' slower, 'p' pause/resume, 's' snapshot (read under PAUSE), 'q' quit and
leave the board running, 'x' stop and quit.
"""
import argparse
import sys

from ca_model import config
from ca_model.grids import load_seed

from .controller import CAController
from .viewer import Viewer


def open_device(args, cfg):
    if args.transport == "sim":
        from .simdev import SimDevice
        return SimDevice(cfg)
    if args.transport == "xdma":
        from .xdma import XdmaDevice
        return XdmaDevice(prefix=args.device)
    from .uart import UartDevice
    return UartDevice(port=args.port, baud=args.baud)


def run_host_paced(ctl: CAController, viewer: Viewer, args) -> int:
    """Request, wait for and show one frame at a time; returns the frame count."""
    repeat, gpf, paused, n = args.frame_repeat, 1, False, 0
    try:
        while args.frames == 0 or n < args.frames:
            ctl.request_frame()
            gen = ctl.wait_frame()
            n += 1
            key = viewer.show(ctl.read_frame(), n)
            if key == "q":
                break
            if key in ("+", "-"):
                repeat = max(0, repeat + (1 if key == "-" else -1))
                ctl.set_frame_repeat(repeat)
            elif key == "f":
                gpf = {1: 2, 2: 4, 4: 8}.get(gpf, 1)
                ctl.set_gens_per_frame(gpf)
            elif key == " ":
                paused = not paused
                ctl.set_pause(paused)
            if key:
                print(f"frame {n}: generation {gen}, FRAME_REPEAT={repeat}, GENS_PER_FRAME={gpf}, paused={paused}")
    except KeyboardInterrupt:
        pass
    finally:
        final = ctl.generation()
        ctl.stop()
    print(f"{n} frames, generation {final}")
    return n


def run_display_paced(ctl: CAController, viewer: Viewer, args) -> int:
    """Steer a board whose display requests the passes; returns the snapshot count."""
    repeat, paused, n, stopped = args.frame_repeat, False, 0, False
    print("commands: + faster, - slower, p pause/resume, s snapshot, q quit (board keeps running), x stop and quit")
    try:
        for line in sys.stdin:
            cmd = line.strip()
            if cmd == "q":
                break
            if cmd == "x":
                ctl.stop()
                stopped = True
                break
            if cmd in ("+", "-"):
                repeat = max(0, repeat + (1 if cmd == "-" else -1))
                ctl.set_frame_repeat(repeat)
            elif cmd == "p":
                paused = not paused
                ctl.set_pause(paused)
            elif cmd == "s":
                n += 1
                gen, frame = ctl.snapshot()
                viewer.show(frame, n)
                print(f"snapshot {n}: generation {gen}")
            if cmd:
                print(f"generation {ctl.generation()}, FRAME_REPEAT={repeat}, paused={paused}")
    except KeyboardInterrupt:
        pass
    print(f"{n} snapshots, generation {ctl.generation()}" + ("" if stopped else "; the board keeps running"))
    return n


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--transport", choices=("xdma", "uart", "sim"), required=True)
    ap.add_argument("--config", required=True)
    ap.add_argument("--seed", help="seed image (default: the configuration's seed)")
    ap.add_argument("--device", default="/dev/xdma0", help="XDMA device prefix")
    ap.add_argument("--port", default="/dev/ttyUSB1", help="UART port")
    ap.add_argument("--baud", type=int, default=2_000_000)
    ap.add_argument("--paced-by", choices=("host", "display"),
                    help="who requests passes: the host (default for xdma and sim) or the board's display "
                         "(default for uart)")
    ap.add_argument("--frames", type=int, default=0, help="host-paced: stop after N frames (0: run until 'q')")
    ap.add_argument("--frame-repeat", type=int, default=0, help="initial FRAME_REPEAT")
    ap.add_argument("--headless", action="store_true", help="write PNG files instead of opening a window")
    ap.add_argument("--out", default="frames")
    args = ap.parse_args(argv)
    paced_by = args.paced_by or ("display" if args.transport == "uart" else "host")

    cfg = config.load(args.config)
    dev = open_device(args, cfg)
    ctl = CAController(dev, cfg)
    if args.transport == "uart":
        dev._unit = ctl.info()["data_bytes"]
    seed = load_seed(args.seed or cfg["seed"], cfg["seed_mode"], cfg.get("seed_value"))
    ctl.load_grid(seed)
    ctl.set_params(cfg["params"])
    ctl.set_frame_repeat(args.frame_repeat)
    ctl.set_gens_per_frame(1)
    ctl.start()
    viewer = Viewer(cfg["cell_w"], cfg["palette"], headless=args.headless, out_dir=args.out, title=cfg["name"])
    try:
        if paced_by == "display":
            run_display_paced(ctl, viewer, args)
        else:
            run_host_paced(ctl, viewer, args)
    finally:
        viewer.close()
        dev.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
