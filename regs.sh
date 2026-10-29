# Shell helpers for KC705 register access over the UDP/10000 AXI-Lite bridge.
#
# Source this file (don't execute it), e.g. from ~/.bashrc:
#     source /path/to/eee299_KC705/python/regs.sh
#
#   rr <addr>          read a register      e.g. rr 0x10
#   wr <addr> <data>   write a register     e.g. wr 0x14 0x000007AE
#
# Set FPGA_IP to talk to a board other than the default 192.168.1.128.

_REGS_PY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/regs.py"

# Use whichever Python actually runs: python3 on Linux/RPi, python on Windows
# (where python3 may be the Microsoft Store placeholder).
if python3 -c '' >/dev/null 2>&1; then
    _REGS_PYTHON=python3
else
    _REGS_PYTHON=python
fi

rr() {
    if [ $# -ne 1 ]; then
        echo "usage: rr <addr>" >&2
        return 1
    fi
    "$_REGS_PYTHON" "$_REGS_PY" --ip "${FPGA_IP:-192.168.1.128}" --addr "$1" --read
}

wr() {
    if [ $# -ne 2 ]; then
        echo "usage: wr <addr> <data>" >&2
        return 1
    fi
    "$_REGS_PYTHON" "$_REGS_PY" --ip "${FPGA_IP:-192.168.1.128}" --addr "$1" --write "$2"
}
