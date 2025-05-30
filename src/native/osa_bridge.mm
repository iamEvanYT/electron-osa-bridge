#include <napi.h>
#include "handler.h"
#import <Foundation/Foundation.h>

/** init() */
Napi::Object Init(Napi::Env env, Napi::Object exports) {
    handlers = [NSMutableDictionary new];

    exports.Set("addHandler", Napi::Function::New(env, addHandler));
    exports.Set("setDispatch", Napi::Function::New(env, setDispatch));
    exports.Set("_dispatchReady", Napi::Boolean::New(env, true));
    
    return exports;
}

NODE_API_MODULE(osa_bridge, Init) 