# XDC constraints for the Xilinx KC705 board
# part: xc7k325tffg900-2

# General configuration
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 2.5 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.OVERTEMPSHUTDOWN Enable  [current_design]

# System clocks
# 200 MHz
set_property -dict {LOC AD12 IOSTANDARD LVDS} [get_ports CLK_200MHZ_P]
set_property -dict {LOC AD11 IOSTANDARD LVDS} [get_ports CLK_200MHZ_N]
create_clock -period 5.000 -name clk_200mhz [get_ports CLK_200MHZ_P]

# LEDs
set_property -dict {LOC AB8 IOSTANDARD LVCMOS15 SLEW SLOW DRIVE 12} [get_ports {LED[0]}]
set_property -dict {LOC AA8 IOSTANDARD LVCMOS15 SLEW SLOW DRIVE 12} [get_ports {LED[1]}]
set_property -dict {LOC AC9 IOSTANDARD LVCMOS15 SLEW SLOW DRIVE 12} [get_ports {LED[2]}]
set_property -dict {LOC AB9 IOSTANDARD LVCMOS15 SLEW SLOW DRIVE 12} [get_ports {LED[3]}]
set_property -dict {LOC AE26 IOSTANDARD LVCMOS25 SLEW SLOW DRIVE 12} [get_ports {LED[4]}]
set_property -dict {LOC G19 IOSTANDARD LVCMOS25 SLEW SLOW DRIVE 12} [get_ports {LED[5]}]
set_property -dict {LOC E18 IOSTANDARD LVCMOS25 SLEW SLOW DRIVE 12} [get_ports {LED[6]}]
set_property -dict {LOC F16 IOSTANDARD LVCMOS25 SLEW SLOW DRIVE 12} [get_ports {LED[7]}]

set_false_path -to [get_ports {LED[*]}]
set_output_delay 0.000 [get_ports {LED[*]}]

# Reset button
set_property -dict {LOC AB7 IOSTANDARD LVCMOS15} [get_ports RESET]

set_false_path -from [get_ports RESET]
set_input_delay 0.000 [get_ports RESET]

# Push buttons
set_property -dict {LOC AA12 IOSTANDARD LVCMOS15} [get_ports BTNU]
set_property -dict {LOC AC6 IOSTANDARD LVCMOS15} [get_ports BTNL]
set_property -dict {LOC AB12 IOSTANDARD LVCMOS15} [get_ports BTND]
set_property -dict {LOC AG5 IOSTANDARD LVCMOS15} [get_ports BTNR]
set_property -dict {LOC G12 IOSTANDARD LVCMOS25} [get_ports BTNC]

set_false_path -from [get_ports {BTNU BTNL BTND BTNR BTNC}]
set_input_delay 0.000 [get_ports {BTNU BTNL BTND BTNR BTNC}]

# Toggle switches
set_property -dict {LOC Y29 IOSTANDARD LVCMOS25} [get_ports {SW[0]}]
set_property -dict {LOC W29 IOSTANDARD LVCMOS25} [get_ports {SW[1]}]
set_property -dict {LOC AA28 IOSTANDARD LVCMOS25} [get_ports {SW[2]}]
set_property -dict {LOC Y28 IOSTANDARD LVCMOS25} [get_ports {SW[3]}]

set_false_path -from [get_ports {SW[*]}]
set_input_delay 0.000 [get_ports {SW[*]}]

# UART
set_property -dict {LOC K24 IOSTANDARD LVCMOS25 SLEW SLOW DRIVE 12} [get_ports UART_TXD]
set_property -dict {LOC M19 IOSTANDARD LVCMOS25} [get_ports UART_RXD]
set_property -dict {LOC L27 IOSTANDARD LVCMOS25 SLEW SLOW DRIVE 12} [get_ports UART_RTS]
set_property -dict {LOC K23 IOSTANDARD LVCMOS25} [get_ports UART_CTS]

set_false_path -to [get_ports {UART_TXD UART_RTS}]
set_output_delay 0.000 [get_ports {UART_TXD UART_RTS}]
set_false_path -from [get_ports {UART_RXD UART_CTS}]
set_input_delay 0.000 [get_ports {UART_RXD UART_CTS}]

# Gigabit Ethernet GMII PHY
set_property -dict {LOC U27 IOSTANDARD LVCMOS25} [get_ports PHY_RX_CLK]
set_property -dict {LOC U30 IOSTANDARD LVCMOS25} [get_ports {PHY_RXD[0]}]
set_property -dict {LOC U25 IOSTANDARD LVCMOS25} [get_ports {PHY_RXD[1]}]
set_property -dict {LOC T25 IOSTANDARD LVCMOS25} [get_ports {PHY_RXD[2]}]
set_property -dict {LOC U28 IOSTANDARD LVCMOS25} [get_ports {PHY_RXD[3]}]
#set_property -dict {LOC R19  IOSTANDARD LVCMOS25} [get_ports {PHY_RXD[4]}] ;# from U37.C4 RXD4
#set_property -dict {LOC T27  IOSTANDARD LVCMOS25} [get_ports {PHY_RXD[5]}] ;# from U37.A1 RXD5
#set_property -dict {LOC T26  IOSTANDARD LVCMOS25} [get_ports {PHY_RXD[6]}] ;# from U37.A2 RXD6
#set_property -dict {LOC T28  IOSTANDARD LVCMOS25} [get_ports {PHY_RXD[7]}] ;# from U37.C5 RXD7
set_property -dict {LOC R28 IOSTANDARD LVCMOS25} [get_ports PHY_RX_CTL]
#set_property -dict {LOC V26  IOSTANDARD LVCMOS25} [get_ports PHY_RX_ER] ;# from U37.D4 RXER
set_property -dict {LOC K30 IOSTANDARD LVCMOS25 SLEW FAST DRIVE 16} [get_ports PHY_TX_CLK]
#set_property -dict {LOC M28  IOSTANDARD LVCMOS25} [get_ports PHY_TX_CLK] ;# from U37.D1 TXCLK
set_property -dict {LOC N27 IOSTANDARD LVCMOS25 SLEW FAST DRIVE 16} [get_ports {PHY_TXD[0]}]
set_property -dict {LOC N25 IOSTANDARD LVCMOS25 SLEW FAST DRIVE 16} [get_ports {PHY_TXD[1]}]
set_property -dict {LOC M29 IOSTANDARD LVCMOS25 SLEW FAST DRIVE 16} [get_ports {PHY_TXD[2]}]
set_property -dict {LOC L28 IOSTANDARD LVCMOS25 SLEW FAST DRIVE 16} [get_ports {PHY_TXD[3]}]
#set_property -dict {LOC J26  IOSTANDARD LVCMOS25 SLEW FAST DRIVE 16} [get_ports {PHY_TXD[4]}] ;# from U37.H2 TXD4
#set_property -dict {LOC K26  IOSTANDARD LVCMOS25 SLEW FAST DRIVE 16} [get_ports {PHY_TXD[5]}] ;# from U37.H3 TXD5
#set_property -dict {LOC L30  IOSTANDARD LVCMOS25 SLEW FAST DRIVE 16} [get_ports {PHY_TXD[6]}] ;# from U37.J1 TXD6
#set_property -dict {LOC J28  IOSTANDARD LVCMOS25 SLEW FAST DRIVE 16} [get_ports {PHY_TXD[7]}] ;# from U37.J2 TXD7
set_property -dict {LOC M27 IOSTANDARD LVCMOS25 SLEW FAST DRIVE 16} [get_ports PHY_TX_CTL]
#set_property -dict {LOC N29  IOSTANDARD LVCMOS25 SLEW FAST DRIVE 16} [get_ports PHY_TX_ER] ;# from U37.F2 TXER
#set_property -dict {LOC A7   } [get_ports PHY_SGMII_RX_P] ;# MGTXRXP1_117 GTXE2_CHANNEL_X0Y9 / GTXE2_COMMON_X?Y? from U37.A7 SOUT_P
#set_property -dict {LOC A8   } [get_ports PHY_SGMII_RX_N] ;# MGTXRXN1_117 GTXE2_CHANNEL_X0Y9 / GTXE2_COMMON_X?Y? from U37.A8 SOUT_N
#set_property -dict {LOC A3   } [get_ports PHY_SGMII_TX_P] ;# MGTXTXP1_117 GTXE2_CHANNEL_X0Y9 / GTXE2_COMMON_X?Y? from U37.A3 SIN_P
#set_property -dict {LOC A4   } [get_ports PHY_SGMII_TX_N] ;# MGTXTXN1_117 GTXE2_CHANNEL_X0Y9 / GTXE2_COMMON_X?Y? from U37.A4 SIN_N
#set_property -dict {LOC G8   } [get_ports PHY_SGMII_CLK_P] ;# MGTREFCLK0P_117 from U2.7
#set_property -dict {LOC G7   } [get_ports PHY_SGMII_CLK_N] ;# MGTREFCLK0N_117 from U2.6
set_property -dict {LOC L20 IOSTANDARD LVCMOS25 SLEW SLOW DRIVE 12} [get_ports PHY_RESET_N]
set_property -dict {LOC N30 IOSTANDARD LVCMOS25} [get_ports PHY_INT_N]
#set_property -dict {LOC J21  IOSTANDARD LVCMOS25 SLEW SLOW DRIVE 12} [get_ports PHY_MDIO] ;# from U37.M1 MDIO
#set_property -dict {LOC R23  IOSTANDARD LVCMOS25 SLEW SLOW DRIVE 12} [get_ports PHY_MDC] ;# from U37.L3 MDC

#create_clock -period 40.000 -name phy_tx_clk [get_ports PHY_TX_CLK]
create_clock -period 8.000 -name phy_rx_clk [get_ports PHY_RX_CLK]
#create_clock -period 8.000 -name phy_sgmii_clk [get_ports PHY_SGMII_CLK_P]

set_false_path -to [get_ports PHY_RESET_N]
set_output_delay 0.000 [get_ports PHY_RESET_N]
set_false_path -from [get_ports PHY_INT_N]
set_input_delay 0.000 [get_ports PHY_INT_N]

#set_false_path -to [get_ports {PHY_MDIO PHY_MDC}]
#set_output_delay 0 [get_ports {PHY_MDIO PHY_MDC}]
#set_false_path -from [get_ports {PHY_MDIO}]
#set_input_delay 0 [get_ports {PHY_MDIO}]


#Start of EEE299 project constraints

#FMC DAC
#I
set_property PACKAGE_PIN AC22 [get_ports FMC_LPC_LA16_P]
set_property IOSTANDARD LVCMOS25 [get_ports FMC_LPC_LA16_P]
set_property PACKAGE_PIN AD22 [get_ports FMC_LPC_LA16_N]
set_property IOSTANDARD LVCMOS25 [get_ports FMC_LPC_LA16_N]

#Q
set_property PACKAGE_PIN AD21 [get_ports FMC_LPC_LA14_P]
set_property IOSTANDARD LVCMOS25 [get_ports FMC_LPC_LA14_P]
set_property PACKAGE_PIN AE21 [get_ports FMC_LPC_LA14_N]
set_property IOSTANDARD LVCMOS25 [get_ports FMC_LPC_LA14_N]

