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
    
    // Check if this event expects a reply
    // Simply check if reply is not NULL - the OS provides a reply descriptor when one is expected
    Boolean hasReply = (reply != NULL);
    
    // For events that expect a reply, we need to suspend the event and handle it asynchronously
    if (hasReply) {
        // Create a suspended reply
        AppleEvent* suspendedReply = new AppleEvent;
        *suspendedReply = *reply;
        
        // Suspend the Apple Event (tell the system we'll reply later)
        err = AESuspendTheCurrentEvent(evt);
        if (err != noErr) {
            delete suspendedReply;
            return err;
        }
        
        // Call JS dispatcher asynchronously with the suspended reply
        if (tsfn) {
            struct CallbackData {
                AEEventData* payload;
                AppleEvent* suspendedReply;
                AppleEvent suspendedEvent;
            };
            
            auto callbackData = new CallbackData{new AEEventData(aeData), suspendedReply, *evt};
            
            auto callback = [](Napi::Env env, Napi::Function jsDispatch, CallbackData* data) {
                if (jsDispatch) {
                    Napi::Object aeObj = CreateAEEventObject(env, *data->payload);
                    
                    // Create a proper done callback that handles the suspended reply
                    Napi::Function doneCallback = Napi::Function::New(env, [data](const Napi::CallbackInfo& info) {
                        Napi::Env env = info.Env();
                        
                        OSErr replyErr = noErr;
                        
                        // Check if error was passed
                        if (info.Length() > 0 && !info[0].IsNull() && !info[0].IsUndefined()) {
                            // Error case
                            std::string errorMessage = info[0].ToString().Utf8Value();
                            CFStringRef errorStr = CFStringCreateWithCString(NULL, errorMessage.c_str(), kCFStringEncodingUTF8);
                            if (errorStr) {
                                AEPutParamPtr(data->suspendedReply, keyErrorString, typeUTF8Text, 
                                            CFStringGetCStringPtr(errorStr, kCFStringEncodingUTF8), 
                                            CFStringGetLength(errorStr));
                                CFRelease(errorStr);
                            }
                            replyErr = errAEEventFailed;
                        } 
                        // Check if result was passed
                        else if (info.Length() > 1) {
                            // Success case - put the result in the reply
                            Napi::Value jsResult = info[1];
                            if (jsResult.IsString()) {
                                std::string strValue = jsResult.ToString().Utf8Value();
                                AEPutParamPtr(data->suspendedReply, keyDirectObject, typeUTF8Text, 
                                            strValue.c_str(), strValue.length());
                            } else if (jsResult.IsNumber()) {
                                double numValue = jsResult.ToNumber().DoubleValue();
                                if (numValue == floor(numValue)) {
                                    SInt32 intValue = static_cast<SInt32>(numValue);
                                    AEPutParamPtr(data->suspendedReply, keyDirectObject, typeSInt32, 
                                                &intValue, sizeof(intValue));
                                } else {
                                    AEPutParamPtr(data->suspendedReply, keyDirectObject, typeIEEE64BitFloatingPoint, 
                                                &numValue, sizeof(numValue));
                                }
                            } else if (jsResult.IsBoolean()) {
                                Boolean boolValue = jsResult.ToBoolean().Value();
                                AEPutParamPtr(data->suspendedReply, keyDirectObject, typeBoolean, 
                                            &boolValue, sizeof(boolValue));
                            } else if (jsResult.IsNull() || jsResult.IsUndefined()) {
                                // Put null in reply
                                AEPutParamPtr(data->suspendedReply, keyDirectObject, typeNull, NULL, 0);
                            }
                        }
                        
                        // Resume the suspended event with the reply
                        AEResumeTheCurrentEvent(&data->suspendedEvent, data->suspendedReply, 
                                               (AEEventHandlerUPP)kAENoDispatch, (SRefCon)(intptr_t)replyErr);
                        
                        // Clean up
                        delete data->suspendedReply;
                        delete data;
                        
                        return env.Undefined();
                    });
                    
                    jsDispatch.Call({aeObj, doneCallback});
                }
                
                delete data->payload;
            };
            
            napi_status status = tsfn.NonBlockingCall(callbackData, callback);
            
            if (status != napi_ok) {
                // Failed to call JS - resume with error
                AEResumeTheCurrentEvent(evt, reply, (AEEventHandlerUPP)kAENoDispatch, (SRefCon)(intptr_t)errAEEventFailed);
                delete callbackData->payload;
                delete callbackData->suspendedReply;
                delete callbackData;
                return errAEEventFailed;
            }
        }
        
        // Return special code to indicate we'll handle the reply later
        return errAEWaitCanceled;
    } else {
        // No reply expected - handle as before (fire and forget)
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