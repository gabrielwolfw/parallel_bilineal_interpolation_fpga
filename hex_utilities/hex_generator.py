import os


def calculate_checksum(data):
    total = sum(data)
    checksum = ((~total) + 1) & 0xFF
    return checksum

def convert_to_hex():
        parent_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

        input_path = 'matrix_test.txt'
        output_path = os.path.join(parent_dir, 'mem', 'image.hex')
        
        print(f"Leyendo desde: {input_path}")
        print(f"Escribiendo en: {output_path}")
        with open('matrix_test.txt', 'r') as input_file:
            with open(output_path, 'w') as output_file:
                address = 0
                for line in input_file:
                    try:
                        value = int(line.strip())
                        value = value & 0xFFFF
                        
                        # Split 16-bit value into two bytes
                        high_byte = (value >> 8) & 0xFF
                        low_byte = value & 0xFF
                        length = 0x02
                        # Create data array for checksum calculation
                        data = [length,
                               (address >> 8) & 0xFF,
                               address & 0xFF,
                               0x00,  # Record type (data)
                               high_byte,
                               low_byte]
                        
                        checksum = calculate_checksum(data)
                        
                        # Write Intel HEX record
                        output_file.write(f":{format(length, '02X')}"
                                        f"{format(address, '04X')}"
                                        f"00"
                                        f"{format(high_byte, '02X')}{format(low_byte, '02X')}"
                                        f"{format(checksum, '02X')}\n")
                        
                        address += 2  # Increment address by 2
                    except ValueError:
                        print(f"Advertencia: Línea inválida ignorada: {line.strip()}")

                output_file.write(":00000001FF\n")

if __name__ == "__main__":
    try:
        convert_to_hex()
        print("Archivo Intel HEX generado exitosamente!")
    except FileNotFoundError:
        print("Error: ¡No se encontró el archivo matrix.txt!")
    except Exception as e:
        print(f"Ocurrió un error: {str(e)}")