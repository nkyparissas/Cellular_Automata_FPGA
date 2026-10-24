"""UartDevice: byte-exact command frames (spec Section 14) and a loopback
against a Python stand-in for ca_uart_bridge."""
import struct

from ca_host import uart


def test_uart_encoding():
    assert uart.encode_reg_write(0x10, 0x01020304) == bytes([0x10, 0x10, 0, 0, 0, 4, 3, 2, 1])
    assert uart.encode_reg_read(0x18) == bytes([0x11, 0x18, 0, 0, 0])
    assert uart.encode_mem_write(0x100, b"\xaa" * 16) == bytes([0x20, 0, 1, 0, 0, 16, 0, 0, 0]) + b"\xaa" * 16
    assert uart.encode_mem_read(0x1000, 32) == bytes([0x21, 0, 0x10, 0, 0, 32, 0, 0, 0])


class FakeBridge:
    """Implements the bridge protocol on a byte stream (pyserial-like API)."""

    def __init__(self):
        self.regs, self.mem, self.rx, self.tx = {}, bytearray(1 << 16), bytearray(), bytearray()

    def write(self, data):
        self.rx += data
        self._process()
        return len(data)

    def read(self, n):
        out, self.tx = bytes(self.tx[:n]), self.tx[n:]
        return out

    def _process(self):
        while self.rx:
            cmd = self.rx[0]
            need = {0x10: 9, 0x11: 5, 0x20: 9, 0x21: 9}[cmd]
            if len(self.rx) < need:
                return
            addr = struct.unpack_from("<I", self.rx, 1)[0]
            if cmd == 0x10:
                self.regs[addr] = struct.unpack_from("<I", self.rx, 5)[0]
                self.tx += b"\x10"
            elif cmd == 0x11:
                self.tx += b"\x11" + struct.pack("<I", self.regs.get(addr, 0))
            elif cmd == 0x20:
                n = struct.unpack_from("<I", self.rx, 5)[0]
                if len(self.rx) < need + n:
                    return
                self.mem[addr:addr + n] = self.rx[need:need + n]
                need += n
                self.tx += b"\x20"
            else:
                n = struct.unpack_from("<I", self.rx, 5)[0]
                self.tx += b"\x21" + self.mem[addr:addr + n]
            del self.rx[:need]


def test_uart_device_loopback():
    dev = uart.UartDevice(serial_port=FakeBridge(), data_bytes=16)
    dev.write_reg(0x10, 77)
    assert dev.read_reg(0x10) == 77
    payload = bytes(range(64))
    dev.write_mem(0x200, payload)
    assert dev.read_mem(0x200, 64) == payload
