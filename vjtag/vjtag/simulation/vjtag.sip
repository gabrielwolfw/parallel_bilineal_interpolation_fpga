set_global_assignment -entity "vjtag" -library "lib_vjtag" -name IP_TOOL_NAME "Qsys"
set_global_assignment -entity "vjtag" -library "lib_vjtag" -name IP_TOOL_VERSION "18.1"
set_global_assignment -entity "vjtag" -library "lib_vjtag" -name IP_TOOL_ENV "Qsys"
set_global_assignment -library "lib_vjtag" -name SPD_FILE [file join $::quartus(sip_path) "../vjtag.spd"]
set_global_assignment -library "lib_vjtag" -name MISC_FILE [file join $::quartus(sip_path) "../../vjtag.qsys"]

set_global_assignment -library "lib_vjtag" -name MISC_FILE [file join $::quartus(sip_path) "vjtag.v"]
set_global_assignment -library "lib_vjtag" -name MISC_FILE [file join $::quartus(sip_path) "submodules/sld_virtual_jtag.v"]
