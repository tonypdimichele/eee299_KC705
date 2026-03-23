# Ethernet constraints

# IDELAY on RGMII from PHY chip
set_property IDELAY_VALUE 0 [get_cells {phy_rx_ctl_idelay phy_rxd_idelay_*}]




connect_debug_port u_ila_0/probe0 [get_nets [list dac_config_inst/clk_spi_ce]]
connect_debug_port u_ila_0/probe1 [get_nets [list dac_config_inst/dac1_spi_ce]]
connect_debug_port u_ila_0/probe2 [get_nets [list dac_config_inst/dac2_spi_ce]]
connect_debug_port u_ila_0/probe4 [get_nets [list dac_config_inst/spi_sclk]]
connect_debug_port u_ila_0/probe5 [get_nets [list dac_config_inst/spi_sdo]]







connect_debug_port u_ila_0/probe0 [get_nets [list {dac1_l[0]} {dac1_l[1]} {dac1_l[2]} {dac1_l[3]} {dac1_l[4]} {dac1_l[5]} {dac1_l[6]} {dac1_l[7]} {dac1_l[8]} {dac1_l[9]} {dac1_l[10]} {dac1_l[11]} {dac1_l[12]} {dac1_l[13]}]]
connect_debug_port u_ila_0/probe1 [get_nets [list {dac1_h[0]} {dac1_h[1]} {dac1_h[2]} {dac1_h[3]} {dac1_h[4]} {dac1_h[5]} {dac1_h[6]} {dac1_h[7]} {dac1_h[8]} {dac1_h[9]} {dac1_h[10]} {dac1_h[11]} {dac1_h[12]} {dac1_h[13]}]]



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
connect_debug_port u_ila_0/clk [get_nets [list clk_250mhz_int]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe0]
set_property port_width 14 [get_debug_ports u_ila_0/probe0]
connect_debug_port u_ila_0/probe0 [get_nets [list {dac1_l_dbg_250[0]} {dac1_l_dbg_250[1]} {dac1_l_dbg_250[2]} {dac1_l_dbg_250[3]} {dac1_l_dbg_250[4]} {dac1_l_dbg_250[5]} {dac1_l_dbg_250[6]} {dac1_l_dbg_250[7]} {dac1_l_dbg_250[8]} {dac1_l_dbg_250[9]} {dac1_l_dbg_250[10]} {dac1_l_dbg_250[11]} {dac1_l_dbg_250[12]} {dac1_l_dbg_250[13]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe1]
set_property port_width 14 [get_debug_ports u_ila_0/probe1]
connect_debug_port u_ila_0/probe1 [get_nets [list {dac1_h_dbg_250[0]} {dac1_h_dbg_250[1]} {dac1_h_dbg_250[2]} {dac1_h_dbg_250[3]} {dac1_h_dbg_250[4]} {dac1_h_dbg_250[5]} {dac1_h_dbg_250[6]} {dac1_h_dbg_250[7]} {dac1_h_dbg_250[8]} {dac1_h_dbg_250[9]} {dac1_h_dbg_250[10]} {dac1_h_dbg_250[11]} {dac1_h_dbg_250[12]} {dac1_h_dbg_250[13]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe2]
set_property port_width 1 [get_debug_ports u_ila_0/probe2]
connect_debug_port u_ila_0/probe2 [get_nets [list dac_tone_mode_dbg_250]]
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
connect_debug_port u_ila_1/clk [get_nets [list clk_500mhz_int]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_1/probe0]
set_property port_width 14 [get_debug_ports u_ila_1/probe0]
connect_debug_port u_ila_1/probe0 [get_nets [list {dac1_h_dbg_500[0]} {dac1_h_dbg_500[1]} {dac1_h_dbg_500[2]} {dac1_h_dbg_500[3]} {dac1_h_dbg_500[4]} {dac1_h_dbg_500[5]} {dac1_h_dbg_500[6]} {dac1_h_dbg_500[7]} {dac1_h_dbg_500[8]} {dac1_h_dbg_500[9]} {dac1_h_dbg_500[10]} {dac1_h_dbg_500[11]} {dac1_h_dbg_500[12]} {dac1_h_dbg_500[13]}]]
create_debug_port u_ila_1 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_1/probe1]
set_property port_width 14 [get_debug_ports u_ila_1/probe1]
connect_debug_port u_ila_1/probe1 [get_nets [list {dac1_l_dbg_500[0]} {dac1_l_dbg_500[1]} {dac1_l_dbg_500[2]} {dac1_l_dbg_500[3]} {dac1_l_dbg_500[4]} {dac1_l_dbg_500[5]} {dac1_l_dbg_500[6]} {dac1_l_dbg_500[7]} {dac1_l_dbg_500[8]} {dac1_l_dbg_500[9]} {dac1_l_dbg_500[10]} {dac1_l_dbg_500[11]} {dac1_l_dbg_500[12]} {dac1_l_dbg_500[13]}]]
create_debug_port u_ila_1 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_1/probe2]
set_property port_width 1 [get_debug_ports u_ila_1/probe2]
connect_debug_port u_ila_1/probe2 [get_nets [list dac_tone_mode_dbg_500]]
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
connect_debug_port u_ila_2/clk [get_nets [list clk_spi]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_2/probe0]
set_property port_width 4 [get_debug_ports u_ila_2/probe0]
connect_debug_port u_ila_2/probe0 [get_nets [list {dac_config_inst/state[0]} {dac_config_inst/state[1]} {dac_config_inst/state[2]} {dac_config_inst/state[3]}]]
create_debug_port u_ila_2 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_2/probe1]
set_property port_width 1 [get_debug_ports u_ila_2/probe1]
connect_debug_port u_ila_2/probe1 [get_nets [list dac_config_inst/dac1_cs_debug]]
create_debug_port u_ila_2 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_2/probe2]
set_property port_width 1 [get_debug_ports u_ila_2/probe2]
connect_debug_port u_ila_2/probe2 [get_nets [list dac_config_inst/dac2_cs_debug]]
create_debug_port u_ila_2 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_2/probe3]
set_property port_width 1 [get_debug_ports u_ila_2/probe3]
connect_debug_port u_ila_2/probe3 [get_nets [list dac_config_inst/pll_locked_debug]]
create_debug_port u_ila_2 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_2/probe4]
set_property port_width 1 [get_debug_ports u_ila_2/probe4]
connect_debug_port u_ila_2/probe4 [get_nets [list dac_config_inst/sdio_debug]]
create_debug_port u_ila_2 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_2/probe5]
set_property port_width 1 [get_debug_ports u_ila_2/probe5]
connect_debug_port u_ila_2/probe5 [get_nets [list dac_config_inst/sdo_debug]]
create_debug_port u_ila_2 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_2/probe6]
set_property port_width 1 [get_debug_ports u_ila_2/probe6]
connect_debug_port u_ila_2/probe6 [get_nets [list dac_config_inst/spi_clk_debug]]
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
connect_debug_port u_ila_3/clk [get_nets [list clk_int]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_3/probe0]
set_property port_width 14 [get_debug_ports u_ila_3/probe0]
connect_debug_port u_ila_3/probe0 [get_nets [list {iq_codec_loop_inst/tone_dac1_h[0]} {iq_codec_loop_inst/tone_dac1_h[1]} {iq_codec_loop_inst/tone_dac1_h[2]} {iq_codec_loop_inst/tone_dac1_h[3]} {iq_codec_loop_inst/tone_dac1_h[4]} {iq_codec_loop_inst/tone_dac1_h[5]} {iq_codec_loop_inst/tone_dac1_h[6]} {iq_codec_loop_inst/tone_dac1_h[7]} {iq_codec_loop_inst/tone_dac1_h[8]} {iq_codec_loop_inst/tone_dac1_h[9]} {iq_codec_loop_inst/tone_dac1_h[10]} {iq_codec_loop_inst/tone_dac1_h[11]} {iq_codec_loop_inst/tone_dac1_h[12]} {iq_codec_loop_inst/tone_dac1_h[13]}]]
create_debug_port u_ila_3 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_3/probe1]
set_property port_width 14 [get_debug_ports u_ila_3/probe1]
connect_debug_port u_ila_3/probe1 [get_nets [list {iq_codec_loop_inst/tone_dac1_l[0]} {iq_codec_loop_inst/tone_dac1_l[1]} {iq_codec_loop_inst/tone_dac1_l[2]} {iq_codec_loop_inst/tone_dac1_l[3]} {iq_codec_loop_inst/tone_dac1_l[4]} {iq_codec_loop_inst/tone_dac1_l[5]} {iq_codec_loop_inst/tone_dac1_l[6]} {iq_codec_loop_inst/tone_dac1_l[7]} {iq_codec_loop_inst/tone_dac1_l[8]} {iq_codec_loop_inst/tone_dac1_l[9]} {iq_codec_loop_inst/tone_dac1_l[10]} {iq_codec_loop_inst/tone_dac1_l[11]} {iq_codec_loop_inst/tone_dac1_l[12]} {iq_codec_loop_inst/tone_dac1_l[13]}]]
create_debug_port u_ila_3 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_3/probe2]
set_property port_width 32 [get_debug_ports u_ila_3/probe2]
connect_debug_port u_ila_3/probe2 [get_nets [list {iq_codec_loop_inst/tone_dds_tdata[0]} {iq_codec_loop_inst/tone_dds_tdata[1]} {iq_codec_loop_inst/tone_dds_tdata[2]} {iq_codec_loop_inst/tone_dds_tdata[3]} {iq_codec_loop_inst/tone_dds_tdata[4]} {iq_codec_loop_inst/tone_dds_tdata[5]} {iq_codec_loop_inst/tone_dds_tdata[6]} {iq_codec_loop_inst/tone_dds_tdata[7]} {iq_codec_loop_inst/tone_dds_tdata[8]} {iq_codec_loop_inst/tone_dds_tdata[9]} {iq_codec_loop_inst/tone_dds_tdata[10]} {iq_codec_loop_inst/tone_dds_tdata[11]} {iq_codec_loop_inst/tone_dds_tdata[12]} {iq_codec_loop_inst/tone_dds_tdata[13]} {iq_codec_loop_inst/tone_dds_tdata[14]} {iq_codec_loop_inst/tone_dds_tdata[15]} {iq_codec_loop_inst/tone_dds_tdata[16]} {iq_codec_loop_inst/tone_dds_tdata[17]} {iq_codec_loop_inst/tone_dds_tdata[18]} {iq_codec_loop_inst/tone_dds_tdata[19]} {iq_codec_loop_inst/tone_dds_tdata[20]} {iq_codec_loop_inst/tone_dds_tdata[21]} {iq_codec_loop_inst/tone_dds_tdata[22]} {iq_codec_loop_inst/tone_dds_tdata[23]} {iq_codec_loop_inst/tone_dds_tdata[24]} {iq_codec_loop_inst/tone_dds_tdata[25]} {iq_codec_loop_inst/tone_dds_tdata[26]} {iq_codec_loop_inst/tone_dds_tdata[27]} {iq_codec_loop_inst/tone_dds_tdata[28]} {iq_codec_loop_inst/tone_dds_tdata[29]} {iq_codec_loop_inst/tone_dds_tdata[30]} {iq_codec_loop_inst/tone_dds_tdata[31]}]]
create_debug_port u_ila_3 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_3/probe3]
set_property port_width 1 [get_debug_ports u_ila_3/probe3]
connect_debug_port u_ila_3/probe3 [get_nets [list dac_tone_mode]]
create_debug_port u_ila_3 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_3/probe4]
set_property port_width 1 [get_debug_ports u_ila_3/probe4]
connect_debug_port u_ila_3/probe4 [get_nets [list helpme]]
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk_250mhz_int]
