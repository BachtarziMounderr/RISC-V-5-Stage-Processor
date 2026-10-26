"""Build and run the same cocotb suite with Verilator or Icarus Verilog."""

from __future__ import annotations

import argparse
import os
import shutil
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from cocotb_tools import config
from cocotb_tools.runner import get_runner

ROOT = Path(__file__).resolve().parents[1]
RTL = ROOT / "rtl"
SOURCES = [RTL / f"rv32_{name}.sv" for name in
           ("alu", "regfile", "decode", "dcache", "core", "soc")]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sim", choices=("verilator", "icarus"), default="verilator")
    parser.add_argument("--waves", action="store_true", help="save a simulator waveform")
    parser.add_argument("--test", help="run one named cocotb test")
    parser.add_argument("--verilator-bin", type=Path,
                        help="directory containing a local Verilator binary")
    args = parser.parse_args()

    if args.verilator_bin:
        os.environ["PATH"] = f"{args.verilator_bin}{os.pathsep}{os.environ['PATH']}"
    runner = get_runner(args.sim)
    metrics_path = ROOT / "artifacts" / f"metrics_{args.sim}.json"
    if metrics_path.exists():
        metrics_path.unlink()
    build_dir = (Path.home() / ".cache" / "rv32_verilator_sim"
                 if args.sim == "verilator" and " " in str(ROOT)
                 else ROOT / "sim_build" / args.sim)
    sources = SOURCES
    if args.sim == "verilator" and " " in str(ROOT):
        if " " in str(config.share_dir) or " " in str(config.libs_dir):
            raise SystemExit(
                "Verilator's generated Makefile cannot use a cocotb installation under "
                "a path with spaces. Create a WSL venv at ~/rv32-venv and run this "
                "script with ~/rv32-venv/bin/python."
            )
        stage = build_dir / "staged_rtl"
        stage.mkdir(parents=True, exist_ok=True)
        sources = []
        for source in SOURCES:
            target = stage / source.name
            shutil.copy2(source, target)
            sources.append(target)
    runner.build(
        sources=sources,
        hdl_toplevel="rv32_soc",
        build_dir=build_dir,
        build_args=["-Wall"] if args.sim == "verilator" else ["-g2012"],
        always=True,
        waves=args.waves,
        timescale=("1ns", "1ps"),
    )
    sys.path.insert(0, str(ROOT))
    results = runner.test(
        test_module="verification.test_core",
        hdl_toplevel="rv32_soc",
        build_dir=build_dir,
        testcase=args.test,
        waves=args.waves,
        extra_env={"RV32_SIMULATOR": args.sim},
        timescale=("1ns", "1ps"),
        results_xml="results.xml",
    )
    suite = ET.parse(results).getroot()
    tests = suite.findall(".//testcase")
    failures = suite.findall(".//failure") + suite.findall(".//error")
    print(f"{len(tests)} cocotb tests: {len(tests) - len(failures)} passed, {len(failures)} failed")
    if not tests or failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
