#!/bin/bash
# One-time setup: install Playwright browsers for web testing
set -e

echo "Installing Playwright Chromium browser..."
npx playwright install chromium

echo ""
echo "Setup complete. Test with:"
echo "  node $(dirname "$0")/web-test.mjs screenshot https://example.com /tmp/test.png"
