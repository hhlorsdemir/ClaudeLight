#!/bin/bash
# ClaudeLight.app'ı derler. Kullanım: ./build.sh
set -e
cd "$(dirname "$0")"
APP="ClaudeLight.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
swiftc -O -framework Cocoa -o "$APP/Contents/MacOS/ClaudeLight" main.swift
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Derlendi: $(pwd)/$APP"
