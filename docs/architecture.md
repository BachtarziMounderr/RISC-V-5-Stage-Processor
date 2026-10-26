# Architecture notes

## Machine model

This core executes a documented RV32I subset on a 32-bit little-endian architectural state. Instruction and data spaces are separate arrays of 256 words, each addressed with a byte address from `0x000` through `0x3fc`. They are initialized to NOPs and zeros in the simulation wrapper, and can be preloaded through debug ports while `run=0`. The core fetches one 32-bit instruction each cycle when it is free to advance. This is a Harvard-style teaching memory system, with a small data cache in front of the data array.

The subset comprises `ADD`, `SUB`, `AND`, `OR`, `XOR`, `SLT`, `SLTU`, `SLL`, `SRL`, `SRA`, their legal immediate counterparts, `LUI`, `AUIPC`, `LW`, `SW`, six standard conditional branches, `JAL`, and `JALR`. There is no compressed ISA; an instruction PC must be 4-byte aligned.

## Pipeline

| Stage | Work and interstage state |
| --- | --- |
| IF | Supply PC to instruction memory and fetch its 32-bit word. |
| ID | Decode opcode and immediate; read `rs1`/`rs2`; capture control signals and operands. |
| EX | Forward recent producer results; run ALU; decide branch/jump target. |
| MEM | Issue `LW`/`SW` to the small cache and backing memory. |
| WB | Commit register result and count a retired instruction. |

Pipeline registers carry validity bits so inserted bubbles and branch flushes cannot write state. `x0` ignores writes. The register file writes on the rising edge and supplies combinational reads; WB-to-ID bypass handles same-cycle observation.

## Hazards

* **ALU dependency:** EX forwards a value from EX/MEM or MEM/WB, preferring the younger EX/MEM producer.
* **Load-use dependency:** A consumer directly after `LW` inserts one bubble because the load value is not yet available in EX.
* **Cache miss:** MEM holds the miss request for one additional cycle; all younger stages are frozen. The older WB stage may still retire. Forwarded WB operand values are copied into the held EX operands before WB clears, preventing a stale read when the pipeline resumes.
* **Branch or jump:** EX computes the decision/target, and a taken redirect invalidates IF/ID and ID/EX. There is no prediction or delay slot.

The cache has eight direct-mapped lines. Each line holds one 32-bit word, a tag, and a valid bit. A read hit is combinational; a read miss fills a line from the backing array at the next rising edge. Stores always update backing memory and update a cache line only on a hit, giving write-through/no-write-allocate behavior. This is an intentionally simple functional cache; bus timing, byte enables, arbitration, and realistic memory latency are outside this version.

## Boundary and fault behavior

The `rv32_soc` wrapper returns NOP for an instruction address outside its instruction array and zero for an out-of-range data read. Aligned stores outside the array are ignored. Unsupported instructions are turned into bubbles and set sticky `debug_fault`; misaligned memory access or jump target also sets the flag. These are debug behaviors, **not RISC-V traps**. Tests use supported aligned accesses in range. The wrapper is intended for RTL simulation; a synthesizable board top with target RAM and I/O remains a separate step.
