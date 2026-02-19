
# FPGA settings
FPGA_PART = xc7k325tffg900-2
FPGA_TOP = fpga
FPGA_ARCH = kintex7

# Files for synthesis
SYN_FILES = rtl/fpga.v
SYN_FILES += rtl/fpga_core.v
SYN_FILES += rtl/debounce_switch.v
SYN_FILES += rtl/sync_signal.v
SYN_FILES += rtl/udp_axi_lite_bridge.v
SYN_FILES += rtl/axi_lite_regs.v
SYN_FILES += lib/iddr.v
SYN_FILES += lib/oddr.v
SYN_FILES += lib/ssio_ddr_in.v
SYN_FILES += lib/rgmii_phy_if.v
SYN_FILES += lib/eth_mac_1g_rgmii_fifo.v
SYN_FILES += lib/eth_mac_1g_rgmii.v
SYN_FILES += lib/eth_mac_1g.v
SYN_FILES += lib/axis_gmii_rx.v
SYN_FILES += lib/axis_gmii_tx.v
SYN_FILES += lib/lfsr.v
SYN_FILES += lib/eth_axis_rx.v
SYN_FILES += lib/eth_axis_tx.v
SYN_FILES += lib/udp_complete.v
SYN_FILES += lib/udp_checksum_gen.v
SYN_FILES += lib/udp.v
SYN_FILES += lib/udp_ip_rx.v
SYN_FILES += lib/udp_ip_tx.v
SYN_FILES += lib/ip_complete.v
SYN_FILES += lib/ip.v
SYN_FILES += lib/ip_eth_rx.v
SYN_FILES += lib/ip_eth_tx.v
SYN_FILES += lib/ip_arb_mux.v
SYN_FILES += lib/arp.v
SYN_FILES += lib/arp_cache.v
SYN_FILES += lib/arp_eth_rx.v
SYN_FILES += lib/arp_eth_tx.v
SYN_FILES += lib/eth_arb_mux.v
SYN_FILES += lib/arbiter.v
SYN_FILES += lib/priority_encoder.v
SYN_FILES += lib/axis_fifo.v
SYN_FILES += lib/axis_async_fifo.v
SYN_FILES += lib/axis_async_fifo_adapter.v
SYN_FILES += lib/sync_reset.v


# XDC files
XDC_FILES = xdc/fpga.xdc
XDC_FILES += xdc/eth.xdc
XDC_FILES += xdc/rgmii_phy_if.tcl
XDC_FILES += xdc/eth_mac_1g_rgmii.tcl
XDC_FILES += xdc/eth_mac_fifo.tcl
XDC_FILES += xdc/axis_async_fifo.tcl
XDC_FILES += xdc/sync_reset.tcl

include ../common/vivado.mk

program: $(FPGA_TOP).bit
	echo "open_hw" > program.tcl
	echo "connect_hw_server" >> program.tcl
	echo "open_hw_target" >> program.tcl
	echo "current_hw_device [lindex [get_hw_devices] 0]" >> program.tcl
	echo "refresh_hw_device -update_hw_probes false [current_hw_device]" >> program.tcl
	echo "set_property PROGRAM.FILE {$(FPGA_TOP).bit} [current_hw_device]" >> program.tcl
	echo "program_hw_devices [current_hw_device]" >> program.tcl
	echo "exit" >> program.tcl
	vivado -nojournal -nolog -mode batch -source program.tcl

