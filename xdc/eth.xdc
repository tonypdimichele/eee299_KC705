# Ethernet constraints

# IDELAY on RGMII from PHY chip
set_property IDELAY_VALUE 0 [get_cells {phy_rx_ctl_idelay phy_rxd_idelay_*}]








connect_debug_port u_ila_2/clk [get_nets [list ADC2_CLK_REF_OBUF]]


connect_debug_port u_ila_1/clk [get_nets [list adc2_clk]]
connect_debug_port u_ila_3/clk [get_nets [list adc1_clk_BUFG]]

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
connect_debug_port u_ila_0/probe0 [get_nets [list {adc_top_inst/adc1_data_b_d0[0]} {adc_top_inst/adc1_data_b_d0[1]} {adc_top_inst/adc1_data_b_d0[2]} {adc_top_inst/adc1_data_b_d0[3]} {adc_top_inst/adc1_data_b_d0[4]} {adc_top_inst/adc1_data_b_d0[5]} {adc_top_inst/adc1_data_b_d0[6]} {adc_top_inst/adc1_data_b_d0[7]} {adc_top_inst/adc1_data_b_d0[8]} {adc_top_inst/adc1_data_b_d0[9]} {adc_top_inst/adc1_data_b_d0[10]} {adc_top_inst/adc1_data_b_d0[11]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe1]
set_property port_width 12 [get_debug_ports u_ila_0/probe1]
connect_debug_port u_ila_0/probe1 [get_nets [list {adc_top_inst/adc1_data_a_d0[0]} {adc_top_inst/adc1_data_a_d0[1]} {adc_top_inst/adc1_data_a_d0[2]} {adc_top_inst/adc1_data_a_d0[3]} {adc_top_inst/adc1_data_a_d0[4]} {adc_top_inst/adc1_data_a_d0[5]} {adc_top_inst/adc1_data_a_d0[6]} {adc_top_inst/adc1_data_a_d0[7]} {adc_top_inst/adc1_data_a_d0[8]} {adc_top_inst/adc1_data_a_d0[9]} {adc_top_inst/adc1_data_a_d0[10]} {adc_top_inst/adc1_data_a_d0[11]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe2]
set_property port_width 8 [get_debug_ports u_ila_0/probe2]
connect_debug_port u_ila_0/probe2 [get_nets [list {adc_to_eth_afifo_inst/i_w_data[0]} {adc_to_eth_afifo_inst/i_w_data[1]} {adc_to_eth_afifo_inst/i_w_data[2]} {adc_to_eth_afifo_inst/i_w_data[3]} {adc_to_eth_afifo_inst/i_w_data[4]} {adc_to_eth_afifo_inst/i_w_data[5]} {adc_to_eth_afifo_inst/i_w_data[6]} {adc_to_eth_afifo_inst/i_w_data[7]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe3]
set_property port_width 1 [get_debug_ports u_ila_0/probe3]
connect_debug_port u_ila_0/probe3 [get_nets [list adc_fifo_w_valid]]
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
create_debug_core u_ila_2 ila
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_2]
set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores u_ila_2]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_2]
set_property C_DATA_DEPTH 8192 [get_debug_cores u_ila_2]
set_property C_EN_STRG_QUAL false [get_debug_cores u_ila_2]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_2]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_2]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_2]
set_property port_width 1 [get_debug_ports u_ila_2/clk]
connect_debug_port u_ila_2/clk [get_nets [list clk_int]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_2/probe0]
set_property port_width 8 [get_debug_ports u_ila_2/probe0]
connect_debug_port u_ila_2/probe0 [get_nets [list {ping_pong_buffer_tx/o_m_axis_tdata[0]} {ping_pong_buffer_tx/o_m_axis_tdata[1]} {ping_pong_buffer_tx/o_m_axis_tdata[2]} {ping_pong_buffer_tx/o_m_axis_tdata[3]} {ping_pong_buffer_tx/o_m_axis_tdata[4]} {ping_pong_buffer_tx/o_m_axis_tdata[5]} {ping_pong_buffer_tx/o_m_axis_tdata[6]} {ping_pong_buffer_tx/o_m_axis_tdata[7]}]]
create_debug_port u_ila_2 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_2/probe1]
set_property port_width 8 [get_debug_ports u_ila_2/probe1]
connect_debug_port u_ila_2/probe1 [get_nets [list {adc_rx_axis_tdata[0]} {adc_rx_axis_tdata[1]} {adc_rx_axis_tdata[2]} {adc_rx_axis_tdata[3]} {adc_rx_axis_tdata[4]} {adc_rx_axis_tdata[5]} {adc_rx_axis_tdata[6]} {adc_rx_axis_tdata[7]}]]
create_debug_port u_ila_2 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_2/probe2]
set_property port_width 16 [get_debug_ports u_ila_2/probe2]
connect_debug_port u_ila_2/probe2 [get_nets [list {adc_fifo_r_data[0]} {adc_fifo_r_data[1]} {adc_fifo_r_data[2]} {adc_fifo_r_data[3]} {adc_fifo_r_data[4]} {adc_fifo_r_data[5]} {adc_fifo_r_data[6]} {adc_fifo_r_data[7]} {adc_fifo_r_data[8]} {adc_fifo_r_data[9]} {adc_fifo_r_data[10]} {adc_fifo_r_data[11]} {adc_fifo_r_data[12]} {adc_fifo_r_data[13]} {adc_fifo_r_data[14]} {adc_fifo_r_data[15]}]]
create_debug_port u_ila_2 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_2/probe3]
set_property port_width 16 [get_debug_ports u_ila_2/probe3]
connect_debug_port u_ila_2/probe3 [get_nets [list {adc_fifo_word_hold[0]} {adc_fifo_word_hold[1]} {adc_fifo_word_hold[2]} {adc_fifo_word_hold[3]} {adc_fifo_word_hold[4]} {adc_fifo_word_hold[5]} {adc_fifo_word_hold[6]} {adc_fifo_word_hold[7]} {adc_fifo_word_hold[8]} {adc_fifo_word_hold[9]} {adc_fifo_word_hold[10]} {adc_fifo_word_hold[11]} {adc_fifo_word_hold[12]} {adc_fifo_word_hold[13]} {adc_fifo_word_hold[14]} {adc_fifo_word_hold[15]}]]
create_debug_port u_ila_2 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_2/probe4]
set_property port_width 8 [get_debug_ports u_ila_2/probe4]
connect_debug_port u_ila_2/probe4 [get_nets [list {ping_pong_buffer_rx/o_m_axis_tdata[0]} {ping_pong_buffer_rx/o_m_axis_tdata[1]} {ping_pong_buffer_rx/o_m_axis_tdata[2]} {ping_pong_buffer_rx/o_m_axis_tdata[3]} {ping_pong_buffer_rx/o_m_axis_tdata[4]} {ping_pong_buffer_rx/o_m_axis_tdata[5]} {ping_pong_buffer_rx/o_m_axis_tdata[6]} {ping_pong_buffer_rx/o_m_axis_tdata[7]}]]
create_debug_port u_ila_2 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_2/probe5]
set_property port_width 11 [get_debug_ports u_ila_2/probe5]
connect_debug_port u_ila_2/probe5 [get_nets [list {adc_rx_frame_byte_count[0]} {adc_rx_frame_byte_count[1]} {adc_rx_frame_byte_count[2]} {adc_rx_frame_byte_count[3]} {adc_rx_frame_byte_count[4]} {adc_rx_frame_byte_count[5]} {adc_rx_frame_byte_count[6]} {adc_rx_frame_byte_count[7]} {adc_rx_frame_byte_count[8]} {adc_rx_frame_byte_count[9]} {adc_rx_frame_byte_count[10]}]]
create_debug_port u_ila_2 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_2/probe6]
set_property port_width 1 [get_debug_ports u_ila_2/probe6]
connect_debug_port u_ila_2/probe6 [get_nets [list adc_fifo_r_ready]]
create_debug_port u_ila_2 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_2/probe7]
set_property port_width 1 [get_debug_ports u_ila_2/probe7]
connect_debug_port u_ila_2/probe7 [get_nets [list adc_fifo_r_valid]]
create_debug_port u_ila_2 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_2/probe8]
set_property port_width 1 [get_debug_ports u_ila_2/probe8]
connect_debug_port u_ila_2/probe8 [get_nets [list adc_fifo_w_almost_full]]
create_debug_port u_ila_2 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_2/probe9]
set_property port_width 1 [get_debug_ports u_ila_2/probe9]
connect_debug_port u_ila_2/probe9 [get_nets [list adc_fifo_word_low_byte]]
create_debug_port u_ila_2 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_2/probe10]
set_property port_width 1 [get_debug_ports u_ila_2/probe10]
connect_debug_port u_ila_2/probe10 [get_nets [list adc_fifo_word_valid]]
create_debug_port u_ila_2 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_2/probe11]
set_property port_width 1 [get_debug_ports u_ila_2/probe11]
connect_debug_port u_ila_2/probe11 [get_nets [list adc_rx_axis_hs]]
create_debug_port u_ila_2 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_2/probe12]
set_property port_width 1 [get_debug_ports u_ila_2/probe12]
connect_debug_port u_ila_2/probe12 [get_nets [list adc_rx_axis_last_beat]]
create_debug_port u_ila_2 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_2/probe13]
set_property port_width 1 [get_debug_ports u_ila_2/probe13]
connect_debug_port u_ila_2/probe13 [get_nets [list adc_rx_axis_tlast]]
create_debug_port u_ila_2 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_2/probe14]
set_property port_width 1 [get_debug_ports u_ila_2/probe14]
connect_debug_port u_ila_2/probe14 [get_nets [list adc_rx_axis_tready]]
create_debug_port u_ila_2 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_2/probe15]
set_property port_width 1 [get_debug_ports u_ila_2/probe15]
connect_debug_port u_ila_2/probe15 [get_nets [list adc_rx_axis_tvalid]]
create_debug_core u_ila_3 ila
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_3]
set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores u_ila_3]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_3]
set_property C_DATA_DEPTH 8192 [get_debug_cores u_ila_3]
set_property C_EN_STRG_QUAL false [get_debug_cores u_ila_3]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_3]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_3]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_3]
set_property port_width 1 [get_debug_ports u_ila_3/clk]
connect_debug_port u_ila_3/clk [get_nets [list clk_spi]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_3/probe0]
set_property port_width 4 [get_debug_ports u_ila_3/probe0]
connect_debug_port u_ila_3/probe0 [get_nets [list {dac_config_inst/state[0]} {dac_config_inst/state[1]} {dac_config_inst/state[2]} {dac_config_inst/state[3]}]]
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets adc1_clk]
