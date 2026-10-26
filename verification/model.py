"""Small independent RV32I-subset assembler and architectural reference model.

The model executes one instruction at a time. It has no pipeline or cache state;
that makes it useful for checking the architectural results of the RTL.
"""

from __future__ import annotations

from dataclasses import dataclass, field

MASK = 0xFFFF_FFFF
NOP = 0x0000_0013


def u32(value: int) -> int:
    return value & MASK


def signed(value: int, bits: int = 32) -> int:
    value &= (1 << bits) - 1
    return value - (1 << bits) if value & (1 << (bits - 1)) else value


def r_type(funct7: int, rs2: int, rs1: int, funct3: int, rd: int) -> int:
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | 0x33


def i_type(imm: int, rs1: int, funct3: int, rd: int, opcode: int = 0x13) -> int:
    assert -2048 <= imm <= 4095
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def s_type(imm: int, rs2: int, rs1: int, funct3: int = 2) -> int:
    assert -2048 <= imm <= 2047
    imm &= 0xFFF
    return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | ((imm & 31) << 7) | 0x23


def b_type(imm: int, rs2: int, rs1: int, funct3: int) -> int:
    assert -4096 <= imm <= 4094 and imm % 2 == 0
    imm &= 0x1FFF
    return (((imm >> 12) & 1) << 31) | (((imm >> 5) & 63) << 25) | (rs2 << 20) | \
           (rs1 << 15) | (funct3 << 12) | (((imm >> 1) & 15) << 8) | \
           (((imm >> 11) & 1) << 7) | 0x63


def u_type(imm: int, rd: int, opcode: int) -> int:
    return (imm & 0xFFFF_F000) | (rd << 7) | opcode


def j_type(imm: int, rd: int) -> int:
    assert -(1 << 20) <= imm < (1 << 20) and imm % 2 == 0
    imm &= 0x1F_FFFF
    return (((imm >> 20) & 1) << 31) | (((imm >> 1) & 0x3FF) << 21) | \
           (((imm >> 11) & 1) << 20) | (((imm >> 12) & 0xFF) << 12) | (rd << 7) | 0x6F


def addi(rd: int, rs1: int, imm: int) -> int:
    return i_type(imm, rs1, 0, rd)


def lw(rd: int, rs1: int, imm: int = 0) -> int:
    return i_type(imm, rs1, 2, rd, 0x03)


def sw(rs2: int, rs1: int, imm: int = 0) -> int:
    return s_type(imm, rs2, rs1)


def beq(rs1: int, rs2: int, imm: int) -> int:
    return b_type(imm, rs2, rs1, 0)


def bne(rs1: int, rs2: int, imm: int) -> int:
    return b_type(imm, rs2, rs1, 1)


def jal(rd: int, imm: int) -> int:
    return j_type(imm, rd)


def jalr(rd: int, rs1: int, imm: int = 0) -> int:
    return i_type(imm, rs1, 0, rd, 0x67)


@dataclass
class Reference:
    program: list[int]
    initial_data: dict[int, int] = field(default_factory=dict)
    registers: list[int] = field(default_factory=lambda: [0] * 32)
    memory: list[int] = field(default_factory=lambda: [0] * 256)
    pc: int = 0
    retired: int = 0

    def __post_init__(self) -> None:
        for address, value in self.initial_data.items():
            assert address % 4 == 0 and 0 <= address < len(self.memory) * 4
            self.memory[address // 4] = u32(value)

    def _load(self, address: int) -> int:
        assert address % 4 == 0 and 0 <= address < len(self.memory) * 4
        return self.memory[address // 4]

    def _store(self, address: int, value: int) -> None:
        assert address % 4 == 0 and 0 <= address < len(self.memory) * 4
        self.memory[address // 4] = u32(value)

    def step(self) -> bool:
        if self.pc // 4 >= len(self.program):
            return False
        insn = self.program[self.pc // 4]
        opcode = insn & 0x7F
        rd = (insn >> 7) & 31
        funct3 = (insn >> 12) & 7
        rs1 = (insn >> 15) & 31
        rs2 = (insn >> 20) & 31
        funct7 = (insn >> 25) & 127
        a, b = self.registers[rs1], self.registers[rs2]
        next_pc = u32(self.pc + 4)
        result = 0
        writes = False

        if opcode in (0x33, 0x13):
            immediate_form = opcode == 0x13
            operand = signed(insn >> 20, 12) if immediate_form else b
            shift = operand & 31
            if funct3 == 0:
                result = a - operand if not immediate_form and funct7 == 0x20 else a + operand
            elif funct3 == 7:
                result = a & operand
            elif funct3 == 6:
                result = a | operand
            elif funct3 == 4:
                result = a ^ operand
            elif funct3 == 2:
                result = int(signed(a) < signed(operand))
            elif funct3 == 3:
                result = int(u32(a) < u32(operand))
            elif funct3 == 1:
                result = a << shift
            elif funct3 == 5:
                arithmetic = funct7 == 0x20
                result = signed(a) >> shift if arithmetic else u32(a) >> shift
            else:
                raise ValueError(f"Unsupported arithmetic instruction {insn:08x}")
            writes = True
        elif opcode == 0x03 and funct3 == 2:
            result = self._load(u32(a + signed(insn >> 20, 12)))
            writes = True
        elif opcode == 0x23 and funct3 == 2:
            imm = signed(((insn >> 25) << 5) | ((insn >> 7) & 31), 12)
            self._store(u32(a + imm), b)
        elif opcode == 0x63:
            imm = signed((((insn >> 31) & 1) << 12) | (((insn >> 7) & 1) << 11) |
                         (((insn >> 25) & 63) << 5) | (((insn >> 8) & 15) << 1), 13)
            condition = {0: a == b, 1: a != b, 4: signed(a) < signed(b),
                         5: signed(a) >= signed(b), 6: a < b, 7: a >= b}[funct3]
            if condition:
                next_pc = u32(self.pc + imm)
        elif opcode == 0x6F:
            imm = signed((((insn >> 31) & 1) << 20) | (((insn >> 12) & 255) << 12) |
                         (((insn >> 20) & 1) << 11) | (((insn >> 21) & 1023) << 1), 21)
            result, writes = next_pc, True
            next_pc = u32(self.pc + imm)
        elif opcode == 0x67 and funct3 == 0:
            result, writes = next_pc, True
            next_pc = u32(a + signed(insn >> 20, 12)) & ~1
        elif opcode == 0x37:
            result, writes = insn & 0xFFFF_F000, True
        elif opcode == 0x17:
            result, writes = self.pc + (insn & 0xFFFF_F000), True
        else:
            raise ValueError(f"Unsupported instruction {insn:08x} at PC {self.pc:08x}")

        if writes and rd != 0:
            self.registers[rd] = u32(result)
        self.registers[0] = 0
        self.pc = next_pc
        self.retired += 1
        return True

    def run(self, limit: int = 1000) -> "Reference":
        for _ in range(limit):
            if not self.step():
                return self
        raise TimeoutError("Reference model did not leave the program")
