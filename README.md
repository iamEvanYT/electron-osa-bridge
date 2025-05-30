# OSA Bridge

A cross-platform Node.js native addon for handling Apple Events (OSA - Open Scripting Architecture) designed specifically for Electron applications.

## Features

- 🍎 **Apple Events support** on macOS with native performance
- 🌐 **Cross-platform compatible** - works on Windows, Linux, and macOS
- ⚡ **Electron optimized** - designed for both main and renderer processes
- 🎯 **Event handler registration** with support for specific and wildcard patterns
- 🔄 **Asynchronous event handling** with Promise support
- 📝 **TypeScript definitions** included with comprehensive type safety
- 🛡️ **Graceful fallbacks** - never crashes on unsupported platforms
- 🔧 **Development friendly** - detailed platform information and debugging tools

## Installation

```bash
npm install electron-osa-bridge
```

### Dependencies & Electron Compatibility

**Important**: `node-gyp-build` is a **runtime dependency** (not devDependency) - it's required to load the correct prebuilt binary for your platform.

**Electron Compatibility:**

- ✅ **No `electron-rebuild` required** - Uses NAPI for ABI stability across versions
- ✅ **Automatic binary selection** - Works with all supported Electron versions
- ✅ **Universal binaries included** - Supports both Intel and Apple Silicon
- ✅ **Cross-platform safe** - No runtime errors on any platform

**Supported versions**: Node.js 18+, Electron 22+ (any version supporting Node.js 18+)

The module will automatically:

- Build the native module on macOS (requires Xcode Command Line Tools)
- Skip native compilation on other platforms (cross-platform mode)
- Work seamlessly regardless of platform

## Quick Start

```typescript
import {
  on,
  isAppleEventsSupported,
  getPlatformInfo,
  AEEvent,
  AEResult,
} from "osa-bridge";

// Check platform compatibility
console.log("Platform info:", getPlatformInfo());

if (isAppleEventsSupported()) {
  console.log("🍎 Apple Events available!");

  // Register handlers for Apple Events
  on("core", "getd", async (event: AEEvent): Promise<AEResult> => {
    console.log("Received get data event:", event);
    return "Hello from Electron!";
  });
} else {
  console.log("🌐 Running in cross-platform mode");
  // Your app can still register handlers - they just won't receive events
}
```

## Platform Support

| Platform    | Apple Events     | Native Module | Notes                               |
| ----------- | ---------------- | ------------- | ----------------------------------- |
| **macOS**   | ✅ Full Support  | ✅ Built      | Complete Apple Events functionality |
| **Windows** | ❌ Not Available | ⏭️ Skipped    | Graceful fallback mode              |
| **Linux**   | ❌ Not Available | ⏭️ Skipped    | Graceful fallback mode              |

### macOS Requirements

- macOS 11.0 or later
- Xcode Command Line Tools: `xcode-select --install`
- Node.js 18 or later

### Other Platforms

- No additional requirements
- All functions available (no-op implementations)
- Zero runtime errors

## Electron Integration

### Main Process (Recommended)

```typescript
// main.js
import { app } from "electron";
import { on, isAppleEventsSupported } from "osa-bridge";

app.whenReady().then(() => {
  if (isAppleEventsSupported()) {
    // Handle quit events
    on("****", "quit", async (event) => {
      console.log("Application quitting:", event);
      app.quit();
      return null;
    });

    // Handle file open events
    on("core", "odoc", async (event) => {
      console.log("Open document request:", event);
      // Handle file opening logic
      return "File opened successfully";
    });
  }
});
```

### Renderer Process

```typescript
// The module detects renderer process and shows appropriate warnings
// Apple Events only work in the main process
import { getPlatformInfo, isAppleEventsSupported } from "osa-bridge";

const info = getPlatformInfo();
console.log("Running in renderer process:", info);
```

## API Reference

### Functions

#### `on(suite: AECode, event: AECode, handler: AEHandler): void`

Register a handler for Apple Events.

```typescript
// Specific event
on("core", "getd", async (event) => {
  /* ... */
});

// Wildcard suite (any application)
on("****", "quit", async (event) => {
  /* ... */
});

// Wildcard event (any event from core suite)
on("core", "****", async (event) => {
  /* ... */
});
```

#### `off(suite: AECode, event: AECode): boolean`

Remove a specific handler.

```typescript
const removed = off("core", "getd");
console.log("Handler removed:", removed);
```

#### `removeAllHandlers(): void`

Remove all registered handlers.

#### `isAppleEventsSupported(): boolean`

Check if Apple Events are supported on the current platform.

#### `getPlatformInfo(): PlatformInfo`

Get detailed platform information.

```typescript
interface PlatformInfo {
  platform: string; // 'darwin', 'win32', 'linux'
  supported: boolean; // Apple Events support status
  error?: string; // Error message if module failed to load
  architecture: string; // 'x64', 'arm64'
  nodeVersion: string; // Node.js version
}
```

#### `getRegisteredHandlers(): string[]`

Get list of all registered handler keys (useful for debugging).

### Types

```typescript
type AECode = string; // 4-character Apple Event code

interface AEEvent {
  suite: AECode; // Event suite (e.g., 'core')
  event: AECode; // Event ID (e.g., 'getd')
  params: Record<AECode, unknown>; // Event parameters
}

type AEResult = string | number | boolean | null;
type AEHandler = (evt: AEEvent) => Promise<AEResult> | AEResult;
```

## Apple Event Codes

### Common Suites

- `core` - Core suite (standard events)
- `misc` - Miscellaneous events
- `reqd` - Required events
- `****` - Wildcard (any suite)

### Common Events

- `getd` - Get data
- `setd` - Set data
- `quit` - Quit application
- `oapp` - Open application
- `odoc` - Open document
- `****` - Wildcard (any event)

## Building

```bash
# Build everything
npm run build

# Build only TypeScript
npm run build:ts

# Build only native module (macOS)
npm run build:native

# Test platform compatibility
npm test

# Development with auto-rebuild
npm run dev
```

## Testing

Test the module on any platform:

```bash
npm test
```

This will verify:

- ✅ Module imports correctly
- ✅ Platform detection works
- ✅ Handler registration/removal
- ✅ Cross-platform compatibility
- ✅ Electron compatibility

## Troubleshooting

### Build Issues on macOS

```bash
# Install Xcode Command Line Tools
xcode-select --install

# Reinstall with fresh build
npm run clean && npm install && npm run build
```

### Module Not Working in Electron

- Ensure you're using it in the main process
- Check that your Electron app has proper permissions
- Verify with `getPlatformInfo()` that the module loaded correctly

### Cross-Platform Development

```typescript
// Safe pattern for cross-platform apps
import { isAppleEventsSupported, on } from "osa-bridge";

// Always safe to call, even on non-macOS
on("core", "quit", async (event) => {
  // This handler will only be called on macOS
  return handleQuit(event);
});

// Check support before showing macOS-specific UI
if (isAppleEventsSupported()) {
  showAppleEventsFeatures();
}
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Test on multiple platforms
4. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) file for details.
