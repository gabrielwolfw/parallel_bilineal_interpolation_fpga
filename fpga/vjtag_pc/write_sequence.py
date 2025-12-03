#!/usr/bin/env python3
"""
write_sequence.py - Escribir secuencia de datos con SETADDR explícito
Sin auto-incremento: cada WRITE requiere SETADDR previo
"""

import socket
import time

HOST = 'localhost'
PORT = 2540
DATA_WIDTH = 8

def format_binary(value, width):
    """Convierte un valor a string binario de ancho fijo."""
    return format(value, f'0{width}b')

def send_command(sock, command):
    """Envía un comando al servidor."""
    print(f"  → {command.strip()}")
    sock.sendall(command.encode())
    time.sleep(0.05)

def write_data_sequence(sock, start_addr, data_list):
    """Escribe una secuencia de datos comenzando en start_addr."""
    print(f"\n[ESCRIBIR SECUENCIA] Desde 0x{start_addr:02X}")
    print("=" * 50)
    
    for i, data_value in enumerate(data_list):
        addr = start_addr + i
        
        # SETADDR explícito para cada escritura
        addr_bin = format_binary(addr, DATA_WIDTH)
        print(f"\nAddr 0x{addr:02X} = {data_value} (0x{data_value:02X})")
        send_command(sock, f"SETADDR {addr_bin}\n")
        
        # WRITE
        data_bin = format_binary(data_value, DATA_WIDTH)
        send_command(sock, f"WRITE {data_bin}\n")
    
    print("\n" + "=" * 50)
    print(f"✓ Escritos {len(data_list)} bytes desde 0x{start_addr:02X}")

def verify_data_sequence(sock, start_addr, expected_data):
    """Verifica una secuencia de datos."""
    print(f"\n[VERIFICAR SECUENCIA] Desde 0x{start_addr:02X}")
    print("=" * 50)
    
    errors = 0
    for i, expected in enumerate(expected_data):
        addr = start_addr + i
        
        # SETADDR
        addr_bin = format_binary(addr, DATA_WIDTH)
        send_command(sock, f"SETADDR {addr_bin}\n")
        
        # READ
        send_command(sock, f"READ\n")
        
        # Recibir respuesta
        response_bytes = b''
        while True:
            chunk = sock.recv(1)
            if not chunk or chunk == b'\n':
                break
            response_bytes += chunk
        
        response_hex = response_bytes.decode().strip()
        
        try:
            read_value = int(response_hex, 16)
            status = "✓" if read_value == expected else "✗"
            print(f"{status} Addr 0x{addr:02X}: Esperado 0x{expected:02X}, Leído 0x{read_value:02X}")
            
            if read_value != expected:
                errors += 1
        except ValueError:
            print(f"✗ Addr 0x{addr:02X}: Error al leer (respuesta: {response_hex})")
            errors += 1
    
    print("=" * 50)
    if errors == 0:
        print("✓ VERIFICACIÓN EXITOSA - Todos los datos correctos")
    else:
        print(f"✗ ERRORES: {errors}/{len(expected_data)} valores incorrectos")
    
    return errors == 0

def main():
    print("=" * 60)
    print("  Escritura de Secuencia con SETADDR Explícito")
    print("=" * 60)
    
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(10.0)
        sock.connect((HOST, PORT))
        print(f"✓ Conectado a {HOST}:{PORT}\n")
        
        # Secuencia de prueba 1: Direcciones 0x00-0x0F
        test_data_1 = [0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88,
                       0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00]
        
        write_data_sequence(sock, 0x00, test_data_1)
        time.sleep(0.2)
        verify_data_sequence(sock, 0x00, test_data_1)
        
        # Secuencia de prueba 2: Patrón en 0x10-0x1F
        test_data_2 = [i * 16 for i in range(16)]  # 0x00, 0x10, 0x20, ..., 0xF0
        
        write_data_sequence(sock, 0x10, test_data_2)
        time.sleep(0.2)
        verify_data_sequence(sock, 0x10, test_data_2)
        
        print("\n" + "=" * 60)
        print("VERIFICACIÓN EN FPGA:")
        print("=" * 60)
        print("""
1. Con SW[0]=0 (modo "rd"):
   - Presiona KEY[0] para navegar direcciones 0x00-0x0F
   - HEX5-4 muestra dirección actual
   - HEX3-0 debe mostrar: 11, 22, 33, 44, 55, 66, 77, 88...

2. Con SW[0]=1 (modo "Jt"):
   - HEX5-4 muestra última dirección JTAG (debe ser 0x1F)
   - HEX3-0 muestra último dato escrito (debe ser 0xF0)
   
3. LEDs de verificación:
   - LEDR[1] parpadea con cada SETADDR
   - LEDR[2] parpadea con cada WRITE
   - LEDR[3] se enciende brevemente al escribir en RAM
   - LEDR[7] se enciende durante la escritura (FSM en WRITE)
""")
        
        sock.close()
        
    except ConnectionRefusedError:
        print("✗ ERROR: No se pudo conectar al servidor TCL")
        print("  Ejecuta: .\\start_jtag_server.ps1")
    except Exception as e:
        print(f"✗ ERROR: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    main()
