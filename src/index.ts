import os from "os";
import bindings from "bindings";

/** 4-char Apple-event code helpers */
export type AECode = string; // `"CrSu"`, `"ExJa"`, etc.

/** Incoming Apple-event payload */
export interface AEEvent {
  suite: AECode; // e.g. 'core'
  event: AECode; // e.g. 'getd'
  params: Record<AECode, unknown>; // decoded params, keyed by 4-char IDs
}

/** Return value – anything JS-serialisable turns into an AEDesc */
export type AEResult = string | number | boolean | null;

/** Handler signature */
export type AEHandler = (evt: AEEvent) => Promise<AEResult> | AEResult;

/** Internal registry */
const _registry = new Map<string, AEHandler>();

// Platform detection and native module loading
let native: any = null;
let isSupported = false;
let initializationError: string | null = null;

/**
 * Safely load the native module with proper error handling
 */
async function loadNativeModule(): Promise<void> {
  try {
    if (os.platform() !== "darwin") {
      initializationError = `Apple Events not supported on ${os.platform()}`;
      return;
    }

    // Use bindings to load the native module
    native = bindings("osa_bridge");

    if (native && typeof native.addHandler === "function") {
      isSupported = true;
    } else {
      throw new Error(
        "Native module loaded but required functions not available"
      );
    }
  } catch (error) {
    initializationError = `Failed to load native module: ${
      error instanceof Error ? error.message : String(error)
    }`;
    // Don't console.warn here - let the application decide how to handle this
  }
}

// Initialize the module
loadNativeModule().catch(() => {
  // Error already captured in initializationError
});

/** Register a handler for (suite,event). Wild-cards allowed. */
export function on(suite: AECode, event: AECode, handler: AEHandler): void {
  if (!isSupported) {
    // Store handlers even on unsupported platforms for future compatibility
    _registry.set(`${suite}${event}`, handler);
    return;
  }

  try {
    native.addHandler(suite, event); // install native hook if not present
    _registry.set(`${suite}${event}`, handler);
  } catch (error) {
    throw new Error(
      `Failed to register handler for ${suite}.${event}: ${
        error instanceof Error ? error.message : String(error)
      }`
    );
  }
}

/** Check if Apple Events are supported on this platform */
export function isAppleEventsSupported(): boolean {
  return isSupported;
}

/** Get current platform information */
export function getPlatformInfo(): {
  platform: string;
  supported: boolean;
  error?: string;
  architecture: string;
  nodeVersion: string;
} {
  return {
    platform: os.platform(),
    supported: isSupported,
    ...(initializationError && { error: initializationError }),
    architecture: os.arch(),
    nodeVersion: process.version,
  };
}

/** Get all registered handlers (useful for debugging) */
export function getRegisteredHandlers(): string[] {
  return Array.from(_registry.keys());
}

/** Remove a handler */
export function off(suite: AECode, event: AECode): boolean {
  const key = `${suite}${event}`;
  return _registry.delete(key);
}

/** Remove all handlers */
export function removeAllHandlers(): void {
  _registry.clear();
}

/** Called from native when an Apple event arrives */
const _dispatch = async (
  ae: AEEvent,
  done: (err: string | null, res?: AEResult) => void
) => {
  const key = `${ae.suite}${ae.event}`;
  const h =
    _registry.get(key) ||
    _registry.get(`${ae.suite}****`) ||
    _registry.get(`****${ae.event}`);

  if (!h) {
    return done(`No handler registered for ${ae.suite}.${ae.event}`);
  }

  try {
    const result = await h(ae);
    done(null, result);
  } catch (e: any) {
    done(e instanceof Error ? e.message : String(e));
  }
};

// Set up the dispatch function for the native module (only on macOS)
// Use a delayed initialization to ensure the native module is loaded
setTimeout(() => {
  if (
    native &&
    native._dispatchReady &&
    typeof native.setDispatch === "function"
  ) {
    try {
      native.setDispatch(_dispatch);
    } catch (error) {
      console.error("osa-bridge: Failed to set dispatch function:", error);
    }
  }
}, 0);

// For Electron compatibility - ensure module works in both main and renderer processes
if (
  typeof window !== "undefined" &&
  (window as any).process &&
  (window as any).process.type === "renderer"
) {
  console.warn(
    "osa-bridge: Running in Electron renderer process. Apple Events only work in the main process."
  );
}
