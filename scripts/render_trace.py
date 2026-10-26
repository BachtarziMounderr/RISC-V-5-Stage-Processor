"""Render a compact pipeline timeline from cocotb's CSV trace, using stdlib only."""

from __future__ import annotations

import argparse
import csv
from html import escape
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CSV = ROOT / "artifacts" / "pipeline_trace.csv"
DEFAULT_SVG = ROOT / "artifacts" / "pipeline_timeline.svg"


def render(source: Path, destination: Path) -> None:
    with source.open(newline="", encoding="utf-8") as stream:
        rows = list(csv.DictReader(stream))
    if not rows:
        raise ValueError("empty pipeline trace")

    cell_w, cell_h, left, top = 47, 48, 95, 92
    width = left + cell_w * len(rows) + 24
    height = top + cell_h * 5 + 78
    stages = [("IF", "if_pc", 0, "#c7d2fe"),
              ("ID", "id_pc", 1, "#a5f3fc"),
              ("EX", "ex_pc", 2, "#bbf7d0"),
              ("MEM", "mem_pc", 3, "#fde68a"),
              ("WB", "wb_pc", 4, "#fecaca")]
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" role="img" aria-label="Chronogramme du pipeline RISC-V">',
        '<rect width="100%" height="100%" fill="#0b1220"/>',
        '<style>text{font-family:Arial,sans-serif;fill:#e5e7eb} .small{font-size:11px} .label{font-size:16px;font-weight:bold} .title{font-size:21px;font-weight:bold}</style>',
        '<text x="24" y="32" class="title">Pipeline RV32I : charges, forwarding et cache</text>',
        '<text x="24" y="54" class="small">Chaque case indique le PC de l’instruction présente à cet étage au début du cycle.</text>',
    ]
    for index, row in enumerate(rows):
        x = left + index * cell_w
        if int(row["memory_stall"]):
            parts.append(f'<rect x="{x}" y="{top - 26}" width="{cell_w}" height="{cell_h * 5 + 30}" fill="#7f1d1d" opacity="0.38"/>')
        elif int(row["load_stall"]):
            parts.append(f'<rect x="{x}" y="{top - 26}" width="{cell_w}" height="{cell_h * 5 + 30}" fill="#854d0e" opacity="0.32"/>')
        parts.append(f'<text x="{x + cell_w / 2}" y="{top - 9}" text-anchor="middle" class="small">{escape(row["cycle"])}</text>')
    for stage_index, (name, column, valid_bit, color) in enumerate(stages):
        y = top + stage_index * cell_h
        parts.append(f'<text x="28" y="{y + 26}" class="label">{name}</text>')
        for index, row in enumerate(rows):
            x = left + index * cell_w + 2
            valid = bool(int(row["valid"]) & (1 << valid_bit))
            fill = color if valid else "#1e293b"
            parts.append(f'<rect x="{x}" y="{y}" width="{cell_w - 4}" height="{cell_h - 5}" rx="5" fill="{fill}"/>')
            if valid:
                pc = int(row[column])
                parts.append(f'<text x="{x + (cell_w - 4) / 2}" y="{y + 26}" text-anchor="middle" class="small" fill="#0b1220" style="fill:#0b1220">{pc:03x}</text>')
    legend_y = top + cell_h * 5 + 27
    parts.extend([
        f'<rect x="24" y="{legend_y - 11}" width="14" height="14" fill="#7f1d1d"/>',
        f'<text x="45" y="{legend_y}" class="small">défaut de cache, pipeline figé</text>',
        f'<rect x="265" y="{legend_y - 11}" width="14" height="14" fill="#854d0e"/>',
        f'<text x="286" y="{legend_y}" class="small">dépendance immédiate après LW</text>',
        f'<text x="24" y="{legend_y + 26}" class="small">Trace produite par la simulation cocotb ; temps en cycles d’horloge simulés.</text>',
        '</svg>',
    ])
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text("\n".join(parts) + "\n", encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=DEFAULT_CSV)
    parser.add_argument("--output", type=Path, default=DEFAULT_SVG)
    args = parser.parse_args()
    render(args.input, args.output)
    print(args.output)
