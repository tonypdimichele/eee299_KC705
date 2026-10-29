"""Compute DDS phase increment register value for a target frequency.

Usage: python dds_pinc.py <freq_MHz> [clk_MHz]
"""
import sys

DIVISOR = 2**15
DEFAULT_CLK_MHZ = 166.667

if len(sys.argv) < 2:
    sys.exit(__doc__)

f_out = float(sys.argv[1])
f_clk = float(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_CLK_MHZ

pinc = round(f_out * DIVISOR / f_clk)
actual = f_clk * pinc / DIVISOR

print(f"target : {f_out} MHz (clk {f_clk} MHz)")
print(f"pinc   : {pinc} (0x{pinc:08X})")
print(f"actual : {actual:.6f} MHz")
print(f"wr 0x14 0x{pinc:08X}")
