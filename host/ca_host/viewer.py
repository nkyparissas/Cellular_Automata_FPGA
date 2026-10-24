"""Frame display: an OpenCV window when available, PNG files otherwise.

Keys (window mode): '+' faster (FRAME_REPEAT - 1), '-' slower (FRAME_REPEAT + 1),
'f' cycles GENS_PER_FRAME 1/2/4/8, space toggles PAUSE, 's' saves a PNG, 'q' quits.
"""
from pathlib import Path

import numpy as np

from ca_model.grids import save_png, to_rgb


class Viewer:
    def __init__(self, cell_w: int, palette: str, headless: bool = False, out_dir=None, title: str = "CA"):
        self.cell_w, self.palette, self.title = cell_w, palette, title
        self.out = Path(out_dir) if out_dir else Path("frames")
        self.cv2 = None
        if not headless:
            try:
                import cv2
                self.cv2 = cv2
            except ImportError:
                print("OpenCV not available: writing PNG files instead")
        if self.cv2 is None:
            self.out.mkdir(parents=True, exist_ok=True)

    @property
    def windowed(self) -> bool:
        return self.cv2 is not None

    def show(self, frame: np.ndarray, index: int) -> str | None:
        """Display or save one frame; return the key pressed (window mode)."""
        if self.cv2 is None:
            save_png(frame, self.cell_w, self.palette, self.out / f"frame_{index:05d}.png")
            return None
        rgb = to_rgb(frame, self.cell_w, self.palette)
        self.cv2.imshow(self.title, rgb[:, :, ::-1])
        k = self.cv2.waitKey(1) & 0xFF
        if k == ord("s"):
            self.out.mkdir(parents=True, exist_ok=True)
            save_png(frame, self.cell_w, self.palette, self.out / f"frame_{index:05d}.png")
        return chr(k) if k != 0xFF else None

    def close(self) -> None:
        if self.cv2 is not None:
            self.cv2.destroyAllWindows()
