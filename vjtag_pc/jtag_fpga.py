# jtag_fpga.py - JTAG-FPGA Communication Client
# Compatible with jtag_server.tcl (binary protocol)
import socket
import time
import argparse
import os 
try:
    import readline 
except ImportError:
    readline = None  # Windows compatibility
import atexit 

# --- START: Verbosity Levels ---
VERBOSE_LEVEL_QUIET = 0
VERBOSE_LEVEL_NORMAL = 1 # Default: INFO, RESULT, WARNING, ERROR
VERBOSE_LEVEL_DEBUG = 2  # All messages including DEBUG
# --- END: Verbosity Levels ---

# These will be set in main() after parsing arguments
DATA_WIDTH = 8
ADDR_WIDTH = 16  # Para SETADDR (dirección completa de 16 bits - 64KB direccionable)
MAX_VAL = (1 << DATA_WIDTH) - 1
MAX_ADDR = (1 << ADDR_WIDTH) - 1
HEX_PADDING = DATA_WIDTH // 4
VERBOSITY_LEVEL = VERBOSE_LEVEL_NORMAL # Default, will be updated by argparse

HOST = 'localhost'
PORT = 2540
SOCKET_TIMEOUT = 10.0

HISTORY_FILE = os.path.expanduser("~/.jtag_fpga_history")

def load_history():
    if readline and hasattr(readline, "read_history_file"):
        try:
            readline.read_history_file(HISTORY_FILE)
        except FileNotFoundError:
            pass # No history file yet
        except Exception:
            pass # Other error reading history

def save_history():
    if readline and hasattr(readline, "write_history_file"):
        try:
            readline.write_history_file(HISTORY_FILE)
        except Exception:
            pass # Error saving history

if readline:
    atexit.register(save_history)

# --- START: Conditional Print Function ---
def print_message(level, message):
    """Prints a message if the current verbosity level is high enough."""
    global VERBOSITY_LEVEL
    if level <= VERBOSITY_LEVEL:
        print(message)
# --- END: Conditional Print Function ---

def open_connection(host_addr, server_port):
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(SOCKET_TIMEOUT)
        s.connect((host_addr, server_port))
        print_message(VERBOSE_LEVEL_NORMAL, f"|INFO| Connected to server {host_addr}:{server_port}")
        return s
    except socket.timeout:
        print_message(VERBOSE_LEVEL_QUIET, f"|ERROR| Connection to {host_addr}:{server_port} timed out.") # ERROR always prints
        return None
    except ConnectionRefusedError:
        print_message(VERBOSE_LEVEL_QUIET, f"|ERROR| Connection to {host_addr}:{server_port} refused. Is the TCL server running?")
        return None
    except Exception as e:
        print_message(VERBOSE_LEVEL_QUIET, f"|ERROR| Could not connect to server: {e}")
        return None

def write_value_to_fpga(conn, int_value_to_write):
    """Escribe un valor de 8 bits a la memoria FPGA en la dirección actual."""
    if conn is None:
        print_message(VERBOSE_LEVEL_QUIET, "|ERROR| No connection to server. Cannot write.")
        return
    try:
        binary_normal = format(int_value_to_write, f'0{DATA_WIDTH}b')
        print_message(VERBOSE_LEVEL_DEBUG, f"|DEBUG| Value to write: {int_value_to_write} (0x{int_value_to_write:02X})")
        print_message(VERBOSE_LEVEL_DEBUG, f"|DEBUG| Binary value: {binary_normal}")
        
        # Enviar comando WRITE seguido del valor en binario
        request = f"WRITE {binary_normal}\n"
        print_message(VERBOSE_LEVEL_DEBUG, f"|DEBUG| Sending to TCL server: {request.strip()}")
        conn.sendall(request.encode())
        
        time.sleep(0.05)  # Pequeña pausa para estabilidad
        print_message(VERBOSE_LEVEL_NORMAL, f"|INFO| Successfully wrote 0x{int_value_to_write:02X} to memory")
        
    except socket.timeout:
        print_message(VERBOSE_LEVEL_QUIET, "|ERROR| Socket timeout during write operation.")
    except Exception as e:
        print_message(VERBOSE_LEVEL_QUIET, f"|ERROR| Failed to send data: {e}")

def read_value_from_fpga(conn):
    """Lee un valor de 8 bits desde la dirección actual de memoria FPGA."""
    if conn is None:
        print_message(VERBOSE_LEVEL_QUIET, "|ERROR| No connection to server. Cannot read.")
        return None
    try:
        request = "READ\n"
        print_message(VERBOSE_LEVEL_DEBUG, f"|DEBUG| Python sending read request: {request.strip()}")
        conn.sendall(request.encode())
        
        response_bytes = b''
        conn.settimeout(SOCKET_TIMEOUT) 
        while True:
            try:
                chunk = conn.recv(1) 
                if not chunk: 
                    print_message(VERBOSE_LEVEL_QUIET, "|ERROR| Connection closed by server while waiting for read response.")
                    return None
                response_bytes += chunk
                if chunk == b'\n':
                    break
            except socket.timeout:
                print_message(VERBOSE_LEVEL_QUIET, f"|ERROR| Socket timeout while waiting for read response.")
                if response_bytes:
                    print_message(VERBOSE_LEVEL_NORMAL, "|WARNING| Partial response received before timeout.")
                    break 
                return None
        
        response_hex = response_bytes.decode().strip()
        print_message(VERBOSE_LEVEL_DEBUG, f"|DEBUG| Python received hex response: '{response_hex}'")
        if not response_hex:
            print_message(VERBOSE_LEVEL_QUIET, "|ERROR| Received empty or incomplete response from server.")
            return None
        try:
            int_value = int(response_hex, 16)
            return int_value
        except ValueError:
            print_message(VERBOSE_LEVEL_QUIET, f"|ERROR| Could not parse hex string '{response_hex}' to integer.")
            return None
    except socket.timeout: 
        print_message(VERBOSE_LEVEL_QUIET, "|ERROR| Socket timeout during read operation.")
        return None
    except Exception as e:
        print_message(VERBOSE_LEVEL_QUIET, f"|ERROR| Failed to read data: {e}")
        return None

def read_value_from_fpga_addr(conn, address):
    """Lee un valor desde una dirección específica (hace SETADDR + READ automáticamente)."""
    if conn is None:
        print_message(VERBOSE_LEVEL_QUIET, "|ERROR| No connection to server. Cannot read.")
        return None
    
    # Primero setear la dirección
    if not set_address_to_fpga(conn, address):
        return None
    
    time.sleep(0.05)  # Pausa para que la FPGA actualice
    
    # Luego leer el valor
    return read_value_from_fpga(conn)

def parse_integer_argument(arg_str, arg_name="argument"):
    if arg_str is None:
        return None
    try:
        return int(arg_str, 0) 
    except ValueError:
        print_message(VERBOSE_LEVEL_QUIET, f"|ERROR| Invalid format for {arg_name}: '{arg_str}'. Must be an integer.")
        return None

def set_address_to_fpga(conn, address):
    """Establece la dirección de memoria actual en la FPGA (16 bits - dirección completa)."""
    if conn is None:
        print_message(VERBOSE_LEVEL_QUIET, "|ERROR| No connection to server. Cannot set address.")
        return False
    try:
        # IMPORTANTE: El servidor TCL ahora espera ADDR_WIDTH bits (16 bits) para SETADDR
        addr_16bit = address & 0xFFFF  # Máscara de 16 bits (64KB)
        binary_normal = format(addr_16bit, f'0{ADDR_WIDTH}b')  # 16 bits
        
        print_message(VERBOSE_LEVEL_DEBUG, f"|DEBUG| Setting address: {address} -> {addr_16bit} (16-bit complete)")
        print_message(VERBOSE_LEVEL_DEBUG, f"|DEBUG| Address binary ({ADDR_WIDTH} bits): {binary_normal}")
        
        # Enviar comando SETADDR seguido de la dirección en binario (16 bits completos)
        request = f"SETADDR {binary_normal}\n"
        print_message(VERBOSE_LEVEL_DEBUG, f"|DEBUG| Sending to TCL server: {request.strip()}")
        conn.sendall(request.encode())
        
        time.sleep(0.05)  # Pequeña pausa para estabilidad
        print_message(VERBOSE_LEVEL_NORMAL, f"|INFO| Address set to 0x{addr_16bit:04X}")
        return True
        
    except socket.timeout:
        print_message(VERBOSE_LEVEL_QUIET, "|ERROR| Socket timeout during set address operation.")
        return False
    except Exception as e:
        print_message(VERBOSE_LEVEL_QUIET, f"|ERROR| Failed to set address: {e}")
        return False

def main_loop(conn):
    print_message(VERBOSE_LEVEL_NORMAL, "\n=== JTAG-FPGA Interactive Console ===")
    print_message(VERBOSE_LEVEL_NORMAL, "Available commands:")
    print_message(VERBOSE_LEVEL_NORMAL, f"  setaddr <address>     - Set memory address (0x0000-0x{MAX_ADDR:04X})")
    print_message(VERBOSE_LEVEL_NORMAL, "  write <value>         - Write 8-bit value to current address")
    print_message(VERBOSE_LEVEL_NORMAL, "  read                  - Read 8-bit value from current address")
    print_message(VERBOSE_LEVEL_NORMAL, "  readaddr <address>    - Read from specific address (SETADDR+READ)")
    print_message(VERBOSE_LEVEL_NORMAL, "  verbose <quiet|normal|debug> - Change verbosity level")
    print_message(VERBOSE_LEVEL_NORMAL, "  history               - Show command history")
    print_message(VERBOSE_LEVEL_NORMAL, "  help                  - Show this help")
    print_message(VERBOSE_LEVEL_NORMAL, "  exit                  - Close connection and quit")
    print_message(VERBOSE_LEVEL_NORMAL, f"\nNote: Data values 0-{MAX_VAL} (0x00-0x{MAX_VAL:02X}), addresses 0x0000-0x{MAX_ADDR:04X} (64KB)")
    print_message(VERBOSE_LEVEL_NORMAL, "Tip: Use hex format 0xNNNNN for addresses, 0xNN for values\n")

    try:
        while True:
            user_input = input(f"JTAG-{DATA_WIDTH}bit> ").strip()
            parts = user_input.split()

            if not parts:
                continue

            command = parts[0].lower()

            if command == 'exit' or command == 'quit':
                print_message(VERBOSE_LEVEL_NORMAL, "|INFO| Closing connection...")
                break
            elif command == 'help' or command == '?':
                print_message(VERBOSE_LEVEL_NORMAL, "\n=== Available Commands ===")
                print_message(VERBOSE_LEVEL_NORMAL, "  setaddr <addr>   : Set memory address")
                print_message(VERBOSE_LEVEL_NORMAL, "  write <value>    : Write to current address")
                print_message(VERBOSE_LEVEL_NORMAL, "  read             : Read from current address")
                print_message(VERBOSE_LEVEL_NORMAL, "  readaddr <addr>  : Read from specific address")
                print_message(VERBOSE_LEVEL_NORMAL, "  verbose <level>  : Set verbosity (quiet/normal/debug)")
                print_message(VERBOSE_LEVEL_NORMAL, "  history          : Show command history")
                print_message(VERBOSE_LEVEL_NORMAL, "  exit             : Quit\n")
            elif command == 'setaddr':
                if len(parts) == 2:
                    addr_str = parts[1]
                    address = parse_integer_argument(addr_str, "address")
                    if address is not None:
                        if 0 <= address <= MAX_ADDR:
                            print_message(VERBOSE_LEVEL_NORMAL, 
                                f"|INFO| Setting address to: {address} (0x{address:04X})")
                            set_address_to_fpga(conn, address)
                        else:
                            print_message(VERBOSE_LEVEL_QUIET, 
                                f"|ERROR| Address ({address}) out of {ADDR_WIDTH}-bit range (0-{MAX_ADDR}).")
                else:
                    print_message(VERBOSE_LEVEL_QUIET, "|ERROR| Usage: setaddr <address>")

            elif command == 'write':
                if len(parts) == 2:
                    value_str = parts[1]
                    value_to_write = parse_integer_argument(value_str, "value")
                    if value_to_write is not None:
                        if 0 <= value_to_write <= MAX_VAL:
                            print_message(VERBOSE_LEVEL_NORMAL, 
                                f"|INFO| Writing value: {value_to_write} (0x{value_to_write:0{HEX_PADDING}x})")
                            write_value_to_fpga(conn, value_to_write)
                        else:
                            print_message(VERBOSE_LEVEL_QUIET, 
                                f"|ERROR| Value ({value_to_write}) out of {DATA_WIDTH}-bit range (0-{MAX_VAL}).")
                else:
                    print_message(VERBOSE_LEVEL_QUIET, "|ERROR| Usage: write <value>")
            elif command == 'read':
                if len(parts) == 1:
                    print_message(VERBOSE_LEVEL_NORMAL, "|INFO| Reading value at current address (set by setaddr).")
                    value = read_value_from_fpga(conn)
                    if value is not None:
                        print_message(VERBOSE_LEVEL_NORMAL, f"|RESULT| Read value: {value} (0x{value:0{HEX_PADDING}x})")
                else:
                    print_message(VERBOSE_LEVEL_QUIET, "|ERROR| Usage: read")
            elif command == 'readaddr':
                if len(parts) == 2:
                    addr_str = parts[1]
                    address = parse_integer_argument(addr_str, "address")
                    if address is not None:
                        if 0 <= address <= MAX_ADDR:
                            print_message(VERBOSE_LEVEL_NORMAL, f"|INFO| Reading from address: {address} (0x{address:04X})")
                            value = read_value_from_fpga_addr(conn, address)
                            if value is not None:
                                print_message(VERBOSE_LEVEL_NORMAL, f"|RESULT| Read value: {value} (0x{value:0{HEX_PADDING}x})")
                        else:
                            print_message(VERBOSE_LEVEL_QUIET, 
                                f"|ERROR| Address ({address}) out of {ADDR_WIDTH}-bit range (0-{MAX_ADDR}).")
                else:
                    print_message(VERBOSE_LEVEL_QUIET, "|ERROR| Usage: readaddr <address>")
            elif command == 'verbose':
                if len(parts) == 2:
                    level = parts[1].lower()
                    if level == "quiet":
                        globals()["VERBOSITY_LEVEL"] = VERBOSE_LEVEL_QUIET
                        print_message(VERBOSE_LEVEL_NORMAL, "|INFO| Verbosity set to QUIET")
                    elif level == "normal":
                        globals()["VERBOSITY_LEVEL"] = VERBOSE_LEVEL_NORMAL
                        print_message(VERBOSE_LEVEL_NORMAL, "|INFO| Verbosity set to NORMAL")
                    elif level == "debug":
                        globals()["VERBOSITY_LEVEL"] = VERBOSE_LEVEL_DEBUG
                        print_message(VERBOSE_LEVEL_NORMAL, "|INFO| Verbosity set to DEBUG")
                    else:
                        print_message(VERBOSE_LEVEL_QUIET, "|ERROR| Usage: verbose <quiet|normal|debug>")
                else:
                    print_message(VERBOSE_LEVEL_QUIET, "|ERROR| Usage: verbose <quiet|normal|debug>")
            elif command == 'history':
                # Show command history (if available)
                if readline:
                    try:
                        hist_len = readline.get_current_history_length()
                        if hist_len > 0:
                            print_message(VERBOSE_LEVEL_NORMAL, "\n=== Command History ===")
                            for i in range(1, hist_len + 1):
                                print_message(VERBOSE_LEVEL_NORMAL, f"  {i}: {readline.get_history_item(i)}")
                            print_message(VERBOSE_LEVEL_NORMAL, "")
                        else:
                            print_message(VERBOSE_LEVEL_NORMAL, "|INFO| No history available yet.")
                    except Exception as e:
                        print_message(VERBOSE_LEVEL_QUIET, f"|ERROR| Unable to display history: {e}")
                else:
                    print_message(VERBOSE_LEVEL_QUIET, "|ERROR| readline not available (try: pip install pyreadline3)")
            else:
                print_message(VERBOSE_LEVEL_QUIET, f"|ERROR| Unknown command: {command}. Type 'help' for available commands.")
        
    finally:
        print_message(VERBOSE_LEVEL_NORMAL, "|INFO| Exiting main loop. Closing connection.")
        conn.close()
        save_history()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=f"JTAG Client for FPGA communication.")
    parser.add_argument(
        "-dw", "--data_width", 
        type=int, 
        default=8, 
        choices=[8, 16, 32, 64],
        help="Specify the data width in bits for JTAG operations (default: 8)."
    )
    # Add verbosity arguments
    parser.add_argument(
        "-q", "--quiet",
        action="store_const", const=VERBOSE_LEVEL_QUIET, dest="verbosity",
        help="Set verbosity to quiet (only errors)."
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_const", const=VERBOSE_LEVEL_DEBUG, dest="verbosity",
        help="Set verbosity to debug (all messages)."
    )
    parser.set_defaults(verbosity=VERBOSE_LEVEL_NORMAL) # Default if no -q or -v

    args = parser.parse_args()

    DATA_WIDTH = args.data_width
    VERBOSITY_LEVEL = args.verbosity # Set global verbosity from parsed args
    MAX_VAL = (1 << DATA_WIDTH) - 1
    HEX_PADDING = DATA_WIDTH // 4
    
    print_message(VERBOSE_LEVEL_NORMAL, "=" * 60)
    print_message(VERBOSE_LEVEL_NORMAL, "  JTAG-FPGA Memory Communication Client")
    print_message(VERBOSE_LEVEL_NORMAL, "=" * 60)
    print_message(VERBOSE_LEVEL_NORMAL, f"|CONFIG| Data width: {DATA_WIDTH} bits")
    print_message(VERBOSE_LEVEL_NORMAL, f"|CONFIG| Address width: {ADDR_WIDTH} bits (64KB addressable)")
    verbosity_str_map = {VERBOSE_LEVEL_QUIET: "QUIET", VERBOSE_LEVEL_NORMAL: "NORMAL", VERBOSE_LEVEL_DEBUG: "DEBUG"}
    print_message(VERBOSE_LEVEL_NORMAL, f"|CONFIG| Verbosity: {verbosity_str_map.get(VERBOSITY_LEVEL, 'UNKNOWN')}")
    print_message(VERBOSE_LEVEL_NORMAL, f"|CONFIG| Target: {HOST}:{PORT}")
    print_message(VERBOSE_LEVEL_NORMAL, "=" * 60 + "\n")

    if readline:
        print_message(VERBOSE_LEVEL_DEBUG, "|DEBUG| Readline available - command history enabled")
        load_history()
    elif os.name == 'nt':
        print_message(VERBOSE_LEVEL_NORMAL, "|TIP| Install pyreadline3 for command history: pip install pyreadline3")

    conn = open_connection(HOST, PORT)
    if conn is None:
        print_message(VERBOSE_LEVEL_QUIET, "|FATAL| Exiting due to connection failure.")
        exit(1) 
    
    main_loop(conn)