# Verification guide

## What a passing test proves

The independent Python model computes architectural effects instruction by instruction, without reproducing pipeline or cache state. Cocotb compares retirement order and all registers after each instruction, then every register and every data-memory word at completion. The mixed program helped expose a WB forwarding bug during a simultaneous cache stall. This is stronger than checking a few final outputs, but it is not exhaustive formal verification.

Six tests cover arithmetic/forwarding, memory and cache conflicts, branches and jumps, a deterministic mixed workload, the assembly example, and unsupported-instruction fault reporting. A failed assertion shows the first differing register or memory address, expected/actual values, and (for the mixed workload) the instruction PC.

## Read the output

Run the suite from WSL with `.venv/bin/python verification/run.py --sim verilator`. The terminal prints PASS/FAIL per test; the runner exits with code 1 if any test fails. `artifacts/metrics_verilator.json` records counters for each completed program. `artifacts/metrics_icarus.json` is the same format for Icarus. The XML result file in the simulator build directory can be used by CI.

The counters are sampled when the expected final instruction retires. `cycles` includes filling and draining the five-stage pipeline, `stalls` includes load-use bubbles and cache waits, `flushes` counts redirects, and `cache_misses` counts read misses. These are observations of the simulated RTL; they do not imply a real processor frequency, energy, silicon area, or FPGA maximum clock rate.

The cache test writes `artifacts/pipeline_trace.csv`. Re-run `scripts/render_trace.py` to get the GitHub-friendly SVG. To inspect every signal, open the committed `artifacts/cache_demo.vcd` with GTKWave, or use `--waves --test loads_stores_cache_and_load_use` to regenerate a VCD. Useful signal groups are `rv32_soc.core.pc`, `ifid/idex/exmem/memwb`, `load_use_stall`, `memory_stall`, `redirect`, `rv32_soc.cache.*`, and the debug counters. For GTKWave, zoom around the first `LW` miss and the following dependent `ADDI`; watch the PC freeze and the ID/EX bubble.

## Further verification worth adding

1. Compare retired PC and register-write transactions against a reference ISS for many randomly generated branch-heavy programs.
2. Add SystemVerilog assertions for `x0==0`, no architectural write from a bubble, stable stage registers during a cache miss, and correct forwarding priority.
3. Run formal bounded checks on small memory configurations, then exercise an external bus and nonzero memory wait states.
4. For an FPGA phase, synthesize a board top with explicit block RAM, measure area/Fmax, and separate those physical measurements from simulation counters.
