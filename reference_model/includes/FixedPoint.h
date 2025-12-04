#ifndef FIXED_POINT_H
#define FIXED_POINT_H

#include <cstdint>

class FixedPoint {
private:
    int16_t value;
    static constexpr int FRACTIONAL_BITS = 8;

public:
    FixedPoint() : value(0) {}
    
    explicit FixedPoint(int16_t raw_value) : value(raw_value) {}
    
    static FixedPoint fromInt(int integer_part) {
        return FixedPoint(static_cast<int16_t>(integer_part << FRACTIONAL_BITS));
    }
    
    static FixedPoint fromFloat(float f) {
        return FixedPoint(static_cast<int16_t>(f * (1 << FRACTIONAL_BITS)));
    }
    
    int16_t getRaw() const { return value; }
    
    int toInt() const {
        return value >> FRACTIONAL_BITS;
    }
    
    float toFloat() const {
        return static_cast<float>(value) / (1 << FRACTIONAL_BITS);
    }
    
    FixedPoint operator+(const FixedPoint& other) const {
        return FixedPoint(value + other.value);
    }
    
    FixedPoint operator-(const FixedPoint& other) const {
        return FixedPoint(value - other.value);
    }
    
    FixedPoint operator*(const FixedPoint& other) const {
        int32_t result = (static_cast<int32_t>(value) * static_cast<int32_t>(other.value)) >> FRACTIONAL_BITS;
        if (result > 32767) result = 32767;
        if (result < -32768) result = -32768;
        return FixedPoint(static_cast<int16_t>(result));
    }
    
    FixedPoint operator/(const FixedPoint& other) const {
        int32_t result = (static_cast<int32_t>(value) << FRACTIONAL_BITS) / other.value;
        return FixedPoint(static_cast<int16_t>(result));
    }
    
    bool operator<(const FixedPoint& other) const {
        return value < other.value;
    }
    
    bool operator>(const FixedPoint& other) const {
        return value > other.value;
    }
    
    bool operator<=(const FixedPoint& other) const {
        return value <= other.value;
    }
    
    bool operator>=(const FixedPoint& other) const {
        return value >= other.value;
    }
};

#endif
