# EEE299 KC705 Design Documentation (branch1)

 Correct flash part to store .bin is Micron MT25QL128ABA8ESF-0SIT (128 Mbit = 16 MB Quad-SPI Flash)

This file documents the key modules and host utility in this branch:
- `eee299_KC705/rtl/KC705_EEE299_top.v`
- `eee299_KC705/rtl/fpga_core.v`
- `eee299_KC705/rtl/udp_axi_lite_bridge.v`
- `eee299_KC705/rtl/axi_lite_regs.v`
- `eee299_KC705/regs.py`

---

## 1) `KC705_EEE299_top.v` (Board Top Wrapper)

### Purpose
Board-level integration for the KC705 platform.

### What it does
- Accepts differential 200 MHz board clock (`CLK_200MHZ_P/N`).
- Generates internal clocks with MMCM:
  - `clk_int` = 125 MHz
  - `clk90_int` = 125 MHz, 90° phase
  - `clk_200mhz_int` = 200 MHz for IDELAY controller
- Synchronizes reset (`rst_int`) from MMCM lock.
- Debounces/synchronizes GPIO and UART inputs.
- Applies fixed IDELAY to RGMII RX data/ctl.
- Instantiates `fpga_core`.
- Exposes FMC DAC output pins (`FMC_LPC_LA16_*`, `FMC_LPC_LA14_*`) for application use.

### Notes
- This module is mostly timing/IO plumbing.
- Network stack and app behavior are implemented in `fpga_core.v`.

---

## 2) `fpga_core.v` (Ethernet/UDP Core + App Routing)

### Purpose
Implements packet processing and application logic:
- RGMII MAC
- Ethernet/IP/UDP stack
- UDP echo path on port **1234**
- UDP AXI-Lite register bridge on port **10000**
- LED/debug behavior

### Data path overview
RX path:
`PHY -> eth_mac_1g_rgmii_fifo -> eth_axis_rx -> udp_complete -> rx_udp_*`

TX path:
`app mux (echo/app1) -> udp_complete -> eth_axis_tx -> MAC -> PHY`

### UDP application routing
- `match_echo`: destination port == 1234
- `match_regapp`: destination port == 10000
- Per-packet category latch (`cat_echo` / `cat_reg`) is set on UDP header handshake and cleared on payload `tlast` handshake.

### Important behaviors/fixes in this branch
1. **Header ready alignment**
   - Echo route header readiness is tied to echo TX arbitration readiness (`echo_tx_hdr_ready`).
2. **Per-packet TX source latch**
   - `tx_sel_app1` latches whether TX payload belongs to app1 or echo.
   - Prevents payload routing from depending on a one-cycle header valid pulse.
3. **Payload gating**
   - Payload `tvalid`/`tlast` are gated by selected route to avoid cross-route leakage.

### Register bridge integration
- Instantiates `udp_axi_lite_bridge` (`u_regbridge`) on UDP/10000.
- Connects bridge AXI master directly to `axi_lite_regs` (`u_regs`).

### LED mapping
Current LED assignment combines three sources:
- Debug pulse bits (`led_rx`, `led_tx`) on upper bits
- Register LED output (`regs_led[5:0]`)
- `led_reg` (first TX payload byte capture)

Effective assignment:
`led = ({led_rx, led_tx, 6'b0} | {2'b00, regs_led[5:0]} | led_reg)`

This means LEDs are OR-composed, not register-only.

---

## 3) `udp_axi_lite_bridge.v` (UDP Command to AXI-Lite Master)

### Purpose
Converts simple UDP packets into single AXI-Lite read/write transactions.

### UDP protocol
Request:
- Read:  `[0x00][ADDR(4)]`
- Write: `[0x01][ADDR(4)][DATA(4)]`

Response:
- `[STATUS(1)][ADDR(4)][DATA(4)]`
- `STATUS = 0x00` OK, `0x01` ERROR

### Port
- `BRIDGE_PORT` default = `10000`

### RX behavior
- Captures sender metadata (IP/ports) and payload bytes.
- Validates minimum length:
  - Read requires >= 5 bytes
  - Write requires >= 9 bytes

### AXI-Lite FSM behavior
States include:
- `ST_IDLE`, `ST_DO_AR`, `ST_WAIT_R`, `ST_DO_AW`, `ST_WAIT_B`, `ST_BUILD`, `ST_SEND`

Write path detail:
- `AWVALID` and `WVALID` are asserted together in `ST_DO_AW`.
- This matches slaves that expect concurrent AW/W acceptance.

### TX response behavior
- Responds to source IP/UDP source port from request.
- Sends 9-byte payload with status, address, and returned data.

---

## 4) `axi_lite_regs.v` (AXI-Lite Slave Register Bank)

### Purpose
Small AXI-Lite register block used by the UDP bridge.

### Register map
(Word address = `addr[5:2]`)
- `0x00` (`word 0`): `reg0` (R/W)
- `0x04` (`word 1`): `reg1` (R/W)
- `0x08` (`word 2`): `reg2_counter` (RO, free-running)
- `0x0C` (`word 3`): `reg3` (R/W)

Unknown reads return `32'hDEAD_BEEF`.

### Write semantics
- Requires AW and W handshake conditions aligned in the same transaction window.
- Byte write support via `WSTRB`.

### Output
- `reg3_out <= reg3[7:0]` each cycle (used for LED control path in `fpga_core`).

---

## 5) `regs.py` (Host UDP Register Utility)

### Purpose
Python tool to read/write registers through UDP bridge (port 10000).

### Defaults
- IP: `192.168.1.128`
- Port: `10000`
- Default address: `0x0C`

### Packet formats
- Write request: `struct.pack(">BII", 0x01, addr, data)`
- Read request: `struct.pack(">BI", 0x00, addr)`
- Response parse: first 9 bytes as `>BII`

### CLI options
- `--ip`, `--port`, `--timeout`
- `--addr`, `--write`, `--read`
- `--demo` (writes `0x5A` to `0x0C`, reads back `0x0C`, then reads `0x08`)

---

## End-to-end control flow
1. Host runs `regs.py` and sends UDP command to port 10000.
2. `fpga_core` demuxes packet to app1 (`udp_axi_lite_bridge`).
3. Bridge performs AXI-Lite transaction on `axi_lite_regs`.
4. Bridge emits UDP response packet.
5. `regs.py` decodes status/address/data.

---

## Bring-up checklist
1. Build and program FPGA bitstream from this branch.
2. Confirm Ethernet connectivity to target IP (`192.168.1.128`).
3. Verify UDP echo works on port 1234.
4. Run:
   - `python3 eee299_KC705/regs.py --demo`
5. Expect:
   - `status=0x00` for successful read/write
   - `0x0C` readback matches write (low byte)
   - `0x08` counter value changes between reads

---

## Troubleshooting quick notes
- If requests time out:
  - Ensure programmed bitstream is from this updated branch.
  - Verify host and FPGA are on reachable subnet.
  - Confirm destination UDP port is 10000.
- If register values return but LEDs are confusing:
  - LED outputs are OR-combined with debug/payload indicators in `fpga_core`.
  - For pure register-driven LEDs, simplify LED assignment to `regs_led` only.
