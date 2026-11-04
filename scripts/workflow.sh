#!/bin/bash
# Quick workflow helper script for ft_ham dual-repo development

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FT_HAM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FT_HAM_PREMIUM_DIR="$(cd "$FT_HAM_DIR/../ft_ham_premium" 2>/dev/null && pwd || echo "$FT_HAM_DIR/../ft_ham_premium")"

show_help() {
    cat << EOF
🛠️  FT Ham Dual-Repo Workflow Helper

Usage: ./scripts/workflow.sh <command>

Commands:
  status              Show git status of both repos
  check-clean         Verify no premium references in public repo
  sync-to-premium     Copy stub API signatures to premium (for reference)
  test-hook           Test if pre-push hook is working
  list-changes        Show uncommitted changes in both repos

Examples:
  ./scripts/workflow.sh status
  ./scripts/workflow.sh check-clean

EOF
}

cmd_status() {
    echo "📁 Public repo (ft_ham):"
    cd "$FT_HAM_DIR"
    git status -sb
    echo ""
    
    echo "📁 Premium repo (ft_ham_premium):"
    if [ -d "$FT_HAM_PREMIUM_DIR" ]; then
        cd "$FT_HAM_PREMIUM_DIR"
        git status -sb 2>/dev/null || echo "  Not a git repository"
    else
        echo "  Not found at: $FT_HAM_PREMIUM_DIR"
    fi
}

cmd_check_clean() {
    echo "🔍 Checking for premium references in public repo..."
    cd "$FT_HAM_DIR"
    
    # Search for potential premium imports or references
    found=0
    
    if grep -r "import FTHamPremium" ft8_ham/ 2>/dev/null | grep -v ".xcodeproj"; then
        echo "❌ Found 'import FTHamPremium' in public code"
        found=1
    fi
    
    if grep -r "ft_ham_premium" ft8_ham/ 2>/dev/null | grep -v ".xcodeproj"; then
        echo "❌ Found 'ft_ham_premium' references in public code"
        found=1
    fi
    
    if [ $found -eq 0 ]; then
        echo "✅ No premium references found in public repo"
    else
        echo ""
        echo "⚠️  Fix these references before pushing"
    fi
    
    return $found
}

cmd_test_hook() {
    echo "🧪 Testing pre-push hook..."
    cd "$FT_HAM_DIR"
    
    # Test the regex pattern
    test_paths=(
        "ft8_ham/Premium/Test.swift"
        "Documents/Github/ft_ham_premium/Test.swift"
        "some/path/FT_Ham_Premium/file.swift"
    )
    
    blocked_regex='^(ft8_ham/Premium/|ft8_ham/PremiumLocal/|premium-local/|LocalPackages/|.*FT_Ham_Premium/|.*ft_ham_premium/)'
    
    echo "Testing paths against hook regex:"
    for path in "${test_paths[@]}"; do
        if echo "$path" | grep -qE "$blocked_regex"; then
            echo "  ✅ Would block: $path"
        else
            echo "  ❌ Would allow: $path"
        fi
    done
    
    echo ""
    echo "Hook status:"
    if [ -f .githooks/pre-push ]; then
        echo "  ✅ pre-push hook exists"
    else
        echo "  ❌ pre-push hook missing - run: ./scripts/install-git-hooks.sh"
    fi
    
    if git config core.hooksPath | grep -q ".githooks"; then
        echo "  ✅ Git configured to use .githooks"
    else
        echo "  ❌ Git not configured - run: ./scripts/install-git-hooks.sh"
    fi
}

cmd_list_changes() {
    echo "📝 Uncommitted changes:"
    echo ""
    echo "Public repo (ft_ham):"
    cd "$FT_HAM_DIR"
    git status --short
    
    echo ""
    echo "Premium repo (ft_ham_premium):"
    if [ -d "$FT_HAM_PREMIUM_DIR" ]; then
        cd "$FT_HAM_PREMIUM_DIR"
        git status --short 2>/dev/null || echo "  Not a git repository"
    else
        echo "  Not found"
    fi
}

cmd_sync_to_premium() {
    echo "📋 Stub API signatures (for reference when implementing premium):"
    echo ""
    
    cd "$FT_HAM_DIR"
    
    # Extract function signatures from stubs
    echo "CATSupport APIs:"
    grep -h "func \|class \|struct \|enum " ft8_ham/PremiumStubs/CATSupport/*.swift 2>/dev/null | grep -v "^//" | head -20
    
    echo ""
    echo "PSKReporter APIs:"
    grep -h "func \|class \|struct \|enum " ft8_ham/PremiumStubs/PSKReporter/*.swift 2>/dev/null | grep -v "^//" | head -20
    
    echo ""
    echo "💡 Tip: Premium implementations must match these signatures exactly"
}

# Main
case "${1:-help}" in
    status)
        cmd_status
        ;;
    check-clean)
        cmd_check_clean
        ;;
    test-hook)
        cmd_test_hook
        ;;
    list-changes)
        cmd_list_changes
        ;;
    sync-to-premium)
        cmd_sync_to_premium
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "Unknown command: $1"
        echo ""
        show_help
        exit 1
        ;;
esac
