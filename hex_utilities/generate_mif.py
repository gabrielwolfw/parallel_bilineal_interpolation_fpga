import os

def convert_to_mif():
    """Convierte matrix_test.txt a formato MIF para Quartus"""
    parent_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    
    input_path = 'matrix_test.txt'
    output_path = os.path.join(parent_dir, 'mem', 'image.mif')
    
    print(f"Leyendo desde: {input_path}")
    print(f"Escribiendo en: {output_path}")
    
    # Leer datos del archivo de entrada
    with open('matrix_test.txt', 'r') as input_file:
        values = []
        for line in input_file:
            try:
                value = int(line.strip())
                # Separar en high byte y low byte (8 bits cada uno)
                high_byte = (value >> 8) & 0xFF
                low_byte = value & 0xFF
                values.append(high_byte)
                values.append(low_byte)
            except ValueError:
                print(f"Advertencia: Línea inválida ignorada: {line.strip()}")
    
    # Escribir archivo MIF
    with open(output_path, 'w') as output_file:
        # Encabezado MIF
        output_file.write("-- Memory Initialization File (.mif)\n")
        output_file.write("-- Generated from matrix_test.txt\n\n")
        output_file.write("DEPTH = 65536;       -- The size of memory in words\n")
        output_file.write("WIDTH = 8;           -- The size of data in bits\n")
        output_file.write("ADDRESS_RADIX = HEX; -- The radix for address values\n")
        output_file.write("DATA_RADIX = HEX;    -- The radix for data values\n\n")
        output_file.write("CONTENT\n")
        output_file.write("BEGIN\n\n")
        
        # Escribir datos
        for addr, value in enumerate(values):
            output_file.write(f"{addr:04X} : {value:02X};\n")
        
        # Rellenar el resto con 00
        output_file.write(f"\n[{len(values):04X}..FFFF] : 00;  -- Fill rest with zeros\n")
        
        output_file.write("\nEND;\n")
    
    print(f"Archivo MIF generado exitosamente con {len(values)} bytes de datos")

if __name__ == "__main__":
    try:
        convert_to_mif()
    except FileNotFoundError:
        print("Error: ¡No se encontró el archivo matrix_test.txt!")
    except Exception as e:
        print(f"Ocurrió un error: {str(e)}")
