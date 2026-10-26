"""Generate the known example's hex image using the independent encoder."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from verification.model import addi, bne, lw, r_type, sw  # noqa: E402


def main() -> None:
    program = [
        addi(1, 0, 1), addi(2, 0, 11), addi(3, 0, 0),
        r_type(0, 1, 3, 0, 3), addi(1, 1, 1), bne(1, 2, -8),
        sw(3, 0, 0), lw(4, 0, 0),
    ]
    output = ROOT / "examples" / "sum_1_to_10.hex"
    output.write_text("".join(f"{word:08x}\n" for word in program), encoding="ascii")
    print(output)


if __name__ == "__main__":
    main()
