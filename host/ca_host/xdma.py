"""XDMA transport (Xilinx dma_ip_drivers, memory-mapped mode).

Registers: the AXI-Lite BAR exposed as /dev/xdma0_user, accessed through mmap.
Memory:    /dev/xdma0_h2c_0 (write) and /dev/xdma0_c2h_0 (read); the file
           offset is the address in the XDMA M_AXI space (the board DDR).
"""
import mmap
import os
import struct

from .device import Device


class XdmaDevice(Device):
    def __init__(self, prefix: str = "/dev/xdma0", user_size: int = 0x10000,
                 user_path=None, h2c_path=None, c2h_path=None):
        self._user_fd = os.open(str(user_path or f"{prefix}_user"), os.O_RDWR | os.O_SYNC)
        self._regs = mmap.mmap(self._user_fd, user_size, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE)
        self._h2c = os.open(str(h2c_path or f"{prefix}_h2c_0"), os.O_WRONLY)
        self._c2h = os.open(str(c2h_path or f"{prefix}_c2h_0"), os.O_RDONLY)

    def read_reg(self, off: int) -> int:
        return struct.unpack_from("<I", self._regs, off)[0]

    def write_reg(self, off: int, val: int) -> None:
        struct.pack_into("<I", self._regs, off, val & 0xFFFFFFFF)

    def read_mem(self, addr: int, n: int) -> bytes:
        out = bytearray()
        while len(out) < n:
            chunk = os.pread(self._c2h, n - len(out), addr + len(out))
            if not chunk:
                raise IOError(f"short DMA read at 0x{addr + len(out):x}")
            out += chunk
        return bytes(out)

    def write_mem(self, addr: int, data: bytes) -> None:
        done = 0
        while done < len(data):
            done += os.pwrite(self._h2c, data[done:], addr + done)

    def close(self) -> None:
        self._regs.close()
        for fd in (self._user_fd, self._h2c, self._c2h):
            os.close(fd)
