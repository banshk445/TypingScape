#!/bin/bash
set -e
cd "$(dirname "$0")"
swift build
codesign --force --sign - --identifier "com.banshk.TypingScape" .build/debug/TypingScape
exec ./.build/debug/TypingScape
