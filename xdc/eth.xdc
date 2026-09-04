# Ethernet constraints

# IDELAY on RGMII from PHY chip
set_property IDELAY_VALUE 0 [get_cells {phy_rx_ctl_idelay phy_rxd_idelay_*}]








connect_debug_port u_ila_2/clk [get_nets [list ADC2_CLK_REF_OBUF]]


connect_debug_port u_ila_1/clk [get_nets [list adc2_clk]]
connect_debug_port u_ila_3/clk [get_nets [list adc1_clk_BUFG]]


connect_debug_port u_ila_1/probe3 [get_nets [list {adc_fifo_word_hold[0]} {adc_fifo_word_hold[1]} {adc_fifo_word_hold[2]} {adc_fifo_word_hold[3]} {adc_fifo_word_hold[4]} {adc_fifo_word_hold[5]} {adc_fifo_word_hold[6]} {adc_fifo_word_hold[7]} {adc_fifo_word_hold[8]} {adc_fifo_word_hold[9]} {adc_fifo_word_hold[10]} {adc_fifo_word_hold[11]} {adc_fifo_word_hold[12]} {adc_fifo_word_hold[13]} {adc_fifo_word_hold[14]} {adc_fifo_word_hold[15]}]]
connect_debug_port u_ila_1/probe9 [get_nets [list adc_fifo_word_low_byte]]
connect_debug_port u_ila_1/probe10 [get_nets [list adc_fifo_word_valid]]




connect_debug_port u_ila_1/probe0 [get_nets [list {adc_top_inst/adc2_data_a_d0[0]} {adc_top_inst/adc2_data_a_d0[1]} {adc_top_inst/adc2_data_a_d0[2]} {adc_top_inst/adc2_data_a_d0[3]} {adc_top_inst/adc2_data_a_d0[4]} {adc_top_inst/adc2_data_a_d0[5]} {adc_top_inst/adc2_data_a_d0[6]} {adc_top_inst/adc2_data_a_d0[7]} {adc_top_inst/adc2_data_a_d0[8]} {adc_top_inst/adc2_data_a_d0[9]} {adc_top_inst/adc2_data_a_d0[10]} {adc_top_inst/adc2_data_a_d0[11]}]]




connect_debug_port u_ila_1/probe1 [get_nets [list {adc_top_inst/adc2_data_a_d0_reg_n_0_[0]}]]
connect_debug_port u_ila_1/probe2 [get_nets [list {adc_top_inst/adc2_data_a_d0_reg_n_0_[1]}]]
connect_debug_port u_ila_1/probe3 [get_nets [list {adc_top_inst/adc2_data_a_d0_reg_n_0_[2]}]]
connect_debug_port u_ila_1/probe4 [get_nets [list {adc_top_inst/adc2_data_a_d0_reg_n_0_[3]}]]
connect_debug_port u_ila_1/probe5 [get_nets [list {adc_top_inst/adc2_data_a_d0_reg_n_0_[4]}]]
connect_debug_port u_ila_1/probe6 [get_nets [list {adc_top_inst/adc2_data_a_d0_reg_n_0_[5]}]]
connect_debug_port u_ila_1/probe7 [get_nets [list {adc_top_inst/adc2_data_a_d0_reg_n_0_[6]}]]
connect_debug_port u_ila_1/probe8 [get_nets [list {adc_top_inst/adc2_data_a_d0_reg_n_0_[7]}]]
connect_debug_port u_ila_1/probe9 [get_nets [list {adc_top_inst/adc2_data_a_d0_reg_n_0_[8]}]]
connect_debug_port u_ila_1/probe10 [get_nets [list {adc_top_inst/adc2_data_a_d0_reg_n_0_[9]}]]
connect_debug_port u_ila_1/probe11 [get_nets [list {adc_top_inst/adc2_data_a_d0_reg_n_0_[10]}]]
connect_debug_port u_ila_1/probe12 [get_nets [list {adc_top_inst/adc2_data_a_d0_reg_n_0_[11]}]]

connect_debug_port u_ila_1/probe0 [get_nets [list {adc_top_inst/adc2_data_a_d0[0]} {adc_top_inst/adc2_data_a_d0[1]} {adc_top_inst/adc2_data_a_d0[2]} {adc_top_inst/adc2_data_a_d0[3]} {adc_top_inst/adc2_data_a_d0[4]} {adc_top_inst/adc2_data_a_d0[5]} {adc_top_inst/adc2_data_a_d0[6]} {adc_top_inst/adc2_data_a_d0[7]} {adc_top_inst/adc2_data_a_d0[8]} {adc_top_inst/adc2_data_a_d0[9]} {adc_top_inst/adc2_data_a_d0[10]} {adc_top_inst/adc2_data_a_d0[11]}]]





connect_debug_port u_ila_0/probe8 [get_nets [list {qpsk_rx_demod_inst/timing_symbol_period[0]} {qpsk_rx_demod_inst/timing_symbol_period[1]} {qpsk_rx_demod_inst/timing_symbol_period[2]} {qpsk_rx_demod_inst/timing_symbol_period[3]} {qpsk_rx_demod_inst/timing_symbol_period[4]} {qpsk_rx_demod_inst/timing_symbol_period[5]} {qpsk_rx_demod_inst/timing_symbol_period[6]} {qpsk_rx_demod_inst/timing_symbol_period[7]}]]
connect_debug_port u_ila_0/probe31 [get_nets [list qpsk_rx_demod_inst/timing_locked]]


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
connect_debug_port u_ila_0/probe0 [get_nets [list {qpsk_hpf_out_b[0]} {qpsk_hpf_out_b[1]} {qpsk_hpf_out_b[2]} {qpsk_hpf_out_b[3]} {qpsk_hpf_out_b[4]} {qpsk_hpf_out_b[5]} {qpsk_hpf_out_b[6]} {qpsk_hpf_out_b[7]} {qpsk_hpf_out_b[8]} {qpsk_hpf_out_b[9]} {qpsk_hpf_out_b[10]} {qpsk_hpf_out_b[11]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe1]
set_property port_width 2 [get_debug_ports u_ila_0/probe1]
connect_debug_port u_ila_0/probe1 [get_nets [list {qpsk_rx_phase_rot[0]} {qpsk_rx_phase_rot[1]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe2]
set_property port_width 24 [get_debug_ports u_ila_0/probe2]
connect_debug_port u_ila_0/probe2 [get_nets [list {qpsk_rx_corr_mag[0]} {qpsk_rx_corr_mag[1]} {qpsk_rx_corr_mag[2]} {qpsk_rx_corr_mag[3]} {qpsk_rx_corr_mag[4]} {qpsk_rx_corr_mag[5]} {qpsk_rx_corr_mag[6]} {qpsk_rx_corr_mag[7]} {qpsk_rx_corr_mag[8]} {qpsk_rx_corr_mag[9]} {qpsk_rx_corr_mag[10]} {qpsk_rx_corr_mag[11]} {qpsk_rx_corr_mag[12]} {qpsk_rx_corr_mag[13]} {qpsk_rx_corr_mag[14]} {qpsk_rx_corr_mag[15]} {qpsk_rx_corr_mag[16]} {qpsk_rx_corr_mag[17]} {qpsk_rx_corr_mag[18]} {qpsk_rx_corr_mag[19]} {qpsk_rx_corr_mag[20]} {qpsk_rx_corr_mag[21]} {qpsk_rx_corr_mag[22]} {qpsk_rx_corr_mag[23]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe3]
set_property port_width 8 [get_debug_ports u_ila_0/probe3]
connect_debug_port u_ila_0/probe3 [get_nets [list {qpsk_rx_tdata[0]} {qpsk_rx_tdata[1]} {qpsk_rx_tdata[2]} {qpsk_rx_tdata[3]} {qpsk_rx_tdata[4]} {qpsk_rx_tdata[5]} {qpsk_rx_tdata[6]} {qpsk_rx_tdata[7]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe4]
set_property port_width 12 [get_debug_ports u_ila_0/probe4]
connect_debug_port u_ila_0/probe4 [get_nets [list {qpsk_hpf_out_a[0]} {qpsk_hpf_out_a[1]} {qpsk_hpf_out_a[2]} {qpsk_hpf_out_a[3]} {qpsk_hpf_out_a[4]} {qpsk_hpf_out_a[5]} {qpsk_hpf_out_a[6]} {qpsk_hpf_out_a[7]} {qpsk_hpf_out_a[8]} {qpsk_hpf_out_a[9]} {qpsk_hpf_out_a[10]} {qpsk_hpf_out_a[11]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe5]
set_property port_width 12 [get_debug_ports u_ila_0/probe5]
connect_debug_port u_ila_0/probe5 [get_nets [list {hpf_out_b[0]} {hpf_out_b[1]} {hpf_out_b[2]} {hpf_out_b[3]} {hpf_out_b[4]} {hpf_out_b[5]} {hpf_out_b[6]} {hpf_out_b[7]} {hpf_out_b[8]} {hpf_out_b[9]} {hpf_out_b[10]} {hpf_out_b[11]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe6]
set_property port_width 12 [get_debug_ports u_ila_0/probe6]
connect_debug_port u_ila_0/probe6 [get_nets [list {hpf_out_a[0]} {hpf_out_a[1]} {hpf_out_a[2]} {hpf_out_a[3]} {hpf_out_a[4]} {hpf_out_a[5]} {hpf_out_a[6]} {hpf_out_a[7]} {hpf_out_a[8]} {hpf_out_a[9]} {hpf_out_a[10]} {hpf_out_a[11]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe7]
set_property port_width 12 [get_debug_ports u_ila_0/probe7]
connect_debug_port u_ila_0/probe7 [get_nets [list {adc_top_inst/adc1_data_a_d0[0]} {adc_top_inst/adc1_data_a_d0[1]} {adc_top_inst/adc1_data_a_d0[2]} {adc_top_inst/adc1_data_a_d0[3]} {adc_top_inst/adc1_data_a_d0[4]} {adc_top_inst/adc1_data_a_d0[5]} {adc_top_inst/adc1_data_a_d0[6]} {adc_top_inst/adc1_data_a_d0[7]} {adc_top_inst/adc1_data_a_d0[8]} {adc_top_inst/adc1_data_a_d0[9]} {adc_top_inst/adc1_data_a_d0[10]} {adc_top_inst/adc1_data_a_d0[11]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe8]
set_property port_width 12 [get_debug_ports u_ila_0/probe8]
connect_debug_port u_ila_0/probe8 [get_nets [list {adc_top_inst/adc1_data_b_d0[0]} {adc_top_inst/adc1_data_b_d0[1]} {adc_top_inst/adc1_data_b_d0[2]} {adc_top_inst/adc1_data_b_d0[3]} {adc_top_inst/adc1_data_b_d0[4]} {adc_top_inst/adc1_data_b_d0[5]} {adc_top_inst/adc1_data_b_d0[6]} {adc_top_inst/adc1_data_b_d0[7]} {adc_top_inst/adc1_data_b_d0[8]} {adc_top_inst/adc1_data_b_d0[9]} {adc_top_inst/adc1_data_b_d0[10]} {adc_top_inst/adc1_data_b_d0[11]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe9]
set_property port_width 3 [get_debug_ports u_ila_0/probe9]
connect_debug_port u_ila_0/probe9 [get_nets [list {adc_dbg_byte_idx[0]} {adc_dbg_byte_idx[1]} {adc_dbg_byte_idx[2]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe10]
set_property port_width 8 [get_debug_ports u_ila_0/probe10]
connect_debug_port u_ila_0/probe10 [get_nets [list {adc_fifo_w_data[0]} {adc_fifo_w_data[1]} {adc_fifo_w_data[2]} {adc_fifo_w_data[3]} {adc_fifo_w_data[4]} {adc_fifo_w_data[5]} {adc_fifo_w_data[6]} {adc_fifo_w_data[7]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe11]
set_property port_width 8 [get_debug_ports u_ila_0/probe11]
connect_debug_port u_ila_0/probe11 [get_nets [list {adc_stats_inst/m_axis_tdata[0]} {adc_stats_inst/m_axis_tdata[1]} {adc_stats_inst/m_axis_tdata[2]} {adc_stats_inst/m_axis_tdata[3]} {adc_stats_inst/m_axis_tdata[4]} {adc_stats_inst/m_axis_tdata[5]} {adc_stats_inst/m_axis_tdata[6]} {adc_stats_inst/m_axis_tdata[7]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe12]
set_property port_width 12 [get_debug_ports u_ila_0/probe12]
connect_debug_port u_ila_0/probe12 [get_nets [list {adc_stats_inst/prev_sample_i[0]} {adc_stats_inst/prev_sample_i[1]} {adc_stats_inst/prev_sample_i[2]} {adc_stats_inst/prev_sample_i[3]} {adc_stats_inst/prev_sample_i[4]} {adc_stats_inst/prev_sample_i[5]} {adc_stats_inst/prev_sample_i[6]} {adc_stats_inst/prev_sample_i[7]} {adc_stats_inst/prev_sample_i[8]} {adc_stats_inst/prev_sample_i[9]} {adc_stats_inst/prev_sample_i[10]} {adc_stats_inst/prev_sample_i[11]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe13]
set_property port_width 18 [get_debug_ports u_ila_0/probe13]
connect_debug_port u_ila_0/probe13 [get_nets [list {qpsk_rx_demod_inst/sym_q_latched[0]} {qpsk_rx_demod_inst/sym_q_latched[1]} {qpsk_rx_demod_inst/sym_q_latched[2]} {qpsk_rx_demod_inst/sym_q_latched[3]} {qpsk_rx_demod_inst/sym_q_latched[4]} {qpsk_rx_demod_inst/sym_q_latched[5]} {qpsk_rx_demod_inst/sym_q_latched[6]} {qpsk_rx_demod_inst/sym_q_latched[7]} {qpsk_rx_demod_inst/sym_q_latched[8]} {qpsk_rx_demod_inst/sym_q_latched[9]} {qpsk_rx_demod_inst/sym_q_latched[10]} {qpsk_rx_demod_inst/sym_q_latched[11]} {qpsk_rx_demod_inst/sym_q_latched[12]} {qpsk_rx_demod_inst/sym_q_latched[13]} {qpsk_rx_demod_inst/sym_q_latched[14]} {qpsk_rx_demod_inst/sym_q_latched[15]} {qpsk_rx_demod_inst/sym_q_latched[16]} {qpsk_rx_demod_inst/sym_q_latched[17]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe14]
set_property port_width 3 [get_debug_ports u_ila_0/probe14]
connect_debug_port u_ila_0/probe14 [get_nets [list {qpsk_rx_demod_inst/state[0]} {qpsk_rx_demod_inst/state[1]} {qpsk_rx_demod_inst/state[2]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe15]
set_property port_width 5 [get_debug_ports u_ila_0/probe15]
connect_debug_port u_ila_0/probe15 [get_nets [list {qpsk_rx_demod_inst/samp_cnt[0]} {qpsk_rx_demod_inst/samp_cnt[1]} {qpsk_rx_demod_inst/samp_cnt[2]} {qpsk_rx_demod_inst/samp_cnt[3]} {qpsk_rx_demod_inst/samp_cnt[4]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe16]
set_property port_width 18 [get_debug_ports u_ila_0/probe16]
connect_debug_port u_ila_0/probe16 [get_nets [list {qpsk_rx_demod_inst/sym_i_latched[0]} {qpsk_rx_demod_inst/sym_i_latched[1]} {qpsk_rx_demod_inst/sym_i_latched[2]} {qpsk_rx_demod_inst/sym_i_latched[3]} {qpsk_rx_demod_inst/sym_i_latched[4]} {qpsk_rx_demod_inst/sym_i_latched[5]} {qpsk_rx_demod_inst/sym_i_latched[6]} {qpsk_rx_demod_inst/sym_i_latched[7]} {qpsk_rx_demod_inst/sym_i_latched[8]} {qpsk_rx_demod_inst/sym_i_latched[9]} {qpsk_rx_demod_inst/sym_i_latched[10]} {qpsk_rx_demod_inst/sym_i_latched[11]} {qpsk_rx_demod_inst/sym_i_latched[12]} {qpsk_rx_demod_inst/sym_i_latched[13]} {qpsk_rx_demod_inst/sym_i_latched[14]} {qpsk_rx_demod_inst/sym_i_latched[15]} {qpsk_rx_demod_inst/sym_i_latched[16]} {qpsk_rx_demod_inst/sym_i_latched[17]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe17]
set_property port_width 2 [get_debug_ports u_ila_0/probe17]
connect_debug_port u_ila_0/probe17 [get_nets [list {qpsk_rx_demod_inst/phase_ref_cnt[0]} {qpsk_rx_demod_inst/phase_ref_cnt[1]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe18]
set_property port_width 8 [get_debug_ports u_ila_0/probe18]
connect_debug_port u_ila_0/probe18 [get_nets [list {adc_to_eth_afifo_inst/i_w_data[0]} {adc_to_eth_afifo_inst/i_w_data[1]} {adc_to_eth_afifo_inst/i_w_data[2]} {adc_to_eth_afifo_inst/i_w_data[3]} {adc_to_eth_afifo_inst/i_w_data[4]} {adc_to_eth_afifo_inst/i_w_data[5]} {adc_to_eth_afifo_inst/i_w_data[6]} {adc_to_eth_afifo_inst/i_w_data[7]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe19]
set_property port_width 1 [get_debug_ports u_ila_0/probe19]
connect_debug_port u_ila_0/probe19 [get_nets [list adc_fifo_w_valid]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe20]
set_property port_width 1 [get_debug_ports u_ila_0/probe20]
connect_debug_port u_ila_0/probe20 [get_nets [list helpme]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe21]
set_property port_width 1 [get_debug_ports u_ila_0/probe21]
connect_debug_port u_ila_0/probe21 [get_nets [list qpsk_rx_demod_inst/i_corrected]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe22]
set_property port_width 1 [get_debug_ports u_ila_0/probe22]
connect_debug_port u_ila_0/probe22 [get_nets [list qpsk_rx_demod_inst/i_hard]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe23]
set_property port_width 1 [get_debug_ports u_ila_0/probe23]
connect_debug_port u_ila_0/probe23 [get_nets [list qpsk_rx_demod_inst/q_corrected]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe24]
set_property port_width 1 [get_debug_ports u_ila_0/probe24]
connect_debug_port u_ila_0/probe24 [get_nets [list qpsk_rx_demod_inst/q_hard]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe25]
set_property port_width 1 [get_debug_ports u_ila_0/probe25]
connect_debug_port u_ila_0/probe25 [get_nets [list qpsk_mode_adc_ff1]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe26]
set_property port_width 1 [get_debug_ports u_ila_0/probe26]
connect_debug_port u_ila_0/probe26 [get_nets [list qpsk_mode_adc_ff2]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe27]
set_property port_width 1 [get_debug_ports u_ila_0/probe27]
connect_debug_port u_ila_0/probe27 [get_nets [list qpsk_rx_frame_detected]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe28]
set_property port_width 1 [get_debug_ports u_ila_0/probe28]
connect_debug_port u_ila_0/probe28 [get_nets [list qpsk_rx_frame_done]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe29]
set_property port_width 1 [get_debug_ports u_ila_0/probe29]
connect_debug_port u_ila_0/probe29 [get_nets [list qpsk_rx_tvalid]]
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
connect_debug_port u_ila_1/clk [get_nets [list dac_iobuf_inst/dac1_dco_buf]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_1/probe0]
set_property port_width 14 [get_debug_ports u_ila_1/probe0]
connect_debug_port u_ila_1/probe0 [get_nets [list {iq_codec_loop_inst/dac1_h_mux[0]} {iq_codec_loop_inst/dac1_h_mux[1]} {iq_codec_loop_inst/dac1_h_mux[2]} {iq_codec_loop_inst/dac1_h_mux[3]} {iq_codec_loop_inst/dac1_h_mux[4]} {iq_codec_loop_inst/dac1_h_mux[5]} {iq_codec_loop_inst/dac1_h_mux[6]} {iq_codec_loop_inst/dac1_h_mux[7]} {iq_codec_loop_inst/dac1_h_mux[8]} {iq_codec_loop_inst/dac1_h_mux[9]} {iq_codec_loop_inst/dac1_h_mux[10]} {iq_codec_loop_inst/dac1_h_mux[11]} {iq_codec_loop_inst/dac1_h_mux[12]} {iq_codec_loop_inst/dac1_h_mux[13]}]]
create_debug_port u_ila_1 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_1/probe1]
set_property port_width 14 [get_debug_ports u_ila_1/probe1]
connect_debug_port u_ila_1/probe1 [get_nets [list {iq_codec_loop_inst/dac1_l_mux[0]} {iq_codec_loop_inst/dac1_l_mux[1]} {iq_codec_loop_inst/dac1_l_mux[2]} {iq_codec_loop_inst/dac1_l_mux[3]} {iq_codec_loop_inst/dac1_l_mux[4]} {iq_codec_loop_inst/dac1_l_mux[5]} {iq_codec_loop_inst/dac1_l_mux[6]} {iq_codec_loop_inst/dac1_l_mux[7]} {iq_codec_loop_inst/dac1_l_mux[8]} {iq_codec_loop_inst/dac1_l_mux[9]} {iq_codec_loop_inst/dac1_l_mux[10]} {iq_codec_loop_inst/dac1_l_mux[11]} {iq_codec_loop_inst/dac1_l_mux[12]} {iq_codec_loop_inst/dac1_l_mux[13]}]]
create_debug_port u_ila_1 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_1/probe2]
set_property port_width 14 [get_debug_ports u_ila_1/probe2]
connect_debug_port u_ila_1/probe2 [get_nets [list {iq_codec_loop_inst/qpsk_tx_q_sample[0]} {iq_codec_loop_inst/qpsk_tx_q_sample[1]} {iq_codec_loop_inst/qpsk_tx_q_sample[2]} {iq_codec_loop_inst/qpsk_tx_q_sample[3]} {iq_codec_loop_inst/qpsk_tx_q_sample[4]} {iq_codec_loop_inst/qpsk_tx_q_sample[5]} {iq_codec_loop_inst/qpsk_tx_q_sample[6]} {iq_codec_loop_inst/qpsk_tx_q_sample[7]} {iq_codec_loop_inst/qpsk_tx_q_sample[8]} {iq_codec_loop_inst/qpsk_tx_q_sample[9]} {iq_codec_loop_inst/qpsk_tx_q_sample[10]} {iq_codec_loop_inst/qpsk_tx_q_sample[11]} {iq_codec_loop_inst/qpsk_tx_q_sample[12]} {iq_codec_loop_inst/qpsk_tx_q_sample[13]}]]
create_debug_port u_ila_1 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_1/probe3]
set_property port_width 14 [get_debug_ports u_ila_1/probe3]
connect_debug_port u_ila_1/probe3 [get_nets [list {iq_codec_loop_inst/qpsk_tx_i_sample[0]} {iq_codec_loop_inst/qpsk_tx_i_sample[1]} {iq_codec_loop_inst/qpsk_tx_i_sample[2]} {iq_codec_loop_inst/qpsk_tx_i_sample[3]} {iq_codec_loop_inst/qpsk_tx_i_sample[4]} {iq_codec_loop_inst/qpsk_tx_i_sample[5]} {iq_codec_loop_inst/qpsk_tx_i_sample[6]} {iq_codec_loop_inst/qpsk_tx_i_sample[7]} {iq_codec_loop_inst/qpsk_tx_i_sample[8]} {iq_codec_loop_inst/qpsk_tx_i_sample[9]} {iq_codec_loop_inst/qpsk_tx_i_sample[10]} {iq_codec_loop_inst/qpsk_tx_i_sample[11]} {iq_codec_loop_inst/qpsk_tx_i_sample[12]} {iq_codec_loop_inst/qpsk_tx_i_sample[13]}]]
create_debug_port u_ila_1 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_1/probe4]
set_property port_width 1 [get_debug_ports u_ila_1/probe4]
connect_debug_port u_ila_1/probe4 [get_nets [list iq_codec_loop_inst/qpsk_tx_frame_active]]
create_debug_port u_ila_1 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_1/probe5]
set_property port_width 1 [get_debug_ports u_ila_1/probe5]
connect_debug_port u_ila_1/probe5 [get_nets [list iq_codec_loop_inst/qpsk_tx_framer_inst_i_1_n_0]]
create_debug_port u_ila_1 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_1/probe6]
set_property port_width 1 [get_debug_ports u_ila_1/probe6]
connect_debug_port u_ila_1/probe6 [get_nets [list iq_codec_loop_inst/qpsk_tx_symbol_valid]]
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
set_property port_width 1 [get_debug_ports u_ila_2/probe0]
connect_debug_port u_ila_2/probe0 [get_nets [list iq_codec_loop_inst/i_qpsk_mode]]
create_debug_port u_ila_2 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_2/probe1]
set_property port_width 1 [get_debug_ports u_ila_2/probe1]
connect_debug_port u_ila_2/probe1 [get_nets [list iq_codec_loop_inst/i_tone_mode]]
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets adc1_clk]
