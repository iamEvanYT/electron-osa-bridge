{
  "targets": [{
    "target_name": "osa_bridge",
    "sources": ["src/native/osa_bridge.mm"],
    "include_dirs": [
      "<!@(node -p \"require('node-addon-api').include\")",
      "include"
    ],
    "dependencies": [
      "<!(node -p \"require('node-addon-api').gyp\")"
    ],
    "cflags!": ["-fno-exceptions"],
    "cflags_cc!": ["-fno-exceptions"],
    "xcode_settings": {
      "OTHER_LDFLAGS": ["-framework", "Cocoa", "-framework", "Carbon"],
      "GCC_ENABLE_CPP_EXCEPTIONS": "YES",
      "CLANG_CXX_LIBRARY": "libc++",
      "MACOSX_DEPLOYMENT_TARGET": "11.0",
      "OTHER_CPLUSPLUSFLAGS": ["-std=c++17"]
    },
    "defines": [
      "NAPI_DISABLE_CPP_EXCEPTIONS",
      "NAPI_VERSION=6"
    ],
    "conditions": [
      ["OS=='mac'", {
        "cflags+": ["-fvisibility=hidden"],
        "xcode_settings": {
          "GCC_SYMBOLS_PRIVATE_EXTERN": "YES"
        }
      }]
    ]
  }]
}
