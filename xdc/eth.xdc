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





connect_debug_port u_ila_0/probe1 [get_nets [list {iq_codec_loop_inst/nolabel_line87/I[0]} {iq_codec_loop_inst/nolabel_line87/I[1]} {iq_codec_loop_inst/nolabel_line87/I[2]} {iq_codec_loop_inst/nolabel_line87/I[3]} {iq_codec_loop_inst/nolabel_line87/I[4]} {iq_codec_loop_inst/nolabel_line87/I[5]} {iq_codec_loop_inst/nolabel_line87/I[6]} {iq_codec_loop_inst/nolabel_line87/I[7]}]]
connect_debug_port u_ila_0/probe2 [get_nets [list {iq_codec_loop_inst/nolabel_line87/Q_filtered[0]} {iq_codec_loop_inst/nolabel_line87/Q_filtered[1]} {iq_codec_loop_inst/nolabel_line87/Q_filtered[2]} {iq_codec_loop_inst/nolabel_line87/Q_filtered[3]} {iq_codec_loop_inst/nolabel_line87/Q_filtered[4]} {iq_codec_loop_inst/nolabel_line87/Q_filtered[5]} {iq_codec_loop_inst/nolabel_line87/Q_filtered[6]} {iq_codec_loop_inst/nolabel_line87/Q_filtered[7]} {iq_codec_loop_inst/nolabel_line87/Q_filtered[8]} {iq_codec_loop_inst/nolabel_line87/Q_filtered[9]} {iq_codec_loop_inst/nolabel_line87/Q_filtered[10]} {iq_codec_loop_inst/nolabel_line87/Q_filtered[11]} {iq_codec_loop_inst/nolabel_line87/Q_filtered[12]} {iq_codec_loop_inst/nolabel_line87/Q_filtered[13]} {iq_codec_loop_inst/nolabel_line87/Q_filtered[14]} {iq_codec_loop_inst/nolabel_line87/Q_filtered[15]}]]
connect_debug_port u_ila_0/probe3 [get_nets [list {iq_codec_loop_inst/nolabel_line87/Q[0]} {iq_codec_loop_inst/nolabel_line87/Q[1]} {iq_codec_loop_inst/nolabel_line87/Q[2]} {iq_codec_loop_inst/nolabel_line87/Q[3]} {iq_codec_loop_inst/nolabel_line87/Q[4]} {iq_codec_loop_inst/nolabel_line87/Q[5]} {iq_codec_loop_inst/nolabel_line87/Q[6]} {iq_codec_loop_inst/nolabel_line87/Q[7]}]]
connect_debug_port u_ila_0/probe4 [get_nets [list {iq_codec_loop_inst/nolabel_line87/I_filtered[0]} {iq_codec_loop_inst/nolabel_line87/I_filtered[1]} {iq_codec_loop_inst/nolabel_line87/I_filtered[2]} {iq_codec_loop_inst/nolabel_line87/I_filtered[3]} {iq_codec_loop_inst/nolabel_line87/I_filtered[4]} {iq_codec_loop_inst/nolabel_line87/I_filtered[5]} {iq_codec_loop_inst/nolabel_line87/I_filtered[6]} {iq_codec_loop_inst/nolabel_line87/I_filtered[7]} {iq_codec_loop_inst/nolabel_line87/I_filtered[8]} {iq_codec_loop_inst/nolabel_line87/I_filtered[9]} {iq_codec_loop_inst/nolabel_line87/I_filtered[10]} {iq_codec_loop_inst/nolabel_line87/I_filtered[11]} {iq_codec_loop_inst/nolabel_line87/I_filtered[12]} {iq_codec_loop_inst/nolabel_line87/I_filtered[13]} {iq_codec_loop_inst/nolabel_line87/I_filtered[14]} {iq_codec_loop_inst/nolabel_line87/I_filtered[15]}]]
connect_debug_port u_ila_0/probe7 [get_nets [list iq_codec_loop_inst/nolabel_line87/aclk]]



