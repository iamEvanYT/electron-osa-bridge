#!/usr/bin/env node

import os from "os";
import { execSync } from "child_process";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

// Get __dirname equivalent in ES modules
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const platform = os.platform();
const arch = os.arch();

console.log(`🔧 Building osa-bridge on ${platform} ${arch}`);
console.log(`📍 Node.js version: ${process.version}`);

// Create build directory structure for all platforms
const buildDir = path.join(__dirname, "..", "build", "Release");
if (!fs.existsSync(buildDir)) {
  fs.mkdirSync(buildDir, { recursive: true });
  console.log(`📁 Created build directory: ${buildDir}`);
}

if (platform === "darwin") {
  console.log("🍎 macOS detected - building native module...");

  try {
    // Check if we have the necessary build tools
    try {
      execSync("which node-gyp", { stdio: "ignore" });
    } catch (error) {
      throw new Error(
        "node-gyp not found. Please install build tools: npm install -g node-gyp"
      );
    }

    // Check for Xcode command line tools on macOS
    try {
      execSync("xcode-select -p", { stdio: "ignore" });
    } catch (error) {
      console.warn(
        "⚠️  Xcode command line tools may not be installed. Run: xcode-select --install"
      );
    }

    console.log("🔨 Building native module for current architecture...");
    execSync("node-gyp rebuild", {
      stdio: "inherit",
      env: { ...process.env, npm_config_build_from_source: "true" },
    });

    // Verify the build was successful
    const nativeModulePath = path.join(buildDir, "osa_bridge.node");
    if (fs.existsSync(nativeModulePath)) {
      const stats = fs.statSync(nativeModulePath);
      console.log(
        `✅ Native module built successfully (${Math.round(
          stats.size / 1024
        )}KB)`
      );
      console.log(`📍 Location: ${nativeModulePath}`);

      // Check what architecture was built
      try {
        const fileOutput = execSync(`file "${nativeModulePath}"`, {
          encoding: "utf8",
        });
        console.log(`🏗️  Architecture: ${fileOutput.trim()}`);
      } catch (e) {
        console.log("ℹ️  Could not determine architecture");
      }
    } else {
      throw new Error("Native module was not created");
    }

    console.log("\n💡 For cross-architecture support:");
    console.log(
      "   Run 'npm run prebuildify:all' to build for both x64 and arm64"
    );
    console.log(
      "   This will create prebuilt binaries in the 'prebuilds/' directory"
    );
  } catch (error) {
    console.error("❌ Failed to build native module:");
    console.error(`   ${error.message}`);
    console.log(
      "📝 osa-bridge will run in compatibility mode (no Apple Events support)"
    );
    console.log(
      "   This is normal if you don't need Apple Events functionality."
    );

    // Create a placeholder file to indicate the build was attempted
    const placeholderPath = path.join(buildDir, ".build-attempted");
    fs.writeFileSync(
      placeholderPath,
      `Build attempted on ${new Date().toISOString()}\nError: ${error.message}`
    );
  }
} else {
  console.log(`🌐 ${platform} detected - skipping native module build`);
  console.log(
    "📝 osa-bridge will run in cross-platform mode (no Apple Events support)"
  );
  console.log("   Apple Events are only available on macOS.");

  // Create a placeholder to indicate this platform doesn't support native builds
  const placeholderPath = path.join(buildDir, ".platform-unsupported");
  fs.writeFileSync(
    placeholderPath,
    `Platform: ${platform}\nArchitecture: ${arch}\nNote: Apple Events not supported on this platform`
  );
}

// Check for prebuilt binaries
const prebuildsDir = path.join(__dirname, "..", "prebuilds");
if (fs.existsSync(prebuildsDir)) {
  console.log("\n📦 Checking prebuilt binaries...");
  try {
    const prebuilds = fs.readdirSync(prebuildsDir, { recursive: true });
    if (prebuilds.length > 0) {
      console.log("✅ Found prebuilt binaries:");
      prebuilds.forEach((file) => {
        if (typeof file === "string" && file.endsWith(".node")) {
          console.log(`   📄 ${file}`);
        }
      });
    } else {
      console.log("ℹ️  No prebuilt binaries found");
    }
  } catch (e) {
    console.log("ℹ️  Could not read prebuilds directory");
  }
} else {
  console.log("\n📦 No prebuilds directory found");
  if (platform === "darwin") {
    console.log(
      "   💡 Run 'npm run prebuildify:all' to create prebuilt binaries"
    );
  }
}

// Verify TypeScript compilation will work
try {
  console.log("\n🔍 Checking TypeScript configuration...");
  const tsconfigPath = path.join(__dirname, "..", "tsconfig.json");
  if (fs.existsSync(tsconfigPath)) {
    console.log("✅ TypeScript configuration found");
  } else {
    console.warn("⚠️  No tsconfig.json found");
  }
} catch (error) {
  console.warn(`⚠️  TypeScript check failed: ${error.message}`);
}

console.log("\n🎉 Build process completed");
console.log(`📊 Summary:`);
console.log(`   Platform: ${platform} (${arch})`);
console.log(
  `   Native module: ${platform === "darwin" ? "attempted" : "not applicable"}`
);
console.log(
  `   Cross-platform mode: ${
    platform !== "darwin" ? "enabled" : "fallback available"
  }`
);

if (platform === "darwin") {
  console.log(`\n🚀 Next steps for distribution:`);
  console.log(
    `   1. Run 'npm run prebuildify:all' to build for multiple architectures`
  );
  console.log(`   2. Run 'npm run test' to verify everything works`);
  console.log(
    `   3. The package will automatically load the correct binary for each user's system`
  );
}
