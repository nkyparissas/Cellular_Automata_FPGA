"""XdmaDevice on file-backed stand-ins for the dma_ip_drivers device nodes."""
from ca_host import regs
from ca_host.xdma import XdmaDevice


def test_xdma_fake_nodes(tmp_path):
    user = tmp_path / "xdma0_user"
    mem = tmp_path / "ddr"
    user.write_bytes(bytes(0x10000))
    mem.write_bytes(bytes(1 << 20))
    dev = XdmaDevice(user_path=user, h2c_path=mem, c2h_path=mem, user_size=0x10000)
    dev.write_reg(regs.REG_FRAME_REPEAT, 0x1234ABCD)
    assert dev.read_reg(regs.REG_FRAME_REPEAT) == 0x1234ABCD
    assert user.read_bytes()[0x10:0x14] == bytes([0xCD, 0xAB, 0x34, 0x12])   # little-endian register
    payload = bytes(range(256)) * 16
    dev.write_mem(0x4_0000, payload)
    assert dev.read_mem(0x4_0000, len(payload)) == payload
    assert mem.read_bytes()[0x4_0000:0x4_0010] == payload[:16]                  # DDR address = file offset
    dev.close()
