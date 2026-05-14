# Ethernet constraints

# IDELAY on RGMII from PHY chip
set_property IDELAY_VALUE 0 [get_cells {phy_rx_ctl_idelay phy_rxd_idelay_*}]








connect_debug_port u_ila_2/clk [get_nets [list ADC2_CLK_REF_OBUF]]


connect_debug_port u_ila_1/clk [get_nets [list adc2_clk]]
connect_debug_port u_ila_3/clk [get_nets [list adc1_clk_BUFG]]


connect_debug_port u_ila_1/probe3 [get_nets [list {adc_fifo_word_hold[0]} {adc_fifo_word_hold[1]} {adc_fifo_word_hold[2]} {adc_fifo_word_hold[3]} {adc_fifo_word_hold[4]} {adc_fifo_word_hold[5]} {adc_fifo_word_hold[6]} {adc_fifo_word_hold[7]} {adc_fifo_word_hold[8]} {adc_fifo_word_hold[9]} {adc_fifo_word_hold[10]} {adc_fifo_word_hold[11]} {adc_fifo_word_hold[12]} {adc_fifo_word_hold[13]} {adc_fifo_word_hold[14]} {adc_fifo_word_hold[15]}]]
connect_debug_port u_ila_1/probe9 [get_nets [list adc_fifo_word_low_byte]]
connect_debug_port u_ila_1/probe10 [get_nets [list adc_fifo_word_valid]]


create_debug_core u_ila_0 ila
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_0]
set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores u_ila_0]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_0]
set_property C_DATA_DEPTH 8192 [get_debug_cores u_ila_0]
set_property C_EN_STRG_QUAL false [get_debug_cores u_ila_0]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_0]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_0]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_0]
set_property port_width 1 [get_debug_ports u_ila_0/clk]
connect_debug_port u_ila_0/clk [get_nets [list adc_top_inst/adc1_clk]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe0]
set_property port_width 12 [get_debug_ports u_ila_0/probe0]
connect_debug_port u_ila_0/probe0 [get_nets [list {adc_top_inst/adc1_data_a_d0[0]} {adc_top_inst/adc1_data_a_d0[1]} {adc_top_inst/adc1_data_a_d0[2]} {adc_top_inst/adc1_data_a_d0[3]} {adc_top_inst/adc1_data_a_d0[4]} {adc_top_inst/adc1_data_a_d0[5]} {adc_top_inst/adc1_data_a_d0[6]} {adc_top_inst/adc1_data_a_d0[7]} {adc_top_inst/adc1_data_a_d0[8]} {adc_top_inst/adc1_data_a_d0[9]} {adc_top_inst/adc1_data_a_d0[10]} {adc_top_inst/adc1_data_a_d0[11]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe1]
set_property port_width 12 [get_debug_ports u_ila_0/probe1]
connect_debug_port u_ila_0/probe1 [get_nets [list {adc_top_inst/adc1_data_b_d0[0]} {adc_top_inst/adc1_data_b_d0[1]} {adc_top_inst/adc1_data_b_d0[2]} {adc_top_inst/adc1_data_b_d0[3]} {adc_top_inst/adc1_data_b_d0[4]} {adc_top_inst/adc1_data_b_d0[5]} {adc_top_inst/adc1_data_b_d0[6]} {adc_top_inst/adc1_data_b_d0[7]} {adc_top_inst/adc1_data_b_d0[8]} {adc_top_inst/adc1_data_b_d0[9]} {adc_top_inst/adc1_data_b_d0[10]} {adc_top_inst/adc1_data_b_d0[11]}]]
create_debug_core u_ila_1 ila
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_1]
set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores u_ila_1]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_1]
set_property C_DATA_DEPTH 8192 [get_debug_cores u_ila_1]
set_property C_EN_STRG_QUAL false [get_debug_cores u_ila_1]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_1]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_1]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_1]
set_property port_width 1 [get_debug_ports u_ila_1/clk]
connect_debug_port u_ila_1/clk [get_nets [list adc_top_inst/adc2_clk_BUFG]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_1/probe0]
set_property port_width 12 [get_debug_ports u_ila_1/probe0]
connect_debug_port u_ila_1/probe0 [get_nets [list {adc_top_inst/adc2_data_a_d0[0]} {adc_top_inst/adc2_data_a_d0[1]} {adc_top_inst/adc2_data_a_d0[2]} {adc_top_inst/adc2_data_a_d0[3]} {adc_top_inst/adc2_data_a_d0[4]} {adc_top_inst/adc2_data_a_d0[5]} {adc_top_inst/adc2_data_a_d0[6]} {adc_top_inst/adc2_data_a_d0[7]} {adc_top_inst/adc2_data_a_d0[8]} {adc_top_inst/adc2_data_a_d0[9]} {adc_top_inst/adc2_data_a_d0[10]} {adc_top_inst/adc2_data_a_d0[11]}]]
create_debug_port u_ila_1 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_1/probe1]
set_property port_width 12 [get_debug_ports u_ila_1/probe1]
connect_debug_port u_ila_1/probe1 [get_nets [list {adc_top_inst/adc2_data_b_d0[0]} {adc_top_inst/adc2_data_b_d0[1]} {adc_top_inst/adc2_data_b_d0[2]} {adc_top_inst/adc2_data_b_d0[3]} {adc_top_inst/adc2_data_b_d0[4]} {adc_top_inst/adc2_data_b_d0[5]} {adc_top_inst/adc2_data_b_d0[6]} {adc_top_inst/adc2_data_b_d0[7]} {adc_top_inst/adc2_data_b_d0[8]} {adc_top_inst/adc2_data_b_d0[9]} {adc_top_inst/adc2_data_b_d0[10]} {adc_top_inst/adc2_data_b_d0[11]}]]
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets adc1_clk]
