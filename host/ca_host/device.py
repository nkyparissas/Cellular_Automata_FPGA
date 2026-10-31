"""Transport-independent access to a CA core: 32-bit registers and memory."""
from abc import ABC, abstractmethod


class Device(ABC):
    @abstractmethod
    def read_reg(self, off: int) -> int: ...

    @abstractmethod
    def write_reg(self, off: int, val: int) -> None: ...

    @abstractmethod
    def read_mem(self, addr: int, n: int) -> bytes: ...

    @abstractmethod
    def write_mem(self, addr: int, data: bytes) -> None: ...

    def write_regs(self, writes) -> None:
        """Write (offset, value) pairs in order; transports may pipeline them."""
        for off, val in writes:
            self.write_reg(off, val)

    def close(self) -> None:
        pass
