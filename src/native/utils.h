#pragma once

#include <string>
#import <Carbon/Carbon.h>

// Helper to convert 4-char code to OSType
OSType FourCharCodeFromString(const std::string& str);

// Helper to convert OSType to string
std::string StringFromFourCharCode(OSType code); 