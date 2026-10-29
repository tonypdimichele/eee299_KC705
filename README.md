# EEE299 KC705: I/Q Streaming and Phase Measurement Platform

FPGA design and host tooling for a Xilinx KC705 (Kintex-7 `xc7k325tffg900-2`) that:

- generates an I/Q baseband tone (DDS) on an AD9781 dual 14-bit DAC to drive a Sivers EVK06002 mmWave kit,
- digitizes the returned I/Q signal with an AD9627 dual 12-bit ADC (125 MSPS),
- measures amplitude, frequency, and I/Q phase in hardware (zero-crossing and Costas-style correlation),
- streams the measurements to a Raspberry Pi or PC over UDP, and exposes control registers over the same link.

The platform is used for power/beam alignment, path-loss measurement, and through-wall motion experiments (drywall/plywood walk tests).

The Ethernet/UDP stack is based on Alex Forencich's [verilog-ethernet](https://github.com/alexforencich/verilog-ethernet) KC705 example. The ADC/DAC/clock-chip SPI configuration modules are adapted from ALINX reference designs.

---

## System overview

```
                         KC705
  ┌────────────────────────────────────────────────────────────────────────┐
  │                                                                        │
  │  RGMII PHY ─ ethernet_subsystem ──┬── UDP/1234  echo                   │
  │   (1 GbE)    (MAC/IP/UDP/ARP)     ├── UDP/10000 udp_axi_lite_bridge ─► axi_lite_regs ──► control
  │                                   ├── UDP/20000 ingress ─► ping_pong_buffer_tx ─► iq_codec_loop
  │                                   └── UDP/30000 egress  ◄─ ping_pong_buffer_rx ◄─ afifo ◄─ adc_stats
  │                                                                        │          ▲
  │  iq_codec_loop (tone DDS) ─► dac_iobuf ─► AD9781 DAC ─► TX (I/Q)        │          │
  │  dac_config ─SPI─► AD9518 clock chip + AD9781                          │          │
  │                                                                        │          │
  │  RX (I/Q) ─► AD9627 ADC ─► adc_top (LVDS/IDDR) ─► adc_stats ───────────┼──────────┘
  │                                                    └─ phase_costas     │
  └────────────────────────────────────────────────────────────────────────┘
```

- **TX:** with tone mode enabled (the reset default), a DDS in the DAC clock domain writes cosine to DAC1 high and sine to DAC1 low. The tone frequency is set by the PINC register. DAC2 is held at midscale.
- **RX:** `adc_stats` turns ADC1 channels A (I) and B (Q) into 19-byte measurement records. An async FIFO moves them into the 125 MHz domain, and they are sent out in 512-byte UDP payloads on port 30000.
- **Egress destination:** the FPGA sends port-30000 traffic to the IP/port of the most recent packet received on port 20000. Host tools "prime" the stream by sending one packet to UDP/20000 from their listening port.

---

## Repository layout

| Path | Contents |
|------|----------|
| `rtl/` | Project RTL (top level, Ethernet integration, DAC/ADC paths, DSP) |
| `lib/` | verilog-ethernet library (MAC, IP/UDP/ARP, AXI-Stream FIFOs, sync) |
| `ip/dds_compiler_0/` | Vivado IP: `dds_compiler_0`, `cordic_0` (in build), `fir_compiler_0` + RRC `.coe` (not in build) |
| `xdc/` | Pin/timing constraints and per-module timing Tcl |
| `fpga/` | Makefile and Vivado Tcl build scripts; `rev/` holds archived bitstreams and `.ltx` debug probes |
| `sim/` | SystemVerilog testbenches |
| `python/` | Host tools for register access, streaming, and live analysis |
| `python/analysis_scripts/` | Offline analysis of walk-test captures (crossing detection, material comparison, report generation) |
| `doc/` | Subsystem write-ups (PDF) and the Python scripts that generate them |

---

## Network interface

| Setting | Value |
|---------|-------|
| FPGA IP | `192.168.1.128` |
| Gateway / mask | `192.168.1.1` / `255.255.255.0` |
| MAC | `02:00:00:00:00:00` |

| UDP port | Direction | Purpose |
|----------|-----------|---------|
| 1234 | in/out | Echo (stock verilog-ethernet behavior) |
| 10000 | in/out | Register bridge: one AXI-Lite read/write per packet |
| 20000 | host → FPGA | Stream ingress. Feeds the TX ping-pong buffer and sets the egress destination |
| 30000 | FPGA → host | Stream egress: 512-byte payloads of ADC stats records |

Packets to any other port are accepted and dropped so the RX pipeline never stalls.

### Register bridge protocol (UDP/10000)

| Packet | Format |
|--------|--------|
| Read request | `[0x00][ADDR(4)]` (at least 5 bytes) |
| Write request | `[0x01][ADDR(4)][DATA(4)]` (at least 9 bytes) |
| Response | `[STATUS(1)][ADDR(4)][DATA(4)]`, `STATUS` 0x00 = OK, 0x01 = error |

All fields are big-endian. The response goes back to the requester's source IP and port.

---

## Register map (`axi_lite_regs`)

Word select is `addr[5:2]`. Unmapped reads return `0xDEADBEEF`. All writable registers support `WSTRB` byte enables.

| Addr | Name | Access | Reset | Fields |
|------|------|--------|-------|--------|
| `0x00` | STREAM_CTRL | R/W | `0x00000001` | `[0]` ADC stats stream enable |
| `0x04` | REG1 | R/W | `0x00000000` | Scratch |
| `0x08` | COUNTER | RO | — | Free-running 125 MHz counter |
| `0x0C` | LED | R/W | `0x00000000` | `[5:0]` drive LEDs (OR-ed with debug indicators, see below) |
| `0x10` | DAC_CTRL | R/W | `0x00012121` | `[0]` tone mode, `[8:4]` DAC1 DCI delay, `[16:12]` DAC2 DCI delay, `[28]` apply toggle (flip to push delays over SPI) |
| `0x14` | TONE_PINC | R/W | `0x000013AF` | DDS phase increment for the TX tone |
| `0x18` | DAC_SPI_READ | R/W | `0x00000000` | Write: `[7:0]` AD9781 reg addr, `[16]` request toggle. Read: `[7:0]` addr, `[15:8]` data, `[16]` req toggle, `[17]` busy, `[18]` done toggle |

Control signals cross from the 125 MHz register domain to the SPI domain through `sync_signal`. Edge-triggered commands (delay apply, SPI read) are toggles, so you fire one by inverting the bit, not by writing a 1.

**LEDs:** `LED[7]` pulses when a port-10000 header is accepted, `LED[6]` pulses when the bridge wins a TX header, and `LED[5:0]` follow `0x0C`. Everything is OR-ed with the first byte of each outgoing UDP payload, so LEDs flicker while streaming.

---

## RTL modules

### Top level and clocking

| Module | Description |
|--------|-------------|
| `KC705_EEE299_top.v` | Board top. Generates the 125 MHz system clock from the 200 MHz board clock (MMCM). Also handles reset sync, button/switch debounce, fixed RGMII RX IDELAYs, all subsystem instances, the ADC→Ethernet CDC FIFO and 512-byte framing, and a ~0.6 MHz square wave on `USER_SMA_GPIO_P` (ADC clock ÷ 200) for scope triggering. DAC SPI configuration waits a fixed delay after MMCM lock |
| `sync_signal.v`, `debounce_switch.v` | Multi-bit synchronizer and switch debouncer (verilog-ethernet) |

**Clock domains**

| Domain | Frequency | Source | Used by |
|--------|-----------|--------|---------|
| System | 125 MHz | KC705 MMCM | Ethernet stack, register bank, ping-pong buffers |
| DAC | 166.67 MHz | AD9518 → AD9781 DCO | Tone DDS and DAC output in `iq_codec_loop`, `dac_iobuf` |
| ADC | 125 MHz | AD9627 data clock | `adc_top` capture, `adc_stats`, `phase_costas`, FIFO write side |

### Ethernet and control

| Module | Description |
|--------|-------------|
| `ethernet_subsystem.v` | RGMII MAC + FIFO, Ethernet/IP/UDP/ARP stack, and UDP demux by destination port (table above). A per-packet category latch keeps payload routing stable after the header handshake. It also latches the port-20000 sender as the port-30000 destination and drives the LED logic |
| `udp_axi_lite_bridge.v` | UDP packet → single AXI-Lite transaction → 9-byte UDP response. FSM: `IDLE → DO_AR/WAIT_R` or `DO_AW/WAIT_B → BUILD → SEND`. AW and W are asserted together |
| `axi_lite_regs.v` | AXI-Lite slave register bank (map above) |

### TX / DAC path

| Module | Description |
|--------|-------------|
| `ping_pong_buffer.sv` | Two-bank, packet-granular AXI-Stream buffer (2048 B per bank). Writes one packet while the other drains. One instance on TX ingress, one on RX egress |
| `iq_codec_loop.sv` | TX baseband. In tone mode, `dds_compiler_0` (clocked from the DAC DCO) drives DAC1 H/L with cos/sin at `TONE_PINC`. Otherwise the DACs park at midscale. Tone mode and PINC are double-flopped into the DAC domain, and PINC only updates after two consecutive samples agree. It also contains a byte-symbol mapper (XOR scramble, 2 bits/symbol) feeding `fl9781_tx_wrapper` for digital-modulation experiments |
| `fl9781_tx_wrapper.sv` | Maps I/Q symbol bits to ±amplitude 14-bit samples for the DAC |
| `dac_iobuf.v` | LVDS output buffers and ODDR for both AD9781 DACs. Buffers the DAC DCO clocks |
| `dac_config.v` | SPI sequencer for the AD9518 clock generator and AD9781 DACs. Applies DCI delays at boot and on request, and supports single-register readback |
| `spi_config.v`, `spi_config_ctrl.v`, `spi_cmd.v`, `spi_master.v` | SPI engine used by `dac_config` |
| `ad9518_lut_config.v`, `ad9781_lut_config.v` | Register init tables for the clock chip and the DACs |

### RX / ADC path and measurement

| Module | Description |
|--------|-------------|
| `adc_top.v` | AD9627 interface: reference clocks, SPI config, LVDS/IDDR capture. Outputs ADC1 channel A/B samples in the ADC clock domain |
| `adc_spi.v`, `adc_spi_master.v`, `adc_spi_config.v`, `adc_lut_config.v` | ADC SPI engine and register init table |
| `adc_stats.sv` | Per-measurement statistics on I (ch A) and Q (ch B). Windows are aligned to positive-going I zero crossings, with N adapted by powers of 2 to keep the window between 8k and 50k clocks. Produces I and Q peak±, total clocks over N, summed I→Q zero-crossing delay, and Costas correlation X/Y. Emits one 19-byte record per window (format below) |
| `phase_costas.sv` | Correlation phase estimator. A 15-tap Type-III Hilbert FIR builds analytic I and Q. The module accumulates X = Σ(I·Q + H(I)·H(Q)) and Y = Σ(H(I)·Q − I·H(Q)), normalizes them to 12-bit, and the host computes `atan2(Y, X)`. Seven-stage pipeline, meets timing at 125 MHz |
| `afifo_wrapper.sv` | `xpm_fifo_async` wrapper (2048 deep) for the ADC clock → 125 MHz crossing |

### ADC stats record (19 bytes)

| Bytes | Field |
|-------|-------|
| `[0]` | Sync `0xA7` |
| `[1:3]` | I peak+ / peak− (two packed 12-bit values) |
| `[4:7]` | `iq_delay_sum`: clocks from I ZC to Q ZC, summed over N (u32) |
| `[8:9]` | `total_clk_count` over N crossings (u16) |
| `[10:11]` | `n_cycles` N (u16) |
| `[12:13]` | Correlation Y (s16) |
| `[14:15]` | Correlation X (s16) |
| `[16:18]` | Q peak+ / peak− (two packed 12-bit values) |

Host-side decode: `freq = fs · N / total_clks`, `phase_zc = 360 · delay_sum / total_clks`, `phase_corr = atan2(Y, X)`. Records are streamed back-to-back with no regard for UDP payload boundaries, so the receiver resyncs on `0xA7`.

### Present in `rtl/` but not in the build

| Module | Status |
|--------|--------|
| `qpsk_tx_modulator.sv` | Framed QPSK modulator (start/stop sequences, optional RRC shaping). Instantiation in `iq_codec_loop` is commented out. Has a testbench |
| `fir_filter_wrapper.sv` | I/Q RRC filter around `fir_compiler_0` |
| `iq_something.sv` | Older copy/variant of `iq_codec_loop` |

---

## Building

Requires Vivado. Run everything from `fpga/`.

**Makefile flow** (verilog-ethernet style, from `fpga/`):

```sh
make            # synth + impl + bitstream
make program    # program over JTAG
```

**Tcl flow** (from `fpga/`):

```sh
vivado -mode batch -source create_project.tcl   # create KC705_EEE299_top.xpr and import IP
vivado -mode batch -source run_synth.tcl
vivado -mode batch -source run_impl.tcl         # also writes utilization reports
vivado -mode batch -source generate_bit.tcl     # .bit, .bin and .ltx in runs/impl_1/
```

When adding an RTL file, update both `fpga/Makefile` (`SYN_FILES`) and `fpga/create_project.tcl`.

**Flash:** the correct configuration flash for the `.bin` is the Micron **MT25QL128ABA8ESF-0SIT** (128 Mbit / 16 MB Quad-SPI).

---

## Host tools (`python/`)

Defaults for all tools are FPGA `192.168.1.128` and local bind port 40000. Only one process can own the UDP stream at a time.

| Script | Purpose |
|--------|---------|
| `regs.py` | Register read/write over UDP/10000. Supports `--addr/--write/--read`, `--stream-on/--stream-off`, `--dac-read-addr` (AD9781 SPI readback through `0x18`), and `--demo` |
| `adc_stats_analyzer.py` | Real-time curses analyzer for the stats stream. Decodes records and shows I/Q Vrms, frequency, ZC phase, and correlation phase (EMA smoothing, jump rejection/relock, optional π-ambiguity resolution). Optional CSV recording (`--csv-output`) and block-vs-sliding RMS comparison (`--rms-csv`) |
| `adc_stats_gui.py` | Tkinter strip-chart GUI (I and Q V²rms with min/max envelope). Reuses `ADCStatsAnalyzer` and accepts the same CSV option. Run it instead of the analyzer, not alongside it |
| `beamform_analyzer.py` | Raw-sample analyzer: FFT/SNR, waveform, phase tracking, RMS, frequency error. Supports `--iq-interleaved` |
| `adc_stream_to_csv.py` | Capture a raw ADC sample stream to CSV (12-bit offset-binary → volts) |
| `rpi_eth_io.py` | Always-on single-socket UDP I/O. Listens continuously and takes send commands from stdin |
| `data_loop.py` | Send a hex file to UDP/20000 and verify the bytes returned on 30000 (loopback integrity test) |
| `dac_pattern_sender.py` | Continuously send a repeating byte pattern to UDP/20000 for DAC scope tests |
| `dds_pinc.py` | Compute the `TONE_PINC` value for a target frequency and print the matching register write |
| `mag_H.py` | Magnitude response of the `phase_costas` Hilbert FIR at test frequencies |

Typical session:

```sh
python3 python/regs.py --demo                                  # link check: write/read 0x0C, read counter
python3 python/dds_pinc.py 10                                  # get PINC for a 10 MHz tone
python3 python/regs.py --addr 0x14 --write 0x<pinc>            # set tone frequency
python3 python/adc_stats_gui.py --csv-output run1.csv          # live view + record
python3 python/adc_stats_analyzer.py --duration-sec 30 --csv-output run1.csv
```

---

## Simulation (`sim/`)

| Testbench | Covers |
|-----------|--------|
| `tb_adc_stats.sv` | `adc_stats` with fixed N. Add `+define+TB_USE_XILINX_CORDIC` to use the real CORDIC model |
| `tb_iq_codec_tone.sv` | `iq_codec_loop` tone mode (uses `dds_compiler_0_stub.sv`) |
| `tb_qpsk_tx_modulator.sv` | QPSK modulator symbol and framing checks |
| `ping_pong_simulation.sv` | TX → RX ping-pong buffer chain |
| `ping_pong_iq_top_simulation.sv` | Ping-pong → `iq_codec_loop` → ping-pong |
| `afifo_tb.sv` | Async FIFO burst test |

---

## Documentation (`doc/`)

| PDF | Topic |
|-----|-------|
| `adc_stats_subsystem.pdf` | `adc_stats` measurement design and packet format |
| `costas_phase_estimator.pdf` | Hilbert/correlation phase estimator |
| `dac_subsystem.pdf` | DAC, clock chip, and SPI configuration |
| `rms_block_vs_sliding.pdf` | Block vs sliding-window RMS comparison |

Each PDF is generated by the matching `doc/generate_*.py` script.

---

## Troubleshooting

- **Register requests time out:** confirm the host is on `192.168.1.x`, that `ping 192.168.1.128` works, and that the programmed bitstream matches this source. LED7 lights when the FPGA accepts a port-10000 header.
- **No stats stream:** check `0x00[0]` with `regs.py --stream-on`. Make sure the receiver sent a prime packet to UDP/20000 from the port it listens on (the analyzers do this unless `--no-prime` is set), and that no other process holds port 40000.
- **Stream stalls or drops records:** the CDC FIFO applies backpressure to `adc_stats`, and records are dropped while the stream is disabled. Resync on `0xA7` is expected at startup.
- **No DAC output:** DAC SPI configuration waits after MMCM lock, so allow a few seconds after programming. Check that tone mode (`0x10[0]`) is set and that `TONE_PINC` is non-zero. Use `regs.py --dac-read-addr` to read back AD9781 registers.
- **DAC glitching:** tune the DCI delays in `0x10[8:4]` / `0x10[16:12]`, then flip `0x10[28]` to apply them.
- **LEDs look wrong:** they are OR-ed with debug pulses and outgoing payload bytes (see the register map).
