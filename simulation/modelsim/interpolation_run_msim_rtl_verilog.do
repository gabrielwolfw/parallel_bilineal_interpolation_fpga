transcript on
if {[file exists rtl_work]} {
	vdel -lib rtl_work -all
}
vlib rtl_work
vmap work rtl_work

vlog -sv -work work +incdir+C:/Users/Admin/OneDrive/Desktop/parallel_bilineal_interpolation_fpga/fpga {C:/Users/Admin/OneDrive/Desktop/parallel_bilineal_interpolation_fpga/fpga/dsa_datapath.sv}

vlog -sv -work work +incdir+C:/Users/Admin/OneDrive/Desktop/parallel_bilineal_interpolation_fpga/fpga {C:/Users/Admin/OneDrive/Desktop/parallel_bilineal_interpolation_fpga/fpga/testbench.sv}

vsim -t 1ps -L altera_ver -L lpm_ver -L sgate_ver -L altera_mf_ver -L altera_lnsim_ver -L cyclonev_ver -L cyclonev_hssi_ver -L cyclonev_pcie_hip_ver -L rtl_work -L work -voptargs="+acc"  testbench

add wave *
view structure
view signals
run -all
