#pragma once

#include "types.h"
#include <napi.h>
#import <Foundation/Foundation.h>
#import <Carbon/Carbon.h>

// Global state
extern Napi::ThreadSafeFunction tsfn;   // JS dispatcher
extern NSMutableDictionary<NSString*, id>* handlers; // suite+event → true

/** C → JS trampoline */
OSErr HandleAE(const AppleEvent* evt, AppleEvent* reply, void* refcon);

/** JS tells native: "start listening for (suite,event)" */
Napi::Value addHandler(const Napi::CallbackInfo& info);

/** Set the JavaScript dispatch function */
Napi::Value setDispatch(const Napi::CallbackInfo& info); 