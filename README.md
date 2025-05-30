# OSA Bridge

A Node.js native addon for handling Apple Events (OSA - Open Scripting Architecture) on macOS with cross-platform compatibility.

## Features

- 🍎 **Apple Events support** on macOS using Carbon framework
- 🌐 **Cross-platform compatible** - graceful fallbacks on Windows and Linux
- ⚡ **Asynchronous event handling** with Promise support
- 🎯 **Event handler registration** with wildcard pattern support
- 📝 **TypeScript definitions** included
- 🛡️ **Graceful degradation** - never crashes on unsupported platforms
- 🔧 **Platform detection** and debugging utilities
- ⚙️ **Electron compatible** with process type detection

## Installation

```bash
npm install electron-osa-bridge
```

### Requirements

**macOS:**

- macOS with Carbon framework support
- Xcode Command Line Tools: `xcode-select --install`
- Node.js with native addon support

**Other platforms:**

- No additional requirements (module provides no-op implementations)

## Quick Start

```typescript
import {
  on,
  isAppleEventsSupported,
  getPlatformInfo,
  AEEvent,
  AEResult,
} from "electron-osa-bridge";

// Check if Apple Events are supported
console.log("Platform info:", getPlatformInfo());

if (isAppleEventsSupported()) {
  console.log("🍎 Apple Events supported!");

  // Register a handler for "get data" events
  on("core", "getd", async (event: AEEvent): Promise<AEResult> => {
    console.log("Received Apple Event:", event);
    return "Hello from Node.js!";
  });

  // Handle application quit events
  on("****", "quit", async (event: AEEvent): Promise<AEResult> => {
    console.log("Quit event received");
    process.exit(0);
  });
} else {
  console.log("🌐 Running in compatibility mode (no Apple Events)");
}
```

## Platform Support

| Platform    | Apple Events | Status        | Notes                                  |
| ----------- | ------------ | ------------- | -------------------------------------- |
| **macOS**   | ✅ Supported | Native        | Full Apple Events functionality        |
| **Windows** | ❌ N/A       | Compatibility | Functions available but non-functional |
| **Linux**   | ❌ N/A       | Compatibility | Functions available but non-functional |

## API Reference

### Core Functions

#### `on(suite: AECode, event: AECode, handler: AEHandler): void`

Register a handler for Apple Events.

```typescript
// Handle specific events
on("core", "getd", async (event) => {
  return "Data retrieved";
});

// Use wildcards for any suite
on("****", "quit", async (event) => {
  process.exit(0);
});

// Use wildcards for any event in a suite
on("core", "****", async (event) => {
  console.log(`Core event: ${event.event}`);
  return null;
});
```

#### `off(suite: AECode, event: AECode): boolean`

Remove a specific event handler.

```typescript
const wasRemoved = off("core", "getd");
console.log("Handler removed:", wasRemoved);
```

#### `removeAllHandlers(): void`

Remove all registered event handlers.

```typescript
removeAllHandlers();
```

#### `isAppleEventsSupported(): boolean`

Check if Apple Events are supported on the current platform.

```typescript
if (isAppleEventsSupported()) {
  // Safe to use Apple Events functionality
}
```

#### `getPlatformInfo(): PlatformInfo`

Get detailed platform and support information.

```typescript
const info = getPlatformInfo();
console.log(info);
// Output example:
// {
//   platform: "darwin",
//   supported: true,
//   architecture: "arm64",
//   nodeVersion: "v20.0.0"
// }
```

#### `getRegisteredHandlers(): string[]`

Get list of all registered handler keys (useful for debugging).

```typescript
const handlers = getRegisteredHandlers();
console.log("Registered handlers:", handlers);
// Output: ["coregetd", "****quit"]
```

### Types

```typescript
// 4-character Apple Event code
type AECode = string;

// Incoming Apple Event structure
interface AEEvent {
  suite: AECode; // e.g., 'core'
  event: AECode; // e.g., 'getd'
  params: Record<AECode, unknown>; // Event parameters (currently empty)
}

// Return value from handlers
type AEResult = string | number | boolean | null;

// Event handler function signature
type AEHandler = (evt: AEEvent) => Promise<AEResult> | AEResult;

// Platform information
interface PlatformInfo {
  platform: string; // 'darwin', 'win32', 'linux'
  supported: boolean; // Apple Events support status
  error?: string; // Error message if module failed to load
  architecture: string; // 'x64', 'arm64', etc.
  nodeVersion: string; // Current Node.js version
}
```

## Apple Event Codes

### Common Event Suites

- `core` - Core Apple Events (standard system events)
- `misc` - Miscellaneous events
- `reqd` - Required events
- `****` - Wildcard (matches any suite)

### Common Event Types

- `getd` - Get data
- `setd` - Set data
- `quit` - Quit application
- `oapp` - Open application
- `odoc` - Open document
- `****` - Wildcard (matches any event)

## Electron Integration

The module automatically detects when running in Electron and provides appropriate warnings:

### Main Process (Recommended)

```typescript
// main.js
import { app } from "electron";
import { on, isAppleEventsSupported } from "electron-osa-bridge";

app.whenReady().then(() => {
  if (isAppleEventsSupported()) {
    on("****", "quit", async () => {
      app.quit();
      return null;
    });
  }
});
```

### Renderer Process

Apple Events only work in the main process. The module will log a warning if used in a renderer process:

```
electron-osa-bridge: Running in Electron renderer process. Apple Events only work in the main process.
```

## Error Handling

The module is designed to never crash your application:

```typescript
// Safe on all platforms
on("core", "getd", async (event) => {
  return "This works on macOS, is ignored elsewhere";
});

// Check for errors
const info = getPlatformInfo();
if (info.error) {
  console.log("Module load error:", info.error);
}
```

Common error scenarios:

- **Non-macOS platforms**: Functions are no-ops, `isAppleEventsSupported()` returns `false`
- **Missing native module**: Error captured in `getPlatformInfo().error`
- **Electron renderer process**: Warning logged, functions still available but non-functional

## Building from Source

```bash
# Install dependencies
npm install

# Build native module (macOS only)
npm run build

# Run tests
npm test
```

### Build Requirements (macOS)

```bash
# Install Xcode Command Line Tools
xcode-select --install

# Verify installation
xcode-select -p
```

## Current Limitations

- **Event parameters**: Currently not parsed from incoming Apple Events (returns empty object)
- **Event responses**: Basic implementation, may need enhancement for complex return values
- **Error handling**: Native-level errors may need more detailed reporting

## Development Status

This is an active project. Current implementation provides:

- ✅ Event handler registration and dispatch
- ✅ Cross-platform compatibility
- ✅ Basic Apple Event receiving
- 🔄 Event parameter parsing (in development)
- 🔄 Enhanced error reporting (planned)

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature-name`
3. Test on macOS (if possible)
4. Ensure cross-platform compatibility
5. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) file for details.
