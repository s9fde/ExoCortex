#!/usr/bin/env swift

//
//  generate-app-icons.swift
//  Generates app icons using SF Symbols for ExoCortex
//
//  Usage: swift generate-app-icons.swift
//

import Cocoa

// Configuration
let symbolName = "tornado"
let outputPath = "../ExoCortex/Assets.xcassets/AppIcon.appiconset"

// Background and foreground colors
let backgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.15, alpha: 1.0)  // Dark blue-gray
let symbolColor = NSColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 1.0)       // Bright blue

// Icon sizes needed for iOS and macOS - all in actual pixels
let iconSizes: [(name: String, pixels: Int, platform: String?)] = [
    // iOS - single 1024x1024 universal icon
    ("AppIcon-1024", 1024, "ios"),
    ("AppIcon-1024-dark", 1024, "ios-dark"),
    ("AppIcon-1024-tinted", 1024, "ios-tinted"),
    // macOS icons - actual pixel dimensions
    ("AppIcon-16@1x", 16, "mac"),
    ("AppIcon-16@2x", 32, "mac"),
    ("AppIcon-32@1x", 32, "mac"),
    ("AppIcon-32@2x", 64, "mac"),
    ("AppIcon-128@1x", 128, "mac"),
    ("AppIcon-128@2x", 256, "mac"),
    ("AppIcon-256@1x", 256, "mac"),
    ("AppIcon-256@2x", 512, "mac"),
    ("AppIcon-512@1x", 512, "mac"),
    ("AppIcon-512@2x", 1024, "mac"),
]

func generateIcon(pixels: Int, platform: String?) -> Data? {
    // Create bitmap rep at EXACT pixel size (not points)
    guard let bitmapRep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        print("Error: Could not create bitmap rep")
        return nil
    }
    
    // Set size to match pixels (1:1 scale)
    bitmapRep.size = NSSize(width: pixels, height: pixels)
    
    // Create graphics context
    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: bitmapRep) else {
        print("Error: Could not create graphics context")
        return nil
    }
    NSGraphicsContext.current = context
    
    // Draw background
    let isDark = platform == "ios-dark"
    let isTinted = platform == "ios-tinted"
    
    let bgColor: NSColor
    if isTinted {
        bgColor = NSColor(white: 0.2, alpha: 1.0)
    } else if isDark {
        bgColor = NSColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1.0)
    } else {
        bgColor = backgroundColor
    }
    
    bgColor.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: pixels, height: pixels)).fill()
    
    // Get SF Symbol
    guard let symbolImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
        print("Error: Could not load SF Symbol '\(symbolName)'")
        NSGraphicsContext.restoreGraphicsState()
        return nil
    }
    
    // Configure symbol - use 50% of pixel size for nice centering
    let symbolPointSize = CGFloat(pixels) * 0.5
    let config = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .medium)
    guard let configuredSymbol = symbolImage.withSymbolConfiguration(config) else {
        print("Error: Could not configure symbol")
        NSGraphicsContext.restoreGraphicsState()
        return nil
    }
    
    // Calculate centered position
    let symbolSize = configuredSymbol.size
    let x = (CGFloat(pixels) - symbolSize.width) / 2
    let y = (CGFloat(pixels) - symbolSize.height) / 2
    let symbolRect = NSRect(x: x, y: y, width: symbolSize.width, height: symbolSize.height)
    
    // Draw symbol with tint color
    let symColor: NSColor
    if isTinted {
        symColor = .white
    } else if isDark {
        symColor = NSColor(red: 0.5, green: 0.8, blue: 1.0, alpha: 1.0)
    } else {
        symColor = symbolColor
    }
    
    // Create a tinted version of the symbol
    let tintedSymbol = NSImage(size: configuredSymbol.size)
    tintedSymbol.lockFocus()
    configuredSymbol.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1.0)
    symColor.set()
    NSRect(origin: .zero, size: configuredSymbol.size).fill(using: .sourceAtop)
    tintedSymbol.unlockFocus()
    
    // Draw tinted symbol
    tintedSymbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    
    NSGraphicsContext.restoreGraphicsState()
    
    // Return PNG data
    return bitmapRep.representation(using: .png, properties: [:])
}

func saveIcon(data: Data, name: String, toPath path: String) -> Bool {
    let url = URL(fileURLWithPath: path).appendingPathComponent("\(name).png")
    do {
        try data.write(to: url)
        print("Generated: \(name).png")
        return true
    } catch {
        print("Error writing \(name).png: \(error)")
        return false
    }
}

// Get script directory
let scriptPath = CommandLine.arguments[0]
let scriptDir = URL(fileURLWithPath: scriptPath).deletingLastPathComponent().path
let fullOutputPath = URL(fileURLWithPath: scriptDir).appendingPathComponent(outputPath).path

print("Generating app icons using SF Symbol '\(symbolName)'...")
print("Output directory: \(fullOutputPath)")

// Create output directory if needed
let fileManager = FileManager.default
if !fileManager.fileExists(atPath: fullOutputPath) {
    try? fileManager.createDirectory(atPath: fullOutputPath, withIntermediateDirectories: true)
}

var generatedCount = 0

for iconConfig in iconSizes {
    if let data = generateIcon(pixels: iconConfig.pixels, platform: iconConfig.platform) {
        if saveIcon(data: data, name: iconConfig.name, toPath: fullOutputPath) {
            generatedCount += 1
        }
    }
}

// Generate Contents.json
let contentsJson = """
{
  "images" : [
    {
      "filename" : "AppIcon-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "filename" : "AppIcon-1024-dark.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "tinted"
        }
      ],
      "filename" : "AppIcon-1024-tinted.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "filename" : "AppIcon-16@1x.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "16x16"
    },
    {
      "filename" : "AppIcon-16@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "16x16"
    },
    {
      "filename" : "AppIcon-32@1x.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "32x32"
    },
    {
      "filename" : "AppIcon-32@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "32x32"
    },
    {
      "filename" : "AppIcon-128@1x.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128"
    },
    {
      "filename" : "AppIcon-128@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128"
    },
    {
      "filename" : "AppIcon-256@1x.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "filename" : "AppIcon-256@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    },
    {
      "filename" : "AppIcon-512@1x.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512"
    },
    {
      "filename" : "AppIcon-512@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""

let contentsPath = URL(fileURLWithPath: fullOutputPath).appendingPathComponent("Contents.json")
do {
    try contentsJson.write(to: contentsPath, atomically: true, encoding: .utf8)
    print("Generated: Contents.json")
} catch {
    print("Error writing Contents.json: \(error)")
}

print("\nDone! Generated \(generatedCount) icons.")
