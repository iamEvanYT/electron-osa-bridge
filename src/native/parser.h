#pragma once

#include "types.h"
#include <napi.h>
#import <Carbon/Carbon.h>

// Helper to convert AEDesc to ParsedAEParam (thread-safe data)
ParsedAEParam AEDescToParsedParam(const AEDesc* desc);

// Helper to convert ParsedAEParam to Napi::Value in JS thread
Napi::Value ParsedParamToNapiValue(Napi::Env env, const ParsedAEParam& param);

// Helper to parse Apple Event parameters to thread-safe data
std::map<std::string, ParsedAEParam> ParseAEParametersThreadSafe(const AppleEvent* evt);

// Helper to get application info from Apple Event
void ParseTargetApplication(const AppleEvent* evt, AEEventData& aeData);

// Helper to create JS object from AEEventData
Napi::Object CreateAEEventObject(Napi::Env env, const AEEventData& data); 