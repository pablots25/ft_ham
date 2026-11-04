#!/bin/bash
# Integrate paywall from feature/premium branch

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FT_HAM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🔄 FT Ham Paywall Integration"
echo ""

cd "$FT_HAM_DIR"

# Check we're on main
current_branch=$(git branch --show-current)
if [ "$current_branch" != "main" ]; then
    echo "⚠️  Warning: You're on branch '$current_branch', not 'main'"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check for uncommitted changes
if ! git diff-index --quiet HEAD --; then
    echo "❌ You have uncommitted changes. Please commit or stash them first."
    git status --short
    exit 1
fi

echo "📋 Files that will be merged from feature/premium:"
git diff main..feature/premium --name-only
echo ""

read -p "Proceed with merge? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "🔀 Merging feature/premium into $current_branch..."
git merge feature/premium --no-ff -m "Integrate paywall and premium IAP system"

echo ""
echo "✅ Paywall code merged successfully!"
echo ""
echo "📁 New/Modified files:"
echo "  - ft8_ham/Models/PremiumManager.swift (StoreKit IAP manager)"
echo "  - ft8_ham/Views/Other/PremiumPaywallView.swift (Paywall UI)"
echo "  - Configuration.storekit (IAP product config)"
echo "  - ft8_ham/Views/Configuration/ConfigurationView.swift (Updated with premium gates)"
echo ""
echo "📖 Next Steps:"
echo ""
echo "1. Review the merged code:"
echo "   git log -1 --stat"
echo ""
echo "2. Add feature gates for CAT and PSK Reporter:"
echo "   - See PAYWALL_INTEGRATION.md for examples"
echo ""
echo "3. Test free version (no premium package):"
echo "   - Build in Xcode without ft_ham_premium package"
echo "   - Verify paywall appears for premium features"
echo ""
echo "4. Test premium version (with premium package):"
echo "   - Add ft_ham_premium local package in Xcode"
echo "   - Add -D PREMIUM_BUILD to Swift compiler flags"
echo "   - Test that real implementations work"
echo ""
echo "5. Configure App Store Connect:"
echo "   - Product ID: com.turrion.ft8ham.premium"
echo "   - Type: Non-Consumable"
echo ""
echo "6. Push to GitHub:"
echo "   git push origin $current_branch"
echo ""
echo "For detailed integration guide, see:"
echo "  📄 PAYWALL_INTEGRATION.md"
echo ""
