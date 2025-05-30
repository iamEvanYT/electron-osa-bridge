#include <napi.h>
#import <Foundation/Foundation.h>
#import <Carbon/Carbon.h>

static Napi::ThreadSafeFunction tsfn;   // JS dispatcher
static NSMutableDictionary<NSString*, id>* handlers; // suite+event → true

// Helper to convert 4-char code to OSType
OSType FourCharCodeFromString(const std::string& str) {
    if (str.length() != 4) return 0;
    return (OSType)((str[0] << 24) | (str[1] << 16) | (str[2] << 8) | str[3]);
}

// Helper to convert OSType to string
std::string StringFromFourCharCode(OSType code) {
    char str[5] = {0};
    str[0] = (code >> 24) & 0xFF;
    str[1] = (code >> 16) & 0xFF;
    str[2] = (code >> 8) & 0xFF;
    str[3] = code & 0xFF;
    return std::string(str);
}

// Enhanced structure to pass Apple Event data to JS
struct AEEventData {
    std::string suite;
    std::string event;
    std::vector<uint8_t> eventData; // Raw Apple Event data for parameter parsing
    std::string targetApp;
    std::string sourceApp;
    int32_t transactionID;
    bool hasTransaction;
    
    AEEventData() : transactionID(0), hasTransaction(false) {}
};

// Helper to convert AEDesc to Napi::Value
Napi::Value AEDescToNapiValue(Napi::Env env, const AEDesc* desc) {
    if (!desc) return env.Null();
    
    switch (desc->descriptorType) {
        case typeChar:
        case typeUTF8Text: {
            Size dataSize = AEGetDescDataSize(desc);
            if (dataSize > 0) {
                std::vector<char> buffer(dataSize + 1, 0);
                OSErr err = AEGetDescData(desc, buffer.data(), dataSize);
                if (err == noErr) {
                    return Napi::String::New(env, buffer.data());
                }
            }
            break;
        }
        case typeSInt32: {
            SInt32 value;
            OSErr err = AEGetDescData(desc, &value, sizeof(value));
            if (err == noErr) {
                return Napi::Number::New(env, value);
            }
            break;
        }
        case typeIEEE64BitFloatingPoint: {
            double value;
            OSErr err = AEGetDescData(desc, &value, sizeof(value));
            if (err == noErr) {
                return Napi::Number::New(env, value);
            }
            break;
        }
        case typeBoolean: {
            Boolean value;
            OSErr err = AEGetDescData(desc, &value, sizeof(value));
            if (err == noErr) {
                return Napi::Boolean::New(env, value);
            }
            break;
        }
        case typeNull:
            return env.Null();
        case typeAEList: {
            long count;
            OSErr err = AECountItems(desc, &count);
            if (err == noErr) {
                Napi::Array array = Napi::Array::New(env, count);
                for (long i = 1; i <= count; i++) {
                    AEDesc item;
                    err = AEGetNthDesc(desc, i, typeWildCard, nullptr, &item);
                    if (err == noErr) {
                        array.Set(i - 1, AEDescToNapiValue(env, &item));
                        AEDisposeDesc(&item);
                    }
                }
                return array;
            }
            break;
        }
        case typeAERecord: {
            long count;
            OSErr err = AECountItems(desc, &count);
            if (err == noErr) {
                Napi::Object obj = Napi::Object::New(env);
                for (long i = 1; i <= count; i++) {
                    AEKeyword keyword;
                    AEDesc item;
                    err = AEGetNthDesc(desc, i, typeWildCard, &keyword, &item);
                    if (err == noErr) {
                        std::string key = StringFromFourCharCode(keyword);
                        obj.Set(key, AEDescToNapiValue(env, &item));
                        AEDisposeDesc(&item);
                    }
                }
                return obj;
            }
            break;
        }
        default: {
            // For unknown types, try to get as raw data
            Size dataSize = AEGetDescDataSize(desc);
            if (dataSize > 0 && dataSize < 1024) { // Reasonable size limit
                std::vector<uint8_t> buffer(dataSize);
                OSErr err = AEGetDescData(desc, buffer.data(), dataSize);
                if (err == noErr) {
                    Napi::Object result = Napi::Object::New(env);
                    result.Set("type", Napi::String::New(env, StringFromFourCharCode(desc->descriptorType)));
                    result.Set("data", Napi::String::New(env, "<binary data>"));
                    return result;
                }
            }
            break;
        }
    }
    
    return env.Undefined();
}

// Helper to parse Apple Event parameters from raw event data
Napi::Object ParseAEParametersToJS(Napi::Env env, const std::vector<uint8_t>& eventData) {
    Napi::Object params = Napi::Object::New(env);
    
    if (eventData.empty()) return params;
    
    // Reconstruct the Apple Event from raw data
    AEDesc eventDesc;
    OSErr err = AECreateDesc(typeAppleEvent, eventData.data(), eventData.size(), &eventDesc);
    if (err != noErr) return params;
    
    // Parse parameters from the Apple Event
    long count;
    err = AECountItems(&eventDesc, &count);
    if (err == noErr) {
        for (long i = 1; i <= count; i++) {
            AEKeyword keyword;
            AEDesc param;
            err = AEGetNthDesc(&eventDesc, i, typeWildCard, &keyword, &param);
            if (err == noErr) {
                std::string paramKey = StringFromFourCharCode(keyword);
                // Skip system attributes (they start with 'key')
                if (paramKey.find("key") != 0) {
                    params.Set(paramKey, AEDescToNapiValue(env, &param));
                }
                AEDisposeDesc(&param);
            }
        }
    }
    
    AEDisposeDesc(&eventDesc);
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
    
    // Parse and create params object
    Napi::Object params = ParseAEParametersToJS(env, data.eventData);
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

/** C → JS trampoline */
static OSErr HandleAE(const AppleEvent* evt, AppleEvent* reply, void* refcon) {
    AEEventData aeData;
    
    // Get event class and ID from the Apple Event descriptor
    DescType eventClass, eventID;
    Size actualSize;
    
    OSErr err = AEGetAttributePtr(evt, keyEventClassAttr, typeType, 
                                  NULL, &eventClass, sizeof(eventClass), &actualSize);
    if (err == noErr) {
        aeData.suite = StringFromFourCharCode(eventClass);
    }
    
    err = AEGetAttributePtr(evt, keyEventIDAttr, typeType, 
                           NULL, &eventID, sizeof(eventID), &actualSize);
    if (err == noErr) {
        aeData.event = StringFromFourCharCode(eventID);
    }
    
    // Get transaction ID if present
    SInt32 transactionID;
    err = AEGetAttributePtr(evt, keyTransactionIDAttr, typeSInt32,
                           NULL, &transactionID, sizeof(transactionID), &actualSize);
    if (err == noErr) {
        aeData.transactionID = transactionID;
        aeData.hasTransaction = true;
    }
    
    // Capture raw Apple Event data for parameter parsing in JS thread
    Size dataSize = AEGetDescDataSize(evt);
    if (dataSize > 0) {
        aeData.eventData.resize(dataSize);
        err = AEGetDescData(evt, aeData.eventData.data(), dataSize);
        if (err != noErr) {
            aeData.eventData.clear(); // Clear on error
        }
    }
    
    // Parse target application info
    ParseTargetApplication(evt, aeData);
    
    // Call JS dispatcher asynchronously
    if (tsfn) {
        auto callback = [](Napi::Env env, Napi::Function jsDispatch, AEEventData* payload) {
            if (jsDispatch) {
                Napi::Object aeObj = CreateAEEventObject(env, *payload);
                Napi::Function doneCallback = Napi::Function::New(env, [](const Napi::CallbackInfo& info) {
                    // This would handle the response from JS
                    return info.Env().Undefined();
                });
                jsDispatch.Call({aeObj, doneCallback});
            }
            delete payload; // Clean up heap allocation
        };
        
        AEEventData* heapData = new AEEventData(aeData);
        
        napi_status status = tsfn.NonBlockingCall(heapData, callback);
        if (status != napi_ok) {
            delete heapData;
        }
    }
    
    return noErr;
}

/** JS tells native: "start listening for (suite,event)" */
Napi::Value addHandler(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    
    if (info.Length() < 2 || !info[0].IsString() || !info[1].IsString()) {
        Napi::TypeError::New(env, "Expected two string arguments").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    
    std::string suite = info[0].As<Napi::String>().Utf8Value();
    std::string event = info[1].As<Napi::String>().Utf8Value();
    
    NSString* key = [NSString stringWithFormat:@"%s%s", suite.c_str(), event.c_str()];
    
    if (!handlers[key]) {
        OSType suiteCode = FourCharCodeFromString(suite);
        OSType eventCode = FourCharCodeFromString(event);
        
        OSErr err = AEInstallEventHandler(suiteCode, eventCode, 
                                         NewAEEventHandlerUPP(HandleAE), 
                                         0, false);
        
        if (err == noErr) {
            handlers[key] = @YES;
        } else {
            Napi::Error::New(env, "Failed to install Apple Event handler").ThrowAsJavaScriptException();
            return env.Undefined();
        }
    }
    
    return env.Undefined();
}

/** Set the JavaScript dispatch function */
Napi::Value setDispatch(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    
    if (info.Length() < 1 || !info[0].IsFunction()) {
        Napi::TypeError::New(env, "Expected a function argument").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    
    Napi::Function jsDispatch = info[0].As<Napi::Function>();
    
    // Update the thread-safe function with the actual dispatch function
    tsfn = Napi::ThreadSafeFunction::New(
        env,
        jsDispatch,
        "osa_dispatch",
        0,  // unlimited queue
        1   // single thread
    );
    
    return env.Undefined();
}

/** init() */
Napi::Object Init(Napi::Env env, Napi::Object exports) {
    handlers = [NSMutableDictionary new];

    exports.Set("addHandler", Napi::Function::New(env, addHandler));
    exports.Set("setDispatch", Napi::Function::New(env, setDispatch));
    exports.Set("_dispatchReady", Napi::Boolean::New(env, true));
    
    return exports;
}

NODE_API_MODULE(osa_bridge, Init)
