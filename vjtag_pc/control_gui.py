import tkinter as tk
from tkinter import filedialog, messagebox
import socket

# --- JTAG Communication Functions ---
HOST = 'localhost'
PORT = 2540
SOCKET_TIMEOUT = 10.0
DATA_WIDTH = 8
ADDR_WIDTH = 16
MAX_VAL = (1 << DATA_WIDTH) - 1
MAX_ADDR = (1 << ADDR_WIDTH) - 1

def open_connection():
    """Open connection to the server."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(SOCKET_TIMEOUT)
        s.connect((HOST, PORT))
        return s
    except Exception as e:
        messagebox.showerror("Error", f"Error connecting to server: {e}")
        return None

def set_address_to_fpga(conn, address):
    """Send SETADDR command to server."""
    try:
        binary_address = format(address, f'0{ADDR_WIDTH}b')
        request = f"SETADDR {binary_address}\n"
        conn.sendall(request.encode())
    except Exception as e:
        messagebox.showerror("Error", f"Error setting address: {e}")

def write_value_to_fpga(conn, value):
    """Send WRITE command to server."""
    try:
        binary_value = format(value, f'0{DATA_WIDTH}b')
        request = f"WRITE {binary_value}\n"
        conn.sendall(request.encode())
    except Exception as e:
        messagebox.showerror("Error", f"Error writing value: {e}")

def read_value_from_fpga(conn):
    try:
        request = "READ\n"
        conn.sendall(request.encode())
        
        response_bytes = b''
        conn.settimeout(SOCKET_TIMEOUT) 
        while True:
            try:
                chunk = conn.recv(1) 
                if not chunk: 
                    print("|ERROR| Connection closed by server while waiting for read response.")
                    return None
                response_bytes += chunk
                if chunk == b'\n':
                    break
            except socket.timeout:
                print("|ERROR| Socket timeout while waiting for full {DATA_WIDTH}-bit read response line.")
                if response_bytes:
                    break 
                return None
        
        response_hex = response_bytes.decode().strip()
        if not response_hex:
            return None
        try:
            int_value = int(response_hex, 16)
            return int_value
        except ValueError:
            print("|ERROR| Could not parse {DATA_WIDTH}-bit hex string '{response_hex}' to integer.")
            return None
    except socket.timeout: 
        print( "|ERROR| Socket timeout during sending read command.")
        return None
    except Exception as e:
        print("|ERROR| Failed to read data: {e}")
        return None

# --- GUI Functions ---
def browse_file():
    """Browse for a file and update the entry."""
    filepath = filedialog.askopenfilename(filetypes=[("Text Files", "*.txt")])
    if filepath:
        file_path_var.set(filepath)

def write_from_file():
    """Write values from file to RAM."""
    filepath = file_path_var.get()
    if not filepath:
        messagebox.showerror("Error", "Please select a file.")
        return

    try:
        with open(filepath, 'r') as file:
            lines = file.readlines()
        
        conn = open_connection()
        if not conn:
            return

        address = 0
        for line in lines:
            line = line.strip()
            if not line.isdigit():
                messagebox.showerror("Error", f"Invalid number in file: {line}")
                conn.close()
                return
            
            value = int(line)
            if value > MAX_VAL:
                messagebox.showerror("Error", f"Value {value} exceeds maximum allowed ({MAX_VAL}).")
                conn.close()
                return
            
            set_address_to_fpga(conn, address)
            write_value_to_fpga(conn, value)
            address += 1
        
        conn.close()
        messagebox.showinfo("Success", "Values successfully written to RAM.")
    
    except Exception as e:
        messagebox.showerror("Error", f"Error reading file: {e}")

def write_manual():
    """Write a value to a specific address manually."""
    address_str = address_var.get()
    value_str = value_var.get()
    
    if not address_str.isdigit():
        messagebox.showerror("Error", "Address must be a valid integer.")
        return
    
    if not value_str.isdigit():
        messagebox.showerror("Error", "Value must be a valid integer.")
        return
    
    address = int(address_str)
    value = int(value_str)
    
    if address > MAX_ADDR:
        messagebox.showerror("Error", f"Address {address} exceeds maximum allowed ({MAX_ADDR}).")
        return
    
    if value > MAX_VAL:
        messagebox.showerror("Error", f"Value {value} exceeds maximum allowed ({MAX_VAL}).")
        return
    
    conn = open_connection()
    if not conn:
        return
    
    set_address_to_fpga(conn, address)
    write_value_to_fpga(conn, value)
    conn.close()
    messagebox.showinfo("Success", f"Value {value} written to address {address}.")

def read_manual():
    """Read the value from a specific address manually."""
    address_str = address_var.get()
    
    if not address_str.isdigit():
        messagebox.showerror("Error", "Address must be a valid integer.")
        return
    
    address = int(address_str)
    
    if address > MAX_ADDR:
        messagebox.showerror("Error", f"Address {address} exceeds maximum allowed ({MAX_ADDR}).")
        return
    
    conn = open_connection()
    if not conn:
        return
    
    set_address_to_fpga(conn, address)
    value = read_value_from_fpga(conn)
    conn.close()
    
    if value is not None:
        messagebox.showinfo("Read Value", f"Value at address {address}: {value} (Hex: 0x{value:04X})")

# --- Tkinter Setup ---
root = tk.Tk()
root.title("RAM Control GUI")

# Variables
file_path_var = tk.StringVar()
address_var = tk.StringVar()
value_var = tk.StringVar()

# File selection frame
file_frame = tk.Frame(root, padx=10, pady=10)
file_frame.pack(fill="x")

file_label = tk.Label(file_frame, text="Select File:")
file_label.pack(side="left")

file_entry = tk.Entry(file_frame, textvariable=file_path_var, width=40)
file_entry.pack(side="left", padx=5)

browse_button = tk.Button(file_frame, text="Browse", command=browse_file)
browse_button.pack(side="left", padx=5)

write_file_button = tk.Button(file_frame, text="Write from File", command=write_from_file)
write_file_button.pack(side="left", padx=5)

# Manual entry frame
manual_frame = tk.Frame(root, padx=10, pady=10)
manual_frame.pack(fill="x")

address_label = tk.Label(manual_frame, text="Address:")
address_label.pack(side="left")

address_entry = tk.Entry(manual_frame, textvariable=address_var, width=10)
address_entry.pack(side="left", padx=5)

value_label = tk.Label(manual_frame, text="Value:")
value_label.pack(side="left")

value_entry = tk.Entry(manual_frame, textvariable=value_var, width=10)
value_entry.pack(side="left", padx=5)

write_manual_button = tk.Button(manual_frame, text="Write Manually", command=write_manual)
write_manual_button.pack(side="left", padx=5)

read_manual_button = tk.Button(manual_frame, text="Read Manually", command=read_manual)
read_manual_button.pack(side="left", padx=5)

# Run Tkinter main loop
root.mainloop()