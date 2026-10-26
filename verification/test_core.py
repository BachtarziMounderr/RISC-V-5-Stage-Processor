"""Cocotb architectural checks against an independent sequential model."""

from __future__ import annotations

import csv
import json
import os
import random
from pathlib import Path

import cocotb
from cocotb.triggers import Timer

from verification.model import (
    NOP, Reference, addi, beq, bne, b_type, i_type, jal, jalr, lw,
    r_type, sw, u_type,
)

ROOT = Path(__file__).resolve().parents[1]


async def tick(dut) -> None:
    dut.clk.value = 0
    await Timer(5, unit="ns")
    dut.clk.value = 1
    await Timer(5, unit="ns")


async def load_program(dut, program: list[int], data: dict[int, int]) -> None:
    dut.run.value = 0
    dut.reset.value = 1
    dut.program_write.value = 0
    dut.data_preload_write.value = 0
    dut.program_address.value = 0
    dut.program_data.value = 0
    dut.data_preload_address.value = 0
    dut.data_preload_value.value = 0
    dut.debug_data_address.value = 0
    dut.debug_register_address.value = 0
    await tick(dut)

    # Clear the entire small memory so tests remain independent in one run.
    for index in range(256):
        dut.program_write.value = 1
        dut.program_address.value = index * 4
        dut.program_data.value = program[index] if index < len(program) else NOP
        dut.data_preload_write.value = 1
        dut.data_preload_address.value = index * 4
        dut.data_preload_value.value = data.get(index * 4, 0)
        await tick(dut)

    dut.program_write.value = 0
    dut.data_preload_write.value = 0
    await tick(dut)
    dut.reset.value = 0
    dut.run.value = 1


async def execute(dut, program: list[int], data: dict[int, int] | None = None,
                  *, case: str, save_trace: bool = False,
                  step_check: bool = True) -> dict[str, int]:
    data = data or {}
    reference = Reference(program, data).run()
    await load_program(dut, program, data)
    retiring_reference = Reference(program, data) if step_check else None

    trace: list[dict[str, int]] = []
    cycle_limit = reference.retired * 5 + 24
    for cycle in range(cycle_limit):
        if save_trace:
            trace.append({
                "cycle": cycle,
                "if_pc": int(dut.trace_if_pc.value),
                "id_pc": int(dut.trace_id_pc.value),
                "ex_pc": int(dut.trace_ex_pc.value),
                "mem_pc": int(dut.trace_mem_pc.value),
                "wb_pc": int(dut.trace_wb_pc.value),
                "valid": int(dut.trace_valid.value),
                "load_stall": int(dut.trace_load_stall.value),
                "memory_stall": int(dut.trace_memory_stall.value),
                "redirect": int(dut.trace_redirect.value),
            })
        retiring_pc = int(dut.trace_wb_pc.value) if step_check and int(dut.trace_valid.value) & 16 else None
        await tick(dut)
        if retiring_pc is not None and retiring_pc < len(program) * 4:
            assert retiring_reference is not None
            assert retiring_reference.pc == retiring_pc, (
                f"retirement order: RTL PC=0x{retiring_pc:08x}, reference PC=0x{retiring_reference.pc:08x}"
            )
            retiring_reference.step()
            for register in range(32):
                dut.debug_register_address.value = register
                await Timer(1, unit="ns")
                actual = int(dut.debug_register_value.value)
                expected = retiring_reference.registers[register]
                assert actual == expected, (
                    f"after PC=0x{retiring_pc:08x}, instruction=0x{program[retiring_pc // 4]:08x}: "
                    f"x{register} RTL=0x{actual:08x}, reference=0x{expected:08x}; "
                    f"nearby={[hex(word) for word in program[max(0, retiring_pc // 4 - 4):retiring_pc // 4 + 2]]}"
                )
        elif retiring_pc is not None and retiring_reference is not None:
            assert retiring_reference.retired == reference.retired, (
                f"RTL retired a NOP at PC=0x{retiring_pc:08x} before completing the program"
            )
        if int(dut.debug_retired.value) >= reference.retired:
            break
    else:
        raise TimeoutError(f"RTL did not retire {reference.retired} instructions")
    if retiring_reference is not None:
        assert retiring_reference.retired == reference.retired

    for register in range(32):
        dut.debug_register_address.value = register
        await Timer(1, unit="ns")
        actual = int(dut.debug_register_value.value)
        expected = reference.registers[register]
        assert actual == expected, (
            f"x{register}: RTL=0x{actual:08x}, reference=0x{expected:08x}"
        )

    for address in range(0, 256 * 4, 4):
        dut.debug_data_address.value = address
        await Timer(1, unit="ns")
        actual = int(dut.debug_data_value.value)
        expected = reference.memory[address // 4]
        assert actual == expected, (
            f"data[0x{address:03x}]: RTL=0x{actual:08x}, reference=0x{expected:08x}"
        )

    assert int(dut.debug_fault.value) == 0, "RTL flagged an illegal/alignment fault"
    metrics = {
        "cycles": int(dut.debug_cycles.value),
        "retired": int(dut.debug_retired.value),
        "stalls": int(dut.debug_stalls.value),
        "flushes": int(dut.debug_flushes.value),
        "cache_misses": int(dut.debug_cache_misses.value),
        "reference_instructions": reference.retired,
    }
    if save_trace:
        output = ROOT / "artifacts" / "pipeline_trace.csv"
        output.parent.mkdir(exist_ok=True)
        with output.open("w", newline="", encoding="utf-8") as stream:
            writer = csv.DictWriter(stream, fieldnames=list(trace[0]))
            writer.writeheader()
            writer.writerows(trace[: min(42, len(trace))])
    metrics_path = ROOT / "artifacts" / f"metrics_{os.environ.get('RV32_SIMULATOR', 'unknown')}.json"
    metrics_path.parent.mkdir(exist_ok=True)
    previous = json.loads(metrics_path.read_text(encoding="utf-8")) if metrics_path.exists() else {}
    previous[case] = metrics
    metrics_path.write_text(json.dumps(previous, indent=2) + "\n", encoding="utf-8")
    dut._log.info("Architectural comparison passed: %s", metrics)
    return metrics


@cocotb.test()
async def arithmetic_and_forwarding(dut):
    program = [
        addi(1, 0, 7), addi(2, 0, -3),
        r_type(0, 2, 1, 0, 3),        # ADD: 7 + (-3)
        r_type(0x20, 2, 3, 0, 4),     # SUB: 4 - (-3)
        r_type(0, 4, 3, 7, 5),        # AND
        r_type(0, 4, 3, 6, 6),        # OR
        r_type(0, 2, 1, 4, 7),        # XOR
        r_type(0, 1, 2, 2, 8),        # SLT signed
        r_type(0, 1, 2, 3, 9),        # SLTU unsigned
        i_type(3, 1, 1, 10),          # SLLI
        i_type(2, 2, 5, 11),          # SRLI
        i_type(0x402, 2, 5, 12),      # SRAI
        r_type(0, 1, 10, 5, 13),     # SRL
        r_type(0x20, 1, 2, 5, 14),  # SRA
        i_type(-1, 1, 7, 15),        # ANDI
        i_type(12, 1, 6, 16),        # ORI
        i_type(3, 1, 4, 17),         # XORI
        i_type(0, 2, 2, 18),         # SLTI
        i_type(0, 2, 3, 19),         # SLTIU
        u_type(0x12345000, 20, 0x37),
        u_type(0x00001000, 21, 0x17),
        addi(0, 1, 99),              # x0 is hardwired to zero
    ]
    await execute(dut, program, case="arithmetic_and_forwarding")


@cocotb.test()
async def loads_stores_cache_and_load_use(dut):
    program = [
        lw(1, 0, 0), addi(2, 1, 3), sw(2, 0, 4),
        lw(3, 0, 4), lw(4, 0, 0), lw(5, 0, 32),
        lw(6, 0, 0), sw(6, 0, 0), lw(7, 0, 0),
        r_type(0, 7, 2, 0, 8),
    ]
    metrics = await execute(dut, program, {0: 5, 32: 9},
                            case="loads_stores_cache_and_load_use", save_trace=True)
    assert metrics["cache_misses"] >= 4
    assert metrics["stalls"] > metrics["cache_misses"]


@cocotb.test()
async def control_flow_and_flush(dut):
    program = [
        addi(1, 0, 0), addi(2, 0, 5),
        addi(1, 1, 1), bne(1, 2, -4),
        addi(3, 0, -1), b_type(8, 2, 3, 4),
        addi(4, 0, 99), jal(5, 8),
        addi(6, 0, 99), addi(8, 0, 48),
        jalr(9, 8), addi(10, 0, 99),
        addi(11, 0, 42), beq(1, 2, 8),
        addi(12, 0, 99), b_type(8, 1, 2, 7),
        addi(13, 0, 99), addi(14, 0, 77),
    ]
    metrics = await execute(dut, program, case="control_flow_and_flush")
    assert metrics["flushes"] >= 8


@cocotb.test()
async def seeded_mixed_program(dut):
    rng = random.Random(20261026)
    program = [addi(1, 0, -17), addi(2, 0, 31)]
    r_ops = [(0, 0), (0x20, 0), (0, 7), (0, 6), (0, 4),
             (0, 2), (0, 3), (0, 1), (0, 5), (0x20, 5)]
    for _ in range(80):
        op = rng.randrange(4)
        rd = rng.randrange(1, 16)
        rs1 = rng.randrange(0, 16)
        if op == 0:
            program.append(addi(rd, rs1, rng.randrange(-100, 100)))
        elif op == 1:
            funct7, funct3 = rng.choice(r_ops)
            program.append(r_type(funct7, rng.randrange(0, 16), rs1, funct3, rd))
        elif op == 2:
            program.append(lw(rd, 0, rng.randrange(0, 16) * 4))
        else:
            program.append(sw(rng.randrange(0, 16), 0, rng.randrange(0, 16) * 4))
    await execute(dut, program, {address: address ^ 0xA5A5 for address in range(0, 64, 4)},
                  case="seeded_mixed_program", step_check=True)


@cocotb.test()
async def sum_1_to_10_example(dut):
    image = ROOT / "examples" / "sum_1_to_10.hex"
    program = [int(line, 16) for line in image.read_text(encoding="ascii").splitlines()]
    await execute(dut, program, case="sum_1_to_10_example", step_check=True)
    dut.debug_register_address.value = 3
    dut.debug_data_address.value = 0
    await Timer(1, unit="ns")
    assert int(dut.debug_register_value.value) == 55
    assert int(dut.debug_data_value.value) == 55


@cocotb.test()
async def unsupported_instruction_sets_fault(dut):
    await load_program(dut, [0xFFFF_FFFF, addi(1, 0, 11)], {})
    for _ in range(12):
        await tick(dut)
    assert int(dut.debug_fault.value) == 1
    dut.debug_register_address.value = 1
    await Timer(1, unit="ns")
    assert int(dut.debug_register_value.value) == 11
