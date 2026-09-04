#=============================================================================
# File        : wave.do
# Project     : AXI4 to AHB-Lite Bridge VIP
# Author      : Huy Le
# Description : QuestaSim waveform setup for bridge-level debug.
#=============================================================================

onerror {resume}

#-----------------------------------------------------------------------------
# Custom radices
#-----------------------------------------------------------------------------
radix define axi_burst {
    2'b00 "FIXED" -color #00ff00,
    2'b01 "INCR"  -color #00ff00,
    2'b10 "WRAP"  -color #00ff00,
    2'b11 "RSVD"  -color #ff0000,
    -default hex
}

radix define transfer_size {
    3'b000 "1B"   -color #00ff00,
    3'b001 "2B"   -color #00ff00,
    3'b010 "4B"   -color #00ff00,
    3'b011 "8B"   -color #00ff00,
    3'b100 "16B"  -color #00ff00,
    3'b101 "32B"  -color #00ff00,
    3'b110 "64B"  -color #00ff00,
    3'b111 "128B" -color #00ff00,
    -default hex
}

radix define axi_resp {
    2'b00 "OKAY"   -color #00ff00,
    2'b01 "EXOKAY" -color #ffff00,
    2'b10 "SLVERR" -color #ff0000,
    2'b11 "DECERR" -color #ff0000,
    -default hex
}

radix define ahb_trans {
    2'b00 "IDLE"   -color #00ff00,
    2'b01 "BUSY"   -color #00ff00,
    2'b10 "NONSEQ" -color #00ff00,
    2'b11 "SEQ"    -color #00ff00,
    -default hex
}

radix define ahb_burst {
    3'b000 "SINGLE" -color #00ff00,
    3'b001 "INCR"   -color #00ff00,
    3'b010 "WRAP4"  -color #00ff00,
    3'b011 "INCR4"  -color #00ff00,
    3'b100 "WRAP8"  -color #00ff00,
    3'b101 "INCR8"  -color #00ff00,
    3'b110 "WRAP16" -color #00ff00,
    3'b111 "INCR16" -color #00ff00,
    -default hex
}

radix define ahb_resp {
    1'b0 "OKAY"  -color #00ff00,
    1'b1 "ERROR" -color #ff0000,
    -default hex
}

radix define ahb_dir {
    1'b0 "READ"  -color #00ff00,
    1'b1 "WRITE" -color #00ff00,
    -default hex
}

quietly set wave_pos 0

#-----------------------------------------------------------------------------
# System
#-----------------------------------------------------------------------------
add wave -divider {System}
add wave -color Yellow sim:/bridge_tb_top/clk
add wave -color Yellow sim:/bridge_tb_top/rst_n

#-----------------------------------------------------------------------------
# AXI4 write channels
#-----------------------------------------------------------------------------
add wave -divider {AXI4 Write Address}
add wave -hex             sim:/bridge_tb_top/axi_intf/AWID
add wave -hex             sim:/bridge_tb_top/axi_intf/AWADDR
add wave -unsigned        sim:/bridge_tb_top/axi_intf/AWLEN
add wave -radix transfer_size sim:/bridge_tb_top/axi_intf/AWSIZE
add wave -radix axi_burst sim:/bridge_tb_top/axi_intf/AWBURST
add wave                  sim:/bridge_tb_top/axi_intf/AWLOCK
add wave -hex             sim:/bridge_tb_top/axi_intf/AWCACHE
add wave -hex             sim:/bridge_tb_top/axi_intf/AWPROT
add wave                  sim:/bridge_tb_top/axi_intf/AWVALID
add wave                  sim:/bridge_tb_top/axi_intf/AWREADY

add wave -divider {AXI4 Write Data}
add wave -hex sim:/bridge_tb_top/axi_intf/WDATA
add wave -hex sim:/bridge_tb_top/axi_intf/WSTRB
add wave      sim:/bridge_tb_top/axi_intf/WLAST
add wave      sim:/bridge_tb_top/axi_intf/WVALID
add wave      sim:/bridge_tb_top/axi_intf/WREADY

add wave -divider {AXI4 Write Response}
add wave -hex            sim:/bridge_tb_top/axi_intf/BID
add wave -radix axi_resp sim:/bridge_tb_top/axi_intf/BRESP
add wave                 sim:/bridge_tb_top/axi_intf/BVALID
add wave                 sim:/bridge_tb_top/axi_intf/BREADY

#-----------------------------------------------------------------------------
# AXI4 read channels
#-----------------------------------------------------------------------------
add wave -divider {AXI4 Read Address}
add wave -hex             sim:/bridge_tb_top/axi_intf/ARID
add wave -hex             sim:/bridge_tb_top/axi_intf/ARADDR
add wave -unsigned        sim:/bridge_tb_top/axi_intf/ARLEN
add wave -radix transfer_size sim:/bridge_tb_top/axi_intf/ARSIZE
add wave -radix axi_burst sim:/bridge_tb_top/axi_intf/ARBURST
add wave                  sim:/bridge_tb_top/axi_intf/ARLOCK
add wave -hex             sim:/bridge_tb_top/axi_intf/ARCACHE
add wave -hex             sim:/bridge_tb_top/axi_intf/ARPROT
add wave                  sim:/bridge_tb_top/axi_intf/ARVALID
add wave                  sim:/bridge_tb_top/axi_intf/ARREADY

add wave -divider {AXI4 Read Data}
add wave -hex            sim:/bridge_tb_top/axi_intf/RID
add wave -hex            sim:/bridge_tb_top/axi_intf/RDATA
add wave -radix axi_resp sim:/bridge_tb_top/axi_intf/RRESP
add wave                 sim:/bridge_tb_top/axi_intf/RLAST
add wave                 sim:/bridge_tb_top/axi_intf/RVALID
add wave                 sim:/bridge_tb_top/axi_intf/RREADY

#-----------------------------------------------------------------------------
# AHB-Lite bus
#-----------------------------------------------------------------------------
add wave -divider {AHB-Lite Address and Control}
add wave -radix ahb_trans sim:/bridge_tb_top/ahb_intf/HTRANS
add wave -hex             sim:/bridge_tb_top/ahb_intf/HADDR
add wave -radix ahb_dir   sim:/bridge_tb_top/ahb_intf/HWRITE
add wave -radix transfer_size sim:/bridge_tb_top/ahb_intf/HSIZE
add wave -radix ahb_burst sim:/bridge_tb_top/ahb_intf/HBURST
add wave -hex             sim:/bridge_tb_top/ahb_intf/HPROT
add wave                  sim:/bridge_tb_top/ahb_intf/HMASTLOCK

add wave -divider {AHB-Lite Data and Response}
add wave -hex            sim:/bridge_tb_top/ahb_intf/HWDATA
add wave -hex            sim:/bridge_tb_top/ahb_intf/HRDATA
add wave                 sim:/bridge_tb_top/ahb_intf/HREADY
add wave -radix ahb_resp sim:/bridge_tb_top/ahb_intf/HRESP

#-----------------------------------------------------------------------------
# Bridge control
#-----------------------------------------------------------------------------
add wave -divider {Bridge Internal Control}
add wave -hex sim:/bridge_tb_top/dut/axi_address
add wave      sim:/bridge_tb_top/dut/ahb_rd_request
add wave      sim:/bridge_tb_top/dut/ahb_wr_request
add wave      sim:/bridge_tb_top/dut/send_ahb_wr
add wave      sim:/bridge_tb_top/dut/send_bresp
add wave      sim:/bridge_tb_top/dut/send_rvalid
add wave      sim:/bridge_tb_top/dut/send_rlast
add wave      sim:/bridge_tb_top/dut/timeout_s
add wave      sim:/bridge_tb_top/dut/timeout_inprogress

configure wave -namecolwidth 260
configure wave -valuecolwidth 120
configure wave -timelineunits ns
update
WaveRestoreZoom {0 ns} {1000 ns}