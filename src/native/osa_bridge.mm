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

// Structure to pass Apple Event data to JS
struct AEEventData {
    std::string suite;
    std::string event;
    // For now, we'll keep params simple
};

// Helper to create JS object from AEEventData
Napi::Object CreateAEEventObject(Napi::Env env, const AEEventData& data) {
    Napi::Object obj = Napi::Object::New(env);
    obj.Set("suite", Napi::String::New(env, data.suite));
    obj.Set("event", Napi::String::New(env, data.event));
    obj.Set("params", Napi::Object::New(env)); // Empty for now
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
    
    // TODO: Parse event parameters and populate aeData.params
    
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
