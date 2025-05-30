#pragma once

#include <napi.h>
#include <map>
#include <vector>
#include <string>

// Structure to hold parsed parameter data that can be safely passed to JS thread
struct ParsedAEParam {
    std::string key;
    std::string type;
    std::string stringValue;
    double numberValue;
    bool boolValue;
    bool isString;
    bool isNumber;
    bool isBool;
    bool isNull;
    std::vector<ParsedAEParam> arrayItems;
    std::map<std::string, ParsedAEParam> objectProps;
    bool isArray;
    bool isObject;
    
    ParsedAEParam() : numberValue(0), boolValue(false), isString(false), isNumber(false), 
                     isBool(false), isNull(true), isArray(false), isObject(false) {}
};

// Enhanced structure to pass Apple Event data to JS
struct AEEventData {
    std::string suite;
    std::string event;
    std::map<std::string, ParsedAEParam> params; // Thread-safe parsed parameters
    std::string targetApp;
    std::string sourceApp;
    int32_t transactionID;
    bool hasTransaction;
    
    AEEventData() : transactionID(0), hasTransaction(false) {}
}; 