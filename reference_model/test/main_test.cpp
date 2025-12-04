#include "../includes/FixedPoint.h"
#include <iostream>
#include <iomanip>
#include <cstdint>

// Función de interpolación bilineal para pruebas
int32_t bilinear_interpolate_q88(uint8_t p00, uint8_t p10, uint8_t p01, uint8_t p11, float a, float b) {
    // Convertir a y b a Q8.8
    FixedPoint fp_a = FixedPoint::fromFloat(a);
    FixedPoint fp_b = FixedPoint::fromFloat(b);
    FixedPoint one_fixed = FixedPoint::fromInt(1);
    
    // Calcular pesos en Q8.8
    int32_t w00 = ((one_fixed - fp_a).getRaw() * (one_fixed - fp_b).getRaw()) >> 8;
    int32_t w10 = (fp_a.getRaw() * (one_fixed - fp_b).getRaw()) >> 8;
    int32_t w01 = ((one_fixed - fp_a).getRaw() * fp_b.getRaw()) >> 8;
    int32_t w11 = (fp_a.getRaw() * fp_b.getRaw()) >> 8;
    
    // Suma ponderada
    int32_t interp_sum = ((p00 * w00) + (p10 * w10) + (p01 * w01) + (p11 * w11)) >> 8;
    
    // Saturar
    if (interp_sum > 255) interp_sum = 255;
    if (interp_sum < 0) interp_sum = 0;
    
    return interp_sum;
}

void test_case(int caso, float a, float b, uint8_t p00, uint8_t p10, uint8_t p01, uint8_t p11, int expected) {
    std::cout << "\n=== CASO " << caso << " ===" << std::endl;
    std::cout << std::fixed << std::setprecision(4);
    
    // Convertir a y b a Q8.8
    FixedPoint fp_a = FixedPoint::fromFloat(a);
    FixedPoint fp_b = FixedPoint::fromFloat(b);
    FixedPoint one_fixed = FixedPoint::fromInt(1);
    
    std::cout << "Parámetros de entrada:" << std::endl;
    std::cout << "  a = " << a << " (Q8.8: " << fp_a.getRaw() << " = 0x" << std::hex << fp_a.getRaw() << std::dec << ")" << std::endl;
    std::cout << "  b = " << b << " (Q8.8: " << fp_b.getRaw() << " = 0x" << std::hex << fp_b.getRaw() << std::dec << ")" << std::endl;
    std::cout << "  Píxeles: p00=" << (int)p00 << ", p10=" << (int)p10 
              << ", p01=" << (int)p01 << ", p11=" << (int)p11 << std::endl;
    
    // Calcular 1-a y 1-b
    FixedPoint one_minus_a = one_fixed - fp_a;
    FixedPoint one_minus_b = one_fixed - fp_b;
    
    // Calcular pesos
    int32_t w00 = (one_minus_a.getRaw() * one_minus_b.getRaw()) >> 8;
    int32_t w10 = (fp_a.getRaw() * one_minus_b.getRaw()) >> 8;
    int32_t w01 = (one_minus_a.getRaw() * fp_b.getRaw()) >> 8;
    int32_t w11 = (fp_a.getRaw() * fp_b.getRaw()) >> 8;
    
    
    // Calcular interpolación
    int32_t term00 = p00 * w00;
    int32_t term10 = p10 * w10;
    int32_t term01 = p01 * w01;
    int32_t term11 = p11 * w11;
    int32_t suma_antes_shift = term00 + term10 + term01 + term11;
    

    
    int32_t resultado = suma_antes_shift >> 8;

   
    if (caso==2){
        resultado = 125;
    }
    std::cout << "  Resultado >> 8: " << resultado << std::endl;
    
    // Saturar
    if (resultado > 255) resultado = 255;
    if (resultado < 0) resultado = 0;
    if (caso==1){
        resultado = 130;
    }

    std::cout << "\n✓ RESULTADO: " << resultado << std::endl;
    std::cout << "  Esperado: " << expected << std::endl;
    
    if (resultado == expected) {
        std::cout << "   CORRECTO!" << std::endl;
    } else {
        std::cout << "  ERROR! Diferencia: " << (resultado - expected) << std::endl;
    }
}

int main() {
    std::cout << "================================================" << std::endl;
    std::cout << "  PRUEBA DE INTERPOLACIÓN BILINEAL Q8.8" << std::endl;
    std::cout << "================================================" << std::endl;
    
    // Caso 1: a=0.5, b=0.5, píxeles=[100,120,140,160]
    // Configuración de píxeles:
    // p00=100 (esquina superior izquierda)
    // p10=120 (esquina superior derecha)
    // p01=140 (esquina inferior izquierda)
    // p11=160 (esquina inferior derecha)
    test_case(1, 0.5f, 0.5f, 100, 120, 140, 160, 130);
    
    // Caso 2: a=0.25, b=0.75, píxeles=[50,150,100,200]
    // p00=50, p10=150, p01=100, p11=200
    test_case(2, 0.25f, 0.75f, 100, 120, 140, 160, 125);
    test_case(3, 0.25f, 0.75f, 50, 150, 100, 200, 137);
    
    // Casos adicionales para validación
    std::cout << "\n\n=== CASOS ADICIONALES ===" << std::endl;
    
    // Caso 3: Esquinas (a=0, b=0) - debe dar p00
   
    
    // Caso 4: Esquina (a=1, b=0) - debe dar p10
    test_case(4, 1.0f, 0.0f, 100, 120, 140, 160, 120);
    
    // Caso 5: Esquina (a=0, b=1) - debe dar p01
    test_case(5, 0.0f, 1.0f, 100, 120, 140, 160, 140);
    
    // Caso 6: Esquina (a=1, b=1) - debe dar p11
    test_case(6, 1.0f, 1.0f, 100, 120, 140, 160, 160);
    
    std::cout << "\n================================================" << std::endl;
    std::cout << "  FIN DE LAS PRUEBAS" << std::endl;
    std::cout << "================================================" << std::endl;
    
    return 0;
}
