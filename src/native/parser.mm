#include "parser.h"
#include "utils.h"
#import <Foundation/Foundation.h>

// Helper to convert AEDesc to ParsedAEParam (thread-safe data)
ParsedAEParam AEDescToParsedParam(const AEDesc* desc) {
    ParsedAEParam param;
    
    if (!desc) {
        param.isNull = true;
        return param;
    }
    
    param.type = StringFromFourCharCode(desc->descriptorType);
    param.isNull = false;
    
    switch (desc->descriptorType) {
        case typeChar:
        case typeUTF8Text:
        case typeUnicodeText: {
            Size dataSize = AEGetDescDataSize(desc);
            if (dataSize > 0) {
                std::vector<char> buffer(dataSize + 1, 0);
                OSErr err = AEGetDescData(desc, buffer.data(), dataSize);
                if (err == noErr) {
                    param.stringValue = std::string(buffer.data());
                    param.isString = true;
                }
            }
            break;
        }
        case typeSInt32: {
            SInt32 value;
            OSErr err = AEGetDescData(desc, &value, sizeof(value));
            if (err == noErr) {
                param.numberValue = static_cast<double>(value);
                param.isNumber = true;
            }
            break;
        }
        case typeSInt16: {
            SInt16 value;
            OSErr err = AEGetDescData(desc, &value, sizeof(value));
            if (err == noErr) {
                param.numberValue = static_cast<double>(value);
                param.isNumber = true;
            }
            break;
        }
        case typeIEEE64BitFloatingPoint: {
            double value;
            OSErr err = AEGetDescData(desc, &value, sizeof(value));
            if (err == noErr) {
                param.numberValue = value;
                param.isNumber = true;
            }
            break;
        }
        case typeBoolean: {
            Boolean value;
            OSErr err = AEGetDescData(desc, &value, sizeof(value));
            if (err == noErr) {
                param.boolValue = value;
                param.isBool = true;
            }
            break;
        }
        case typeNull:
            param.isNull = true;
            break;
        case typeObjectSpecifier: {
            // For object specifiers, we'll store a detailed representation
            param.isObject = true;
            
            // Get the object class
            AEDesc classDesc;
            OSErr err = AEGetKeyDesc(desc, keyAEDesiredClass, typeType, &classDesc);
            if (err == noErr) {
                OSType classCode;
                err = AEGetDescData(&classDesc, &classCode, sizeof(classCode));
                if (err == noErr) {
                    param.objectProps["class"] = ParsedAEParam();
                    param.objectProps["class"].stringValue = StringFromFourCharCode(classCode);
                    param.objectProps["class"].isString = true;
                    param.objectProps["class"].isNull = false;
                }
                AEDisposeDesc(&classDesc);
            }
            
            // Get the key form
            AEDesc keyFormDesc;
            err = AEGetKeyDesc(desc, keyAEKeyForm, typeType, &keyFormDesc);
            if (err == noErr) {
                OSType keyForm;
                err = AEGetDescData(&keyFormDesc, &keyForm, sizeof(keyForm));
                if (err == noErr) {
                    param.objectProps["keyForm"] = ParsedAEParam();
                    param.objectProps["keyForm"].stringValue = StringFromFourCharCode(keyForm);
                    param.objectProps["keyForm"].isString = true;
                    param.objectProps["keyForm"].isNull = false;
                }
                AEDisposeDesc(&keyFormDesc);
            }
            
            // Get the key data
            AEDesc keyDataDesc;
            err = AEGetKeyDesc(desc, keyAEKeyData, typeWildCard, &keyDataDesc);
            if (err == noErr) {
                param.objectProps["keyData"] = AEDescToParsedParam(&keyDataDesc);
                AEDisposeDesc(&keyDataDesc);
            }
            
            // Get the container (this is crucial for the full hierarchy)
            AEDesc containerDesc;
            err = AEGetKeyDesc(desc, keyAEContainer, typeWildCard, &containerDesc);
            if (err == noErr) {
                param.objectProps["container"] = AEDescToParsedParam(&containerDesc);
                AEDisposeDesc(&containerDesc);
            }
            
            param.objectProps["type"] = ParsedAEParam();
            param.objectProps["type"].stringValue = "objectSpecifier";
            param.objectProps["type"].isString = true;
            param.objectProps["type"].isNull = false;
            break;
        }
        default: {
            // For unknown types, try to get as string if reasonable size
            Size dataSize = AEGetDescDataSize(desc);
            if (dataSize > 0 && dataSize < 1024) {
                std::vector<char> buffer(dataSize + 1, 0);
                OSErr err = AEGetDescData(desc, buffer.data(), dataSize);
                if (err == noErr) {
                    param.stringValue = std::string(buffer.data());
                    param.isString = true;
                } else {
                    param.stringValue = "<binary data>";
                    param.isString = true;
                }
            } else {
                param.stringValue = "<binary data>";
                param.isString = true;
            }
            break;
        }
    }
    
    return param;
}

// Helper to convert ParsedAEParam to Napi::Value in JS thread
Napi::Value ParsedParamToNapiValue(Napi::Env env, const ParsedAEParam& param) {
    if (param.isNull) return env.Null();
    if (param.isString) return Napi::String::New(env, param.stringValue);
    if (param.isNumber) return Napi::Number::New(env, param.numberValue);
    if (param.isBool) return Napi::Boolean::New(env, param.boolValue);
    
    if (param.isArray) {
        Napi::Array array = Napi::Array::New(env, param.arrayItems.size());
        for (size_t i = 0; i < param.arrayItems.size(); i++) {
            array.Set(i, ParsedParamToNapiValue(env, param.arrayItems[i]));
        }
        return array;
    }
    
    if (param.isObject) {
        Napi::Object obj = Napi::Object::New(env);
        for (const auto& pair : param.objectProps) {
            obj.Set(pair.first, ParsedParamToNapiValue(env, pair.second));
        }
        return obj;
    }
    
    // Fallback for unknown types
    Napi::Object result = Napi::Object::New(env);
    result.Set("type", Napi::String::New(env, param.type));
    result.Set("data", Napi::String::New(env, param.stringValue));
    return result;
}

// Helper to parse Apple Event parameters to thread-safe data
std::map<std::string, ParsedAEParam> ParseAEParametersThreadSafe(const AppleEvent* evt) {
    std::map<std::string, ParsedAEParam> params;
    
    // Get the direct parameter (the main target of the command)
    AEDesc directParam;
    OSErr err = AEGetParamDesc(evt, keyDirectObject, typeWildCard, &directParam);
    if (err == noErr) {
        params["----"] = AEDescToParsedParam(&directParam);
        AEDisposeDesc(&directParam);
    }
    
    // Parse other parameters
    const OSType commonParams[] = {
        'kfil',  // file parameter
        'fltp',  // file type
        'insh',  // insertion location
        'prdt',  // properties
        'data',  // data
        'kocl',  // object class
        'JvSc',  // javascript (from the sdef)
        0        // terminator
    };
    
    for (int i = 0; commonParams[i] != 0; i++) {
        AEDesc paramDesc;
        err = AEGetParamDesc(evt, commonParams[i], typeWildCard, &paramDesc);
        if (err == noErr) {
            std::string key = StringFromFourCharCode(commonParams[i]);
            params[key] = AEDescToParsedParam(&paramDesc);
            AEDisposeDesc(&paramDesc);
        }
    }
    
    return params;
}

// Helper to get application info from Apple Event
void ParseTargetApplication(const AppleEvent* evt, AEEventData& aeData) {
    AEDesc targetDesc;
    OSErr err = AEGetAttributeDesc(evt, keyAddressAttr, typeWildCard, &targetDesc);
    if (err == noErr) {
        if (targetDesc.descriptorType == typeApplicationBundleID) {
            Size dataSize = AEGetDescDataSize(&targetDesc);
            if (dataSize > 0) {
                std::vector<char> buffer(dataSize + 1, 0);
                err = AEGetDescData(&targetDesc, buffer.data(), dataSize);
                if (err == noErr) {
                    aeData.targetApp = std::string(buffer.data());
                }
            }
        } else if (targetDesc.descriptorType == typeProcessSerialNumber) {
            ProcessSerialNumber psn;
            err = AEGetDescData(&targetDesc, &psn, sizeof(psn));
            if (err == noErr) {
                // For modern macOS, we'll just indicate it's a process serial number
                // Getting the actual process name requires more complex modern APIs
                aeData.targetApp = "ProcessSerialNumber";
            }
        } else if (targetDesc.descriptorType == typeKernelProcessID) {
            pid_t pid;
            err = AEGetDescData(&targetDesc, &pid, sizeof(pid));
            if (err == noErr) {
                aeData.targetApp = "PID:" + std::to_string(pid);
            }
        }
        AEDisposeDesc(&targetDesc);
    }
}

// Helper to create JS object from AEEventData
Napi::Object CreateAEEventObject(Napi::Env env, const AEEventData& data) {
    Napi::Object obj = Napi::Object::New(env);
    obj.Set("suite", Napi::String::New(env, data.suite));
    obj.Set("event", Napi::String::New(env, data.event));
    
    // Create params object from parsed parameters
    Napi::Object params = Napi::Object::New(env);
    for (const auto& pair : data.params) {
        params.Set(pair.first, ParsedParamToNapiValue(env, pair.second));
    }
    obj.Set("params", params);
    
    // Add additional metadata
    if (!data.targetApp.empty()) {
        obj.Set("targetApp", Napi::String::New(env, data.targetApp));
    }
    if (!data.sourceApp.empty()) {
        obj.Set("sourceApp", Napi::String::New(env, data.sourceApp));
    }
    if (data.hasTransaction) {
        obj.Set("transactionID", Napi::Number::New(env, data.transactionID));
    }
    
    return obj;
} 