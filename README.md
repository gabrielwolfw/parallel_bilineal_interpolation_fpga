# parallel_bilineal_interpolation_fpga
 Proyecto 02: Diseño e Implementación de una Arquitectura de Dominio Específico (DSA) para Downscaling de Imágenes mediante Interpolación Bilineal Paralela

## Estructura del Repositorio

### Modelo de Referencia (Software)
```
src/          # Código fuente C/C++ del modelo de interpolación bilineal
includes/     # Encabezados y definiciones compartidas
bin/          # Ejecutables generados (solo para pruebas locales, no para entrega)
test/         # Pruebas automáticas y casos de prueba comparativos
Makefile      # Compilación y automatización
```
- El modelo de referencia permite validar bit a bit la salida del sistema hardware-FPGA.

### Diseño FPGA (Hardware)
```
fpga/
 ├── dsa_top.sv            # Módulo toplevel: integra todos los submódulos
 ├── dsa_datapath.sv       # Datapath aritmético: interpolación bilineal, punto fijo Q8.8
 ├── dsa_control_fsm.sv    # FSM: control de flujo, estados, stepping
 ├── dsa_mem_interface.sv  # Módulo interfase de memoria interna (M10K/BRAM)
 ├── dsa_regs.sv           # Registros de control, estado y performance counters
 ├── dsa_comm.sv           # Interfaz JTAG/UART comunicación FPGA-PC
 ├── testbench_unitario.sv # Testbench para pruebas funcionales y verificación
 └── constraints/          # (Opcional) Archivos .qsf para pines/timing
```
- Se entregan los fuentes SystemVerilog, compatibles con Quartus y sintetizables para DE1-SoC MTL2.

## Principales Componentes del Diseño

- **dsa_top:** Orquestra el diseño completo, conecta módulos, gestiona señales externas y de test.
- **dsa_datapath:** Realiza el cálculo de interpolación bilineal secuencial y SIMD.
- **dsa_control_fsm:** Controla el flujo de operación, permite stepping y gestiona estados busy/ready.
- **dsa_mem_interface:** Controla el acceso a la memoria interna para imágenes de entrada/salida.
- **dsa_regs:** Registros configurables (tamaño imagen, factor escala, modo operación, estado, performance counters).
- **dsa_comm:** Facilita comunicación eficiente entre PC y FPGA por JTAG/UART.
- **testbench_unitario:** Simulación completa del sistema, generación de casos de prueba, validación automática.
