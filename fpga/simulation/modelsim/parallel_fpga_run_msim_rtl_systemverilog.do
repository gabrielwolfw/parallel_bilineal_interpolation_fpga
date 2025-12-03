transcript on
if {[file exists rtl_work]} {
	vdel -lib rtl_work -all
}
vlib rtl_work
vmap work rtl_work

vlib dsa_jtag_system
vmap dsa_jtag_system dsa_jtag_system
vlog -vlog01compat -work dsa_jtag_system +incdir+C:/Users/ederv/Documents/TEC/Arqui2/p21/parallel_bilineal_interpolation_fpga/fpga/dsa_jtag_system/synthesis/submodules {C:/Users/ederv/Documents/TEC/Arqui2/p21/parallel_bilineal_interpolation_fpga/fpga/dsa_jtag_system/synthesis/submodules/dsa_jtag_system_jtag_uart.v}
vlog -sv -work work +incdir+C:/Users/ederv/Documents/TEC/Arqui2/p21/parallel_bilineal_interpolation_fpga/fpga {C:/Users/ederv/Documents/TEC/Arqui2/p21/parallel_bilineal_interpolation_fpga/fpga/dsa_datapath.sv}
vlog -sv -work work +incdir+C:/Users/ederv/Documents/TEC/Arqui2/p21/parallel_bilineal_interpolation_fpga/fpga {C:/Users/ederv/Documents/TEC/Arqui2/p21/parallel_bilineal_interpolation_fpga/fpga/dsa_datapath_simd.sv}
vlog -sv -work work +incdir+C:/Users/ederv/Documents/TEC/Arqui2/p21/parallel_bilineal_interpolation_fpga/fpga {C:/Users/ederv/Documents/TEC/Arqui2/p21/parallel_bilineal_interpolation_fpga/fpga/dsa_pixel_fetch_sequential.sv}
vlog -sv -work work +incdir+C:/Users/ederv/Documents/TEC/Arqui2/p21/parallel_bilineal_interpolation_fpga/fpga {C:/Users/ederv/Documents/TEC/Arqui2/p21/parallel_bilineal_interpolation_fpga/fpga/dsa_pixel_fetch_simd.sv}
vlog -sv -work work +incdir+C:/Users/ederv/Documents/TEC/Arqui2/p21/parallel_bilineal_interpolation_fpga/fpga {C:/Users/ederv/Documents/TEC/Arqui2/p21/parallel_bilineal_interpolation_fpga/fpga/dsa_pixel_fetch_unified.sv}
vlog -sv -work work +incdir+C:/Users/ederv/Documents/TEC/Arqui2/p21/parallel_bilineal_interpolation_fpga/fpga {C:/Users/ederv/Documents/TEC/Arqui2/p21/parallel_bilineal_interpolation_fpga/fpga/dsa_control_fsm_simd.sv}
vlog -sv -work work +incdir+C:/Users/ederv/Documents/TEC/Arqui2/p21/parallel_bilineal_interpolation_fpga/fpga {C:/Users/ederv/Documents/TEC/Arqui2/p21/parallel_bilineal_interpolation_fpga/fpga/dsa_control_fsm_sequential.sv}
vlog -sv -work work +incdir+C:/Users/ederv/Documents/TEC/Arqui2/p21/parallel_bilineal_interpolation_fpga/fpga {C:/Users/ederv/Documents/TEC/Arqui2/p21/parallel_bilineal_interpolation_fpga/fpga/dsa_mem_banked.sv}
vlog -sv -work work +incdir+C:/Users/ederv/Documents/TEC/Arqui2/p21/parallel_bilineal_interpolation_fpga/fpga {C:/Users/ederv/Documents/TEC/Arqui2/p21/parallel_bilineal_interpolation_fpga/fpga/dsa_top.sv}

vlog -sv -work work +incdir+C:/Users/ederv/Documents/TEC/Arqui2/p21/parallel_bilineal_interpolation_fpga/fpga {C:/Users/ederv/Documents/TEC/Arqui2/p21/parallel_bilineal_interpolation_fpga/fpga/dsa_top_tb.sv}

vsim -t 1ps -L altera_ver -L lpm_ver -L sgate_ver -L altera_mf_ver -L altera_lnsim_ver -L cyclonev_ver -L cyclonev_hssi_ver -L cyclonev_pcie_hip_ver -L rtl_work -L work -L dsa_jtag_system -voptargs="+acc"  dsa_top_tb

add wave *
view structure
view signals
run -all
