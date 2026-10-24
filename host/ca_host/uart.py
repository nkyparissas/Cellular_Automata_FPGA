"""UART transport for display boards (protocol of rtl/io/ca_uart_bridge.sv)."""
import struct

from .device import Device


def encode_reg_write(off: int, val: int) -> bytes:
    return b"\x10" + struct.pack("<II", off, val & 0xFFFFFFFF)


def encode_reg_read(off: int) -> bytes:
    return b"\x11" + struct.pack("<I", off)


def encode_mem_write(addr: int, data: bytes) -> bytes:
    return b"\x20" + struct.pack("<II", addr, len(data)) + bytes(data)


def encode_mem_read(addr: int, n: int) -> bytes:
    return b"\x21" + struct.pack("<II", addr, n)


class UartDevice(Device):
    """`serial_port` is any object with write(bytes) and read(n) (a pyserial
    Serial by default); `data_bytes` is DATA_W/8 of the design."""

    def __init__(self, port: str | None = None, baud: int = 2_000_000, timeout: float = 5.0,
                 serial_port=None, data_bytes: int = 16):
        if serial_port is None:
            import serial  # pyserial
            serial_port = serial.Serial(port, baud, timeout=timeout)
        self._s = serial_port
        self._unit = data_bytes

    def _read_exact(self, n: int) -> bytes:
        out = bytearray()
        while len(out) < n:
            chunk = self._s.read(n - len(out))
            if not chunk:
                raise TimeoutError(f"UART: expected {n} bytes, got {len(out)}")
            out += chunk
        return bytes(out)

    def _expect(self, code: int) -> None:
        got = self._read_exact(1)[0]
        if got != code:
            raise IOError(f"UART: reply 0x{got:02x}, expected 0x{code:02x}")

    def read_reg(self, off: int) -> int:
        self._s.write(encode_reg_read(off))
        self._expect(0x11)
        return struct.unpack("<I", self._read_exact(4))[0]

    def write_reg(self, off: int, val: int) -> None:
        self._s.write(encode_reg_write(off, val))
        self._expect(0x10)

    def read_mem(self, addr: int, n: int) -> bytes:
        self._check(addr, n)
        self._s.write(encode_mem_read(addr, n))
        self._expect(0x21)
        return self._read_exact(n)

    def write_mem(self, addr: int, data: bytes) -> None:
        self._check(addr, len(data))
        self._s.write(encode_mem_write(addr, data))
        self._expect(0x20)

    def _check(self, addr: int, n: int) -> None:
        if addr % self._unit or n % self._unit:
            raise ValueError(f"UART memory transfers must be aligned to {self._unit} bytes")

    def close(self) -> None:
        if hasattr(self._s, "close"):
            self._s.close()
