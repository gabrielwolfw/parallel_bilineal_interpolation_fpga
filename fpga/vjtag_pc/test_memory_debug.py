#!/usr/bin/env python3
"""
test_memory_debug.py - Script de verificación de memoria JTAG
Prueba que SETADDR, WRITE y READ funcionen correctamente
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
    """Envía un comando y espera un poco."""
    print(f"  → Enviando: {command.strip()}")
    sock.sendall(command.encode())
    time.sleep(0.05)

def read_response(sock):
    """Lee respuesta del servidor."""
    response_bytes = b''
    while True:
        chunk = sock.recv(1)
        if not chunk or chunk == b'\n':
            break
        response_bytes += chunk
    response = response_bytes.decode().strip()
    print(f"  ← Recibido: {response}")
    return response

def test_sequence(sock):
    """Ejecuta secuencia de prueba."""
    
    print("\n" + "="*60)
    print("TEST 1: Escribir datos secuenciales en direcciones 0x00-0x05")
    print("="*60)
    
    test_data = [
        (0x00, 0x11),
        (0x01, 0x22),
        (0x02, 0x33),
        (0x03, 0x44),
        (0x04, 0x55),
        (0x05, 0x66),
    ]
    
    for addr, data in test_data:
        print(f"\n[ESCRIBIR] Addr=0x{addr:02X}, Data=0x{data:02X}")
        
        # SETADDR
        addr_bin = format_binary(addr, DATA_WIDTH)
        send_command(sock, f"SETADDR {addr_bin}\n")
        
        # WRITE
        data_bin = format_binary(data, DATA_WIDTH)
        send_command(sock, f"WRITE {data_bin}\n")
    
    print("\n" + "="*60)
    print("TEST 2: Verificar datos escritos con READ")
    print("="*60)
    
    for addr, expected_data in test_data:
        print(f"\n[LEER] Addr=0x{addr:02X}, Esperado=0x{expected_data:02X}")
        
        # SETADDR
        addr_bin = format_binary(addr, DATA_WIDTH)
        send_command(sock, f"SETADDR {addr_bin}\n")
        
        # READ
        send_command(sock, f"READ\n")
        response_hex = read_response(sock)
        
        try:
            read_value = int(response_hex, 16)
            print(f"  Leído: 0x{read_value:02X}")
            
            if read_value == expected_data:
                print(f"  ✓ PASS - Dato correcto")
            else:
                print(f"  ✗ FAIL - Esperado 0x{expected_data:02X}, Obtenido 0x{read_value:02X}")
        except ValueError:
            print(f"  ✗ ERROR - Respuesta inválida: {response_hex}")
    
    print("\n" + "="*60)
    print("TEST 3: Auto-incremento de dirección")
    print("="*60)
    
    print("\n[ESCRIBIR] Setear dirección 0x10, escribir 5 valores consecutivos")
    send_command(sock, f"SETADDR {format_binary(0x10, DATA_WIDTH)}\n")
    
    consecutive_data = [0xAA, 0xBB, 0xCC, 0xDD, 0xEE]
    for data in consecutive_data:
        data_bin = format_binary(data, DATA_WIDTH)
        send_command(sock, f"WRITE {data_bin}\n")
    
    print("\n[VERIFICAR] Leer desde 0x10 y verificar auto-incremento")
    for i, expected_data in enumerate(consecutive_data):
        addr = 0x10 + i
        print(f"\nAddr=0x{addr:02X}, Esperado=0x{expected_data:02X}")
        
        addr_bin = format_binary(addr, DATA_WIDTH)
        send_command(sock, f"SETADDR {addr_bin}\n")
        send_command(sock, f"READ\n")
        response_hex = read_response(sock)
        
        try:
            read_value = int(response_hex, 16)
            print(f"  Leído: 0x{read_value:02X}")
            
            if read_value == expected_data:
                print(f"  ✓ PASS")
            else:
                print(f"  ✗ FAIL - Esperado 0x{expected_data:02X}, Obtenido 0x{read_value:02X}")
        except ValueError:
            print(f"  ✗ ERROR - Respuesta inválida: {response_hex}")
    
    print("\n" + "="*60)
    print("INSTRUCCIONES PARA VERIFICACIÓN EN FPGA:")
    print("="*60)
    print("""
1. VERIFICAR LEDs:
   - LEDR[1] debe parpadear cuando envías SETADDR
   - LEDR[2] debe parpadear cuando envías WRITE
   - LEDR[3] debe encenderse brevemente (escritura a RAM)
   - LEDR[7] debe encenderse durante escritura (FSM en ST_JTAG_WRITE)

2. VERIFICAR HEX DISPLAYS (SW[0]=0 - Modo Read):
   - Presiona KEY[0] varias veces para incrementar display_address
   - HEX5-4 debe mostrar dirección (00, 01, 02, ...)
   - HEX3-0 debe mostrar dato correspondiente (11, 22, 33, ...)
   - HEX1-0 debe mostrar "rd"

3. VERIFICAR HEX DISPLAYS (SW[0]=1 - Modo Address Debug):
   - HEX5-4 muestra la dirección JTAG actual (último SETADDR)
   - HEX3-0 muestra el último dato escrito por JTAG
   - HEX1-0 debe mostrar "Ar"
   - Envía "setaddr 0x12" y verifica que HEX5-4 muestre "12"
   - Envía "write 0xAB" y verifica que HEX3-0 muestre "AB"

4. PRUEBA DE AUTO-INCREMENTO:
   - Envía SETADDR 0x10
   - Envía WRITE 0xAA (dirección debe incrementar a 0x11)
   - Envía WRITE 0xBB (dirección debe incrementar a 0x12)
   - Con SW[0]=1, HEX5-4 debe mostrar "12" (última dirección escrita)
""")

def main():
    print("="*60)
    print("  Test de Memoria JTAG - Verificación Completa")
    print("="*60)
    print(f"Conectando a {HOST}:{PORT}...")
    
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(10.0)
        sock.connect((HOST, PORT))
        print("✓ Conectado al servidor TCL\n")
        
        test_sequence(sock)
        
        print("\n" + "="*60)
        print("PRUEBAS COMPLETADAS")
        print("="*60)
        
    except ConnectionRefusedError:
        print("✗ ERROR: No se pudo conectar. ¿Está corriendo el servidor TCL?")
        print("  Ejecuta: .\\start_jtag_server.ps1")
    except Exception as e:
        print(f"✗ ERROR: {e}")
    finally:
        try:
            sock.close()
        except:
            pass

if __name__ == "__main__":
    main()
