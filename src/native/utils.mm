#include "utils.h"

// Helper to convert 4-char code to OSType
OSType FourCharCodeFromString(const std::string& str) {
    if (str.length() != 4) return 0;
    return (OSType)((str[0] << 24) | (str[1] << 16) | (str[2] << 8) | str[3]);
}

// Helper to convert OSType to string
std::string StringFromFourCharCode(OSType code) {
    char str[5] = {0};
    // OSType is big-endian: most significant byte first
    str[0] = (code >> 24) & 0xFF;
    str[1] = (code >> 16) & 0xFF;
    str[2] = (code >> 8) & 0xFF;
    str[3] = code & 0xFF;
    return std::string(str);
} 