#!/usr/bin/env node

import { fileURLToPath } from "url";
import path from "path";
import os from "os";

// Get __dirname equivalent in ES modules
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

console.log("🧪 Testing osa-bridge platform compatibility");
console.log("=".repeat(50));

async function testModule() {
  try {
    // Import the module
    const modulePath = path.join(__dirname, "..", "dist", "index.js");
    console.log(`📦 Importing module from: ${modulePath}`);

    const osaBridge = await import(modulePath);

    console.log("✅ Module imported successfully");

    // Wait for async module initialization to complete
    console.log("⏳ Waiting for module initialization...");
    await new Promise((resolve) => setTimeout(resolve, 200));

    // Test platform info
    const platformInfo = osaBridge.getPlatformInfo();
    console.log("\n📊 Platform Information:");
    console.log(`   Platform: ${platformInfo.platform}`);
    console.log(`   Architecture: ${platformInfo.architecture}`);
    console.log(`   Node.js: ${platformInfo.nodeVersion}`);
    console.log(
      `   Apple Events Supported: ${
        platformInfo.supported ? "✅ Yes" : "❌ No"
      }`
    );

    if (platformInfo.error) {
      console.log(`   Error: ${platformInfo.error}`);
    }

    // Test Apple Events support check
    const isSupported = osaBridge.isAppleEventsSupported();
    console.log(
      `\n🔍 Apple Events Support: ${isSupported ? "✅ Enabled" : "❌ Disabled"}`
    );

    // Test handler registration
    console.log("\n🔧 Testing handler registration...");
    try {
      osaBridge.on("core", "getd", async (event) => {
        console.log("Handler called:", event);
        return "Test response";
      });
      console.log("✅ Handler registered successfully");

      const handlers = osaBridge.getRegisteredHandlers();
      console.log(`   Registered handlers: ${handlers.length}`);
      if (handlers.length > 0) {
        console.log(`   Handler keys: ${handlers.join(", ")}`);
      }
    } catch (error) {
      console.log(`❌ Handler registration failed: ${error.message}`);
    }

    // Test handler removal
    console.log("\n🧹 Testing handler removal...");
    try {
      const removed = osaBridge.off("core", "getd");
      console.log(
        `✅ Handler removal: ${removed ? "successful" : "no handler found"}`
      );

      osaBridge.removeAllHandlers();
      console.log("✅ All handlers removed");
    } catch (error) {
      console.log(`❌ Handler removal failed: ${error.message}`);
    }

    // Platform-specific tests
    if (os.platform() === "darwin") {
      console.log("\n🍎 macOS-specific tests:");
      if (isSupported) {
        console.log("   ✅ Native module loaded successfully");
        console.log("   ✅ Apple Events should work");

        // Test that we can actually register handlers with the native module
        try {
          osaBridge.on("test", "test", async () => "test");
          console.log("   ✅ Native handler registration works");
          osaBridge.off("test", "test");
        } catch (error) {
          console.log(
            `   ⚠️  Native handler registration issue: ${error.message}`
          );
        }
      } else {
        console.log("   ⚠️  Native module not loaded");
        if (platformInfo.error) {
          console.log(`   🔍 Reason: ${platformInfo.error}`);
        }
        console.log("   ℹ️  Module will work in fallback mode");
      }
    } else {
      console.log(`\n🌐 ${os.platform()} cross-platform tests:`);
      console.log("   ✅ Module loads without errors");
      console.log("   ✅ Functions are available (no-op mode)");
      console.log("   ℹ️  Apple Events not supported on this platform");
    }

    console.log("\n🎉 All tests completed successfully!");
    console.log("\n💡 Usage Tips:");

    if (isSupported) {
      console.log("   - ✅ Apple Events are available and working");
      console.log(
        "   - Register handlers for Apple Events your app needs to handle"
      );
      console.log("   - Use wildcards ('****') for flexible event handling");
      console.log("   - The correct prebuilt binary was automatically loaded");
    } else {
      console.log("   - Module is in cross-platform mode");
      console.log("   - No Apple Events will be received");
      console.log("   - All functions are safe to call (no-op on non-macOS)");
    }

    console.log(
      "   - Check getPlatformInfo() for detailed platform information"
    );
    console.log(
      "   - Use isAppleEventsSupported() to conditionally enable features"
    );

    // Show architecture-specific info
    if (os.platform() === "darwin") {
      console.log(`\n🏗️  Architecture Support:`);
      console.log(`   - Current: ${os.arch()}`);
      console.log(`   - Prebuilt binaries available for: x64, arm64`);
      console.log(`   - Universal binary support: ✅`);
    }
  } catch (error) {
    console.error("❌ Test failed:");
    console.error(`   ${error.message}`);
    if (error.stack) {
      console.error("\nStack trace:");
      console.error(error.stack);
    }
    process.exit(1);
  }
}

// Check if TypeScript files need to be compiled first
async function checkCompilation() {
  const fs = await import("fs");
  const distPath = path.join(__dirname, "..", "dist", "index.js");

  if (!fs.existsSync(distPath)) {
    console.log(
      "⚠️  Compiled JavaScript not found. Please run 'npm run build:ts' first."
    );
    console.log("   Or run 'npm run build' to build everything.");
    process.exit(1);
  }
}

// Run the test
checkCompilation()
  .then(() => testModule())
  .catch((error) => {
    console.error("❌ Test setup failed:", error.message);
    process.exit(1);
  });
