#!/usr/bin/env python3
"""
jtag_mem_writer.py
Script simple para escribir datos a la memoria FPGA vía JTAG
Uso:
    python jtag_mem_writer.py --addr 0x0000 --data 0xFF
    python jtag_mem_writer.py --addr 100 --data 255
    python jtag_mem_writer.py --file image.bin --start-addr 0
"""

import socket
import argparse
import time
import sys

HOST = 'localhost'
PORT = 2540
SOCKET_TIMEOUT = 5.0

class JTAGMemoryWriter:
    def __init__(self, host=HOST, port=PORT, verbose=False):
        self.host = host
        self.port = port
        self.verbose = verbose
        self.conn = None
        
    def connect(self):
        """Conectar al servidor TCL JTAG"""
        try:
            self.conn = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.conn.settimeout(SOCKET_TIMEOUT)
            self.conn.connect((self.host, self.port))
            if self.verbose:
                print(f"✓ Conectado a {self.host}:{self.port}")
            return True
        except ConnectionRefusedError:
            print(f"✗ Error: No se pudo conectar a {self.host}:{self.port}")
            print(f"  Asegúrate de que el servidor TCL esté corriendo:")
            print(f"  quartus_stp -t jtag_server.tcl 8")
            return False
        except Exception as e:
            print(f"✗ Error de conexión: {e}")
            return False
    
    def disconnect(self):
        """Cerrar conexión"""
        if self.conn:
            self.conn.close()
            if self.verbose:
                print("✓ Desconectado")
    
    def set_address(self, address):
        """Enviar comando SETADDR"""
        binary_addr = format(address & 0xFF, '08b')
        request = f"SETADDR {binary_addr}\n"
        
        if self.verbose:
            print(f"  SETADDR: 0x{address:04X} ({address}) -> {binary_addr}")
        
        try:
            self.conn.sendall(request.encode())
            time.sleep(0.01)  # Pequeña pausa para asegurar procesamiento
            return True
        except Exception as e:
            print(f"✗ Error al enviar SETADDR: {e}")
            return False
    
    def write_byte(self, data):
        """Enviar comando WRITE con 1 byte"""
        binary_data = format(data & 0xFF, '08b')
        request = f"WRITE {binary_data}\n"
        
        if self.verbose:
            print(f"  WRITE: 0x{data:02X} ({data}) -> {binary_data}")
        
        try:
            self.conn.sendall(request.encode())
            time.sleep(0.01)
            return True
        except Exception as e:
            print(f"✗ Error al escribir dato: {e}")
            return False
    
    def read_byte(self):
        """Leer 1 byte desde la dirección actual"""
        request = "READ\n"
        
        try:
            self.conn.sendall(request.encode())
            response = self.conn.recv(1024).decode().strip()
            
            if response:
                value = int(response, 16)
                if self.verbose:
                    print(f"  READ: 0x{value:02X} ({value})")
                return value
            else:
                print("✗ No se recibió respuesta")
                return None
        except Exception as e:
            print(f"✗ Error al leer dato: {e}")
            return None
    
    def write_memory(self, start_addr, data_bytes):
        """Escribir múltiples bytes a memoria"""
        print(f"Escribiendo {len(data_bytes)} bytes a partir de 0x{start_addr:04X}...")
        
        # Dividir la dirección en bytes (solo usamos los 15 bits inferiores)
        # Para direcciones mayores a 255, necesitarás enviar múltiples SETADDR
        # o implementar un protocolo de dirección extendida
        
        current_addr = start_addr
        success_count = 0
        
        for i, byte_val in enumerate(data_bytes):
            # Setear dirección cada vez (para direcciones de 8 bits)
            # Si necesitas direcciones mayores, tendrás que usar un esquema diferente
            addr_low = current_addr & 0xFF
            
            if not self.set_address(addr_low):
                break
            
            if not self.write_byte(byte_val):
                break
            
            success_count += 1
            current_addr += 1
            
            # Mostrar progreso cada 16 bytes
            if (i + 1) % 16 == 0:
                print(f"  Progreso: {i+1}/{len(data_bytes)} bytes escritos")
        
        print(f"✓ Escritura completada: {success_count}/{len(data_bytes)} bytes")
        return success_count == len(data_bytes)
    
    def verify_memory(self, start_addr, expected_bytes):
        """Verificar que los datos escritos sean correctos"""
        print(f"Verificando {len(expected_bytes)} bytes desde 0x{start_addr:04X}...")
        
        current_addr = start_addr
        errors = 0
        
        for i, expected_val in enumerate(expected_bytes):
            addr_low = current_addr & 0xFF
            
            if not self.set_address(addr_low):
                break
            
            read_val = self.read_byte()
            if read_val is None:
                break
            
            if read_val != expected_val:
                print(f"  ✗ Error en 0x{current_addr:04X}: esperado 0x{expected_val:02X}, leído 0x{read_val:02X}")
                errors += 1
            
            current_addr += 1
            
            if (i + 1) % 16 == 0 and self.verbose:
                print(f"  Progreso: {i+1}/{len(expected_bytes)} bytes verificados")
        
        if errors == 0:
            print(f"✓ Verificación exitosa: todos los bytes coinciden")
        else:
            print(f"✗ Verificación falló: {errors} errores encontrados")
        
        return errors == 0

def main():
    parser = argparse.ArgumentParser(
        description='Escribir datos a memoria FPGA vía JTAG',
        epilog='Ejemplo: python jtag_mem_writer.py --addr 0x00 --data 0xFF 0xAA 0x55'
    )
    
    parser.add_argument('--addr', type=str, default='0',
                        help='Dirección de inicio (hex o decimal)')
    parser.add_argument('--data', nargs='+', type=str,
                        help='Bytes a escribir (hex o decimal)')
    parser.add_argument('--file', type=str,
                        help='Archivo binario para cargar')
    parser.add_argument('--verify', action='store_true',
                        help='Verificar después de escribir')
    parser.add_argument('-v', '--verbose', action='store_true',
                        help='Modo verbose')
    parser.add_argument('--host', type=str, default=HOST,
                        help=f'Host del servidor TCL (default: {HOST})')
    parser.add_argument('--port', type=int, default=PORT,
                        help=f'Puerto del servidor TCL (default: {PORT})')
    
    args = parser.parse_args()
    
    # Parsear dirección
    try:
        start_addr = int(args.addr, 0)  # Soporta 0x para hex
    except ValueError:
        print(f"✗ Error: dirección inválida '{args.addr}'")
        return 1
    
    # Obtener datos
    data_bytes = []
    
    if args.file:
        # Cargar desde archivo
        try:
            with open(args.file, 'rb') as f:
                data_bytes = list(f.read())
            print(f"✓ Cargados {len(data_bytes)} bytes desde {args.file}")
        except Exception as e:
            print(f"✗ Error al leer archivo: {e}")
            return 1
    elif args.data:
        # Parsear datos de línea de comando
        try:
            for data_str in args.data:
                byte_val = int(data_str, 0) & 0xFF
                data_bytes.append(byte_val)
        except ValueError as e:
            print(f"✗ Error al parsear datos: {e}")
            return 1
    else:
        print("✗ Error: debe especificar --data o --file")
        parser.print_help()
        return 1
    
    # Mostrar resumen
    print(f"\n{'='*60}")
    print(f"JTAG Memory Writer")
    print(f"{'='*60}")
    print(f"Dirección inicio: 0x{start_addr:04X} ({start_addr})")
    print(f"Bytes a escribir: {len(data_bytes)}")
    if len(data_bytes) <= 16:
        hex_str = ' '.join([f'{b:02X}' for b in data_bytes])
        print(f"Datos: {hex_str}")
    print(f"{'='*60}\n")
    
    # Crear escritor y conectar
    writer = JTAGMemoryWriter(host=args.host, port=args.port, verbose=args.verbose)
    
    if not writer.connect():
        return 1
    
    try:
        # Escribir datos
        if not writer.write_memory(start_addr, data_bytes):
            return 1
        
        # Verificar si se solicitó
        if args.verify:
            print()
            if not writer.verify_memory(start_addr, data_bytes):
                return 1
        
        print("\n✓ Operación completada exitosamente")
        return 0
        
    finally:
        writer.disconnect()

if __name__ == '__main__':
    sys.exit(main())
