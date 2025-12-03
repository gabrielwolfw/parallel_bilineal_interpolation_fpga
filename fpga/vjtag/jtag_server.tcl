# jtag_server.tcl - TCP <-> JTAG bridge for DE1-SoC

set VJTAG_DATA_WIDTH 8 ; # Default value
set server_port_number 2540 ; # Default port

# --- Command line parsing: width and port ---
if {$argc > 0} {
    set arg1 [lindex $argv 0]
    if {[string is integer -strict $arg1] && $arg1 > 0} {
        set VJTAG_DATA_WIDTH $arg1
    }
}
if {$argc > 1} {
    set arg2 [lindex $argv 1]
    if {[string is integer -strict $arg2] && $arg2 > 0} {
        set server_port_number $arg2
    }
}
puts "|INFO| VJTAG_DATA_WIDTH=$VJTAG_DATA_WIDTH, TCP PORT=$server_port_number"

# --- Hardware detection ---
global usbblaster_name
global test_device
# --- USB Blaster Detection ---
foreach hardware_name [get_hardware_names] {
    puts "|DEBUG| hardware_name = $hardware_name|"
    if { [string match "DE-SoC*" $hardware_name] } {
        set usbblaster_name $hardware_name
        puts "|INFO| Select JTAG chain connected to $usbblaster_name"
        foreach device_name [get_device_names -hardware_name $usbblaster_name] {
            if { [string match "@2*" $device_name] } {
                puts "|DEBUG| device name = $device_name|"
                set test_device $device_name
                puts "|INFO| Selected device: $test_device.\n"
            }
        }
    }
}
if {![info exists usbblaster_name]} {
    puts "|ERROR| No USB-Blaster found."
    exit 1
}
if {![info exists test_device]} {
    puts "|ERROR| No JTAG device found."
    exit 1
}

# --- JTAG operations ---
proc openport {} {
    global usbblaster_name test_device
    open_device -hardware_name $usbblaster_name -device_name $test_device
}
proc closeport { } {
    catch {device_unlock}
    catch {close_device}
}

# --- JTAG IR states ---
set IR_BYPASS    0
set IR_WRITE     1
set IR_READ      2
set IR_SET_ADDR  3

# --- Server functions must be defined BEFORE they're called! ---
proc Start_Server {port_num} {
    set s [socket -server ConnAccept $port_num]
    puts "Started Socket Server on port - $port_num"
    vwait forever
}

proc ConnAccept {sock addr client_port} {
    global conn
    puts "Accept $sock from $addr port $client_port"
    set conn(addr,$sock) [list $addr $client_port]
    fconfigure $sock -buffering line
    fileevent $sock readable [list IncomingData $sock]
}

proc IncomingData {sock} {
    global conn
    global VJTAG_DATA_WIDTH
    global IR_BYPASS IR_WRITE IR_READ IR_SET_ADDR

    if {[eof $sock] || [catch {gets $sock line}]} {
        close $sock
        unset conn(addr,$sock)
    } else {
        set trimmed_line [string trim $line]
        
        # Separar el comando y los datos
        set parts [split $trimmed_line " "]
        set cmd [string toupper [lindex $parts 0]]
        
        puts "|DEBUG TCL| Received command: $cmd"
        
        switch -exact -- $cmd {
            "READ" {
                # Soporta tanto "READ" como "READ <address>"
                if {[llength $parts] == 2} {
                    set addr [lindex $parts 1]
                    # Validar formato binario de la dirección
                    if {[string length $addr] == $VJTAG_DATA_WIDTH && [regexp "^\[01\]\{$VJTAG_DATA_WIDTH\}$" $addr]} {
                        set response [read_from_fpga_address $addr]
                        puts -nonewline $sock $response
                        flush $sock
                    } else {
                        puts "|ERROR TCL| Invalid READ address format: $addr"
                    }
                } else {
                    # Si solo es "READ", usa la dirección ya seteada
                    set response [read_from_fpga]
                    puts -nonewline $sock $response
                    flush $sock
                }
            }
            "WRITE" {
                set data [lindex $parts 1]
                if {[string length $data] == $VJTAG_DATA_WIDTH && 
                    [regexp "^\[01\]\{$VJTAG_DATA_WIDTH\}$" $data]} {
                    transmit_to_fpga $data $IR_WRITE
                } else {
                    puts "|ERROR TCL| Invalid WRITE data format: $data"
                }
            }
            "SETADDR" {
                set addr [lindex $parts 1]
                if {[string length $addr] == $VJTAG_DATA_WIDTH && 
                    [regexp "^\[01\]\{$VJTAG_DATA_WIDTH\}$" $addr]} {
                    transmit_to_fpga $addr $IR_SET_ADDR
                } else {
                    puts "|ERROR TCL| Invalid SETADDR format: $addr"
                }
            }
            default {
                puts "|WARNING| Unknown command: '$trimmed_line'"
            }
        }
    }
}

proc transmit_to_fpga {send_data_binary_str {ir_value 1}} {
    global VJTAG_DATA_WIDTH
    global IR_BYPASS
    
    # Debug: Muestra el string binario recibido
    puts "|DEBUG TCL| Received binary string: $send_data_binary_str"
    puts "|DEBUG TCL| IR Value: $ir_value"
    
    # Convierte a decimal y muestra
    if {[regexp {^[01]+$} $send_data_binary_str]} {
        set decimal_value 0
        set power 1
        for {set i [expr {[string length $send_data_binary_str] - 1}]} {$i >= 0} {incr i -1} {
            if {[string index $send_data_binary_str $i] == "1"} {
                incr decimal_value $power
            }
            set power [expr {$power * 2}]
        }
        puts "|DEBUG TCL| Decimal value: $decimal_value"
        puts "|DEBUG TCL| Hex value: [format "0x%X" $decimal_value]"
    } else {
        puts "|ERROR TCL| Invalid binary string received"
        return
    }
    
    openport
    device_lock -timeout 10000
    device_virtual_ir_shift -instance_index 0 -ir_value $ir_value -no_captured_ir_value
    device_virtual_dr_shift -dr_value $send_data_binary_str -instance_index 0 -length $VJTAG_DATA_WIDTH -no_captured_dr_value
    device_virtual_ir_shift -instance_index 0 -ir_value $IR_BYPASS -no_captured_ir_value
    closeport
}

proc read_from_fpga {} {
    global VJTAG_DATA_WIDTH
    global IR_READ IR_BYPASS
    
    openport
    device_lock -timeout 10000
    device_virtual_ir_shift -instance_index 0 -ir_value $IR_READ -no_captured_ir_value
    set tdo_hex_value [device_virtual_dr_shift -instance_index 0 -length $VJTAG_DATA_WIDTH -value_in_hex]
    device_virtual_ir_shift -instance_index 0 -ir_value $IR_BYPASS -no_captured_ir_value
    closeport
    return "$tdo_hex_value\n"
}

# Nueva función: read_from_fpga_address
proc read_from_fpga_address {addr_bin_str} {
    global VJTAG_DATA_WIDTH
    global IR_SET_ADDR IR_READ IR_BYPASS
    # Primero, setea la dirección usando IR_SET_ADDR
    openport
    device_lock -timeout 10000
    # Setea la dirección
    device_virtual_ir_shift -instance_index 0 -ir_value $IR_SET_ADDR -no_captured_ir_value
    device_virtual_dr_shift -dr_value $addr_bin_str -instance_index 0 -length $VJTAG_DATA_WIDTH -no_captured_dr_value
    # Ahora, ejecuta un IR_READ y lee el valor
    device_virtual_ir_shift -instance_index 0 -ir_value $IR_READ -no_captured_ir_value
    set tdo_hex_value [device_virtual_dr_shift -instance_index 0 -length $VJTAG_DATA_WIDTH -value_in_hex]
    # Regresa a bypass
    device_virtual_ir_shift -instance_index 0 -ir_value $IR_BYPASS -no_captured_ir_value
    closeport
    return "$tdo_hex_value\n"
}

# --- LA ÚNICA LLAMADA AL FINAL ---
Start_Server $server_port_number