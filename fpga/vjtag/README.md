# FPGA JTAG Communication Interface (via TCP/IP Bridge) - Parameterized & Bidirectional

## 1. Overview

This project provides a flexible framework for **parameterized-width, bidirectional communication** (read and write) between a host PC and an Intel/Altera FPGA using the Virtual JTAG (vJTAG) interface via a TCP/IP bridge. It allows you to send data to and receive data from your FPGA design in real-time, supporting various data widths (e.g., 8-bit, 16-bit, 32-bit) with consistent configuration across all components.

The system consists of:
1.  **Parameterized Verilog Module (`vjtag_interface.sv` [4]):** A hardware module with a data width parameter (`DW`) to be instantiated within your FPGA design. It implements the JTAG-accessible data registers and uses enums for instruction decoding.
2.  **Configurable TCL Script (`jtag_server.tcl` [2]):** Runs within `quartus_stp`. It creates a TCP/IP server that bridges commands to JTAG operations. The JTAG data width is passed as a command-line argument to this script.
3.  **Configurable Python Script (`jtag_fpga.py` [1]):** A command-line client that connects to the TCL server. It provides a user-friendly command processor with history, verbosity control, and parameterized data width.
4.  **Example Top-Level Verilog (`top.sv` [3]):** Demonstrates how to instantiate and connect the Virtual JTAG IP and the parameterized `vjtag_interface.sv` module within a larger FPGA design.

This README is based on the provided working files:
*   `jtag_fpga.py` [1] (Python Client)
*   `jtag_server.tcl` [2] (TCL Server)
*   `top.sv` [3] (Example Top-Level FPGA Design)
*   `vjtag_interface.sv` [4] (Parameterized JTAG Hardware Interface)

## 2. Features

*   **Bidirectional Communication:** Supports both writing data to the FPGA and reading data from it.
*   **Parameterized Data Width (`DW`):** The width of the JTAG data path can be configured in Verilog (as shown in `vjtag_interface.sv` [4] and its instantiation in `top.sv` [3]) and synchronized with software scripts via command-line arguments.
*   **User-Friendly Python Client:**
    *   Interactive command processor (`write`, `read` commands).
    *   Command history (Up/Down arrows, saved across sessions via `readline`).
    *   Configurable output verbosity (`quiet`, `normal`, `debug`) via command-line or runtime `verbose` command.
    *   The `<address>` field in commands is currently a software placeholder.
*   **Clear JTAG Instruction Handling:** Uses a 2-bit Instruction Register (IR) to select BYPASS, WRITE, or READ operations, decoded using enums in Verilog (`vjtag_interface.sv` [4]).
*   **Standard JTAG State Machine Usage:** Utilizes Virtual JTAG IP signals (`v_cdr`, `v_sdr`, `udr`) for correct data capture, shift, and update phases.
*   **Debug Support:** The Verilog module (`vjtag_interface.sv` [4]) includes `debug_dr1` and `debug_dr2` outputs, demonstrated in `top.sv` [3] by connecting them to LEDs.

## 3. Prerequisites

*   **Intel Quartus Prime (or older Quartus II):**
    *   For Verilog synthesis and FPGA configuration.
    *   Requires the "Virtual JTAG" IP core.
    *   The `quartus_stp` utility (System Console / SignalTap II program) is needed to run the `jtag_server.tcl` script.
*   **Python 3.x:**
    *   To run the `jtag_fpga.py` client.
    *   Standard libraries: `socket`, `time`, `argparse`, `os`, `readline`, `atexit`.
*   **(Optional, for Windows Python command history):** `pyreadline3`. Install using pip:
    ```
    pip install pyreadline3
    ```
*   **FPGA Development Board:** An Intel/Altera FPGA board with a JTAG programmer (e.g., USB-Blaster) recognized by Quartus.

## 4. Setup and Configuration

The data width **MUST** be consistent across:
1.  The `DW` parameter value used when instantiating `vjtag_interface.sv` in your top-level design (e.g., `localparam int DW = 16;` in `top.sv` [3]).
2.  The Quartus Virtual JTAG IP configuration (data register path widths).
3.  The command-line argument passed to `jtag_server.tcl` [2].
4.  The command-line argument (`-dw` or `--data_width`) passed to `jtag_fpga.py` [1].

### 4.1. FPGA Design (Verilog & JTAG IP)

**A. `vjtag_interface.sv` Module [4]**
1.  Ensure this Verilog file is included in your Quartus project.
2.  The module itself is parameterized with `parameter int DW = 8;` (this is the default if not overridden during instantiation).

**B. Quartus Virtual JTAG IP Configuration**
1.  In your Quartus project, instantiate the "Virtual JTAG" IP core. The instance in `top.sv` [3] is named `u_vjtag`.
2.  Configure the IP with the following parameters:
    *   **Instruction Register Width:** Set to **`2`** bits. This allows:
        *   `IR=0` (`2'b00`): BYPASS (maps to `BYPASS` enum in `vjtag_interface.sv`)
        *   `IR=1` (`2'b01`): User Instruction for **WRITE** (maps to `WRITE` enum, targets `DR1`)
        *   `IR=2` (`2'b10`): User Instruction for **READ** (maps to `READ` enum, targets `DR2`)
    *   **Number of virtual JTAG user data register paths:** Set to **`2`**.
    *   For **User data register path 0** (corresponds to `IR=1` from IP):
        *   **Data register width:** Set this to your chosen `DW` (e.g., `16` as used in `top.sv` [3]).
    *   For **User data register path 1** (corresponds to `IR=2` from IP):
        *   **Data register width:** Set to the *same* `DW`.
    *   **Exposed Signals from IP:** Ensure the IP is configured to output the necessary control signals. The `top.sv` [3] example shows these connections:
        *   `ir_in` (IP's instruction output, often `ir_out[1:0]` in IP GUI)
        *   `virtual_state_cdr`
        *   `virtual_state_sdr`
        *   `virtual_state_udr`
        *   `tck` (JTAG clock generated by IP)
        *   `tdi` (TDI to be passed to user logic)

**C. Top-Level FPGA Design (Example: `top.sv` [3])**
1.  Instantiate the Virtual JTAG IP (e.g., `u_vjtag`) and the `vjtag_interface.sv` module (e.g., `u_vjtag_interface`).
2.  **Set the `DW` parameter for `vjtag_interface`** when instantiating it. The `top.sv` [3] file uses a `localparam int DW = 16;` and then instantiates with `vjtag_interface #(.DW(DW)) u_vjtag_interface (...)`.
3.  Connect the output ports of the JTAG IP to the corresponding input ports of your `u_vjtag_interface` instance:
    *   JTAG IP `ir_in` (or its actual name like `ir_out`) -> `u_vjtag_interface.ir_in`
    *   JTAG IP `virtual_state_cdr` -> `u_vjtag_interface.v_cdr`
    *   JTAG IP `virtual_state_sdr` -> `u_vjtag_interface.v_sdr`
    *   JTAG IP `virtual_state_udr` -> `u_vjtag_interface.udr`
    *   JTAG IP `tdi` (output from IP for user logic) -> `u_vjtag_interface.tdi`
    *   `u_vjtag_interface.tdo` -> JTAG IP `tdo` (input to IP from user logic)
    *   Connect `u_vjtag_interface.aclr` to your system's reset signal (e.g., `resetn` in `top.sv`).
    *   Connect `u_vjtag_interface.tck` to the `tck` output from the JTAG IP.
4.  Connect the data paths of `u_vjtag_interface`:
    *   `u_vjtag_interface.data_in` should be connected to the FPGA internal signals (of width `DW`) that you wish to read out. In `top.sv` [3], this is connected to a `counter`.
    *   `u_vjtag_interface.data_out` should be connected to FPGA internal signals/registers (of width `DW`) that you wish to control from the PC. In `top.sv` [3], this is connected to `jtag_data`, which can then load the `counter`.
5.  Optionally, connect the debug ports (`debug_dr1`, `debug_dr2`) to LEDs or SignalTap, as shown in `top.sv` [3] where they are connected to `LEDG` and parts of `LEDR`.

**D. Compile and Program**
1.  Add all necessary `.sv` files (including `top.sv` and `vjtag_interface.sv`) and the JTAG IP `.qip` file to your Quartus project.
2.  Compile the project.
3.  Program your FPGA board.

### 4.2. Software Execution

**A. Start the TCL Server (`jtag_server.tcl` [2])**
1.  Open a terminal where `quartus_stp` is accessible (e.g., from an "Embedded Command Shell" or after sourcing Quartus environment scripts).
2.  Run the script, passing the data width as a command-line argument. **This width must match `DW` used in Verilog and the JTAG IP.**
    *   Example for **16-bit** data width (to match `top.sv` [3]):
        ```
        quartus_stp -t /path/to/jtag_server.tcl 16
        ```
    *   If `<DATA_WIDTH>` is omitted, the script defaults to 8.
3.  The server will indicate the data width it's using and the listening port (default: `2540`). Keep this terminal open.

**B. Run the Python Client (`jtag_fpga.py` [1])**
1.  Open another terminal.
2.  Run the script, passing the data width (`-dw` or `--data_width`) and optional verbosity (`-v` for debug, `-q` for quiet). **This width must match the TCL server and hardware.**
    *   For **16-bit** data width:
        ```
        python /path/to/jtag_fpga.py -dw 16
        ```
    *   For **16-bit** with debug verbosity:
        ```
        python /path/to/jtag_fpga.py -dw 16 -v
        ```
    *   Help: `python /path/to/jtag_fpga.py --help`

3.  **Using the Python Command Processor:**
    The prompt will indicate the active data width (e.g., `JTAG-16bit>`).
    *   `write <address> <value>`
        *   Example (16-bit): `write 0x10 0xABCD` or `write 16 43981`
        *   Value range depends on configured `DATA_WIDTH`.
    *   `read <address> <expected_value>`
        *   Example (16-bit): `read 0x10 0xABCD`
    *   `verbose <quiet|normal|debug>`: Change runtime output verbosity.
    *   `history`: View command history.
    *   `exit`: Quit the client.
    *   **Usability:** Up/Down arrows for command history. Terminal scrollback for output (configure terminal buffer size if needed).

## 5. Troubleshooting

*   **Reads Return Incorrect/Fixed Values (like `01` hex):**
    1.  **Data Width Mismatch:** THE MOST COMMON ISSUE. Ensure `DW` in Verilog instantiation (`top.sv`), JTAG IP data path widths, TCL server argument, and Python client argument are ALL IDENTICAL.
    2.  **Virtual JTAG IP Configuration:** Confirm Instruction Register width is `2`, **two** User Data Register paths are configured, and **both** paths have their "Data register width" correctly set to `DW`. The second path (for IR=`2'b10`) must be active for reads.
    3.  **Verilog Connections in `top.sv`:** Verify all JTAG IP output signals (`ir_in`, `virtual_state_cdr`, etc.) are correctly wired to the `u_vjtag_interface` instance.
    4.  **Verilog Logic in `vjtag_interface.sv`:** Is `ir_state` correctly decoding `ir_in`? Is `DR2 <= data_in;` executing during `v_cdr` when `ir_state == READ`?
    5.  **Use SignalTap II:** Probe `ir_in`, `v_cdr`, `v_sdr`, `data_in`, `DR2`, `tdo` within `vjtag_interface`, and the `counter` and `jtag_data` signals in `top.sv`.
*   **"Connection Refused" (Python):** TCL server (`quartus_stp ...`) not running or firewall issue.
*   **"Unknown command" (TCL Server, for writes):** Data width mismatch. The length of the binary string from Python doesn't match `$VJTAG_DATA_WIDTH` used in the TCL `regexp`.

