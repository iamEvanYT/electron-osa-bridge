#include "handler.h"
#include "parser.h"
#include "utils.h"
#import <Foundation/Foundation.h>

// Global state
Napi::ThreadSafeFunction tsfn;   // JS dispatcher
NSMutableDictionary<NSString*, id>* handlers; // suite+event → true

/** C → JS trampoline */
OSErr HandleAE(const AppleEvent* evt, AppleEvent* reply, void* refcon) {
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
    
    // Parse target application info
    ParseTargetApplication(evt, aeData);
    
    // Parse parameters synchronously here where we have access to the Apple Event
    aeData.params = ParseAEParametersThreadSafe(evt);
    
    // Call JS dispatcher asynchronously
    if (tsfn) {
        auto callback = [](Napi::Env env, Napi::Function jsDispatch, AEEventData* payload) {
            if (jsDispatch) {
                Napi::Object aeObj = CreateAEEventObject(env, *payload);
                Napi::Function doneCallback = Napi::Function::New(env, [](const Napi::CallbackInfo& info) {
                    return info.Env().Undefined();
                });
                jsDispatch.Call({aeObj, doneCallback});
            }
            delete payload;
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