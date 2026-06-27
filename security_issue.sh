#!/bin/bash
# =============================================================================
# Script: github_security_export.sh
# Description: Export all issues, Dependabot alerts, and Code Scanning alerts
#              from all repositories of a GitHub user into Markdown files.
# Usage: ./github_security_export.sh [username]
#        If no username is provided, uses the authenticated user.
# Dependencies: gh (GitHub CLI), jq
# =============================================================================

set -uo pipefail

# --- Configuration ---
USER="${1:-$(gh api user --jq '.login')}"
OUTPUT_DIR="./github_export_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTPUT_DIR"

INDEX_FILE="$OUTPUT_DIR/INDEX.md"
SUMMARY_FILE="$OUTPUT_DIR/SUMMARY.md"
echo "# Repository Statistics for $USER" > "$INDEX_FILE"
echo "" >> "$INDEX_FILE"
echo "| Repository | ⭐ Stars | 📥 Clones (14d) | 🟢 Open Issues | 📋 Total Issues | 🛡️ Dependabot Open | 🔍 CodeScan Open |" >> "$INDEX_FILE"
echo "|------------|---------|----------------|----------------|----------------|---------------------|-------------------|" >> "$INDEX_FILE"

# --- Helper functions ---

get_clones() {
    local repo="$1"
    gh api "repos/$USER/$repo/traffic/clones" --jq '.count' 2>/dev/null || echo "0"
}

save_issue() {
    local repo="$1"
    local issue="$2"
    local repo_dir="$OUTPUT_DIR/$repo"
    mkdir -p "$repo_dir"

    number=$(echo "$issue" | jq -r '.number')
    title=$(echo "$issue" | jq -r '.title')
    state=$(echo "$issue" | jq -r '.state')
    body=$(echo "$issue" | jq -r '.body // ""' | sed 's/\r//g')
    labels=$(echo "$issue" | jq -r '.labels[].name' | paste -sd ', ')
    created_at=$(echo "$issue" | jq -r '.created_at')
    updated_at=$(echo "$issue" | jq -r '.updated_at')

    cat > "$repo_dir/issue_${number}.md" <<EOF
# Issue #$number: $title

- **State:** $state
- **Created:** $created_at
- **Updated:** $updated_at
- **Labels:** ${labels:-None}

---

$body
EOF
    echo "- [#$number](./issue_${number}.md) - $title ($state)" >> "$repo_dir/README.md"
}

save_dependabot_alert() {
    local repo="$1"
    local alert="$2"
    local alert_dir="$OUTPUT_DIR/$repo/dependabot"
    mkdir -p "$alert_dir"

    number=$(echo "$alert" | jq -r '.number // 0')
    package=$(echo "$alert" | jq -r '.dependency.package.name // "unknown"')
    severity=$(echo "$alert" | jq -r '.security_advisory.severity // "N/A"')
    cve=$(echo "$alert" | jq -r '.security_advisory.cve_id // "N/A"')
    summary=$(echo "$alert" | jq -r '.security_advisory.summary // ""')
    description=$(echo "$alert" | jq -r '.security_advisory.description // ""')
    state=$(echo "$alert" | jq -r '.state // "unknown"')
    created_at=$(echo "$alert" | jq -r '.created_at // ""')
    html_url=$(echo "$alert" | jq -r '.html_url // ""')

    cat > "$alert_dir/alert_${number}.md" <<EOF
# Dependabot Alert #$number: $package

- **State:** $state
- **Severity:** $severity
- **CVE:** $cve
- **Created:** $created_at
- **URL:** $html_url

## Summary
$summary

## Description
$description
EOF
    echo "- [Dependabot #$number](./dependabot/alert_${number}.md) - $package ($severity) - $state" >> "$OUTPUT_DIR/$repo/README.md"
}

save_codescan_alert() {
    local repo="$1"
    local alert="$2"
    local alert_dir="$OUTPUT_DIR/$repo/codescan"
    mkdir -p "$alert_dir"

    number=$(echo "$alert" | jq -r '.number // 0')
    tool=$(echo "$alert" | jq -r '.tool.name // "unknown"')
    severity=$(echo "$alert" | jq -r '.rule.severity // "N/A"')
    rule_id=$(echo "$alert" | jq -r '.rule.id // "N/A"')
    rule_desc=$(echo "$alert" | jq -r '.rule.description // ""')
    state=$(echo "$alert" | jq -r '.state // "unknown"')
    created_at=$(echo "$alert" | jq -r '.created_at // ""')
    html_url=$(echo "$alert" | jq -r '.html_url // ""')

    cat > "$alert_dir/alert_${number}.md" <<EOF
# Code Scanning Alert #$number: $rule_id

- **State:** $state
- **Severity:** $severity
- **Tool:** $tool
- **Created:** $created_at
- **URL:** $html_url

## Description
$rule_desc
EOF
    echo "- [CodeScan #$number](./codescan/alert_${number}.md) - $rule_id ($severity) - $state" >> "$OUTPUT_DIR/$repo/README.md"
}

# --- Main loop ---

echo "[*] Fetching repository list for $USER..."
repos=$(gh repo list "$USER" --limit 1000 --json name -q '.[].name' 2>/dev/null)
if [ -z "$repos" ]; then
    echo "[-] No repositories found or insufficient permissions."
    exit 1
fi

total_repos=$(echo "$repos" | wc -w)
echo "[*] Total repositories found: $total_repos"

# Global counters for SUMMARY
global_issues=0
global_dependabot=0
global_codescan=0
global_stars=0
global_clones=0
global_repos_processed=0

count=0
for repo in $repos; do
    ((count++))
    echo "[*] ($count/$total_repos) Processing repository: $repo"

    REPO_DIR="$OUTPUT_DIR/$repo"
    mkdir -p "$REPO_DIR"

    # Basic repo info
    repo_info=$(gh api "repos/$USER/$repo" --jq '{stars: .stargazers_count, open_issues: .open_issues_count, description: .description}' 2>/dev/null || echo '{"stars":0,"open_issues":0,"description":""}')
    stars=$(echo "$repo_info" | jq -r '.stars // 0')
    open_issues=$(echo "$repo_info" | jq -r '.open_issues // 0')
    description=$(echo "$repo_info" | jq -r '.description // ""')
    clones=$(get_clones "$repo")

    # Count total issues (all states, excluding PRs)
    total_issues=$(gh api --paginate "repos/$USER/$repo/issues?state=all" --jq '[.[] | select(.pull_request == null)] | length' 2>/dev/null || echo "0")

    # Fetch Dependabot alerts (open)
    dependabot_alerts=$(gh api --paginate "repos/$USER/$repo/dependabot/alerts?state=open" --jq '.[]' 2>/dev/null || echo "")
    count_dependabot=$(echo "$dependabot_alerts" | jq -s 'length' 2>/dev/null || echo "0")

    # Fetch Code Scanning alerts (open)
    codescan_alerts=$(gh api --paginate "repos/$USER/$repo/code-scanning/alerts?state=open" --jq '.[]' 2>/dev/null || echo "")
    count_codescan=$(echo "$codescan_alerts" | jq -s 'length' 2>/dev/null || echo "0")

    # Create README.md for this repo
    cat > "$REPO_DIR/README.md" <<EOF
# Repository: $repo

**Description:** $description

| Metric | Value |
|--------|-------|
| ⭐ Stars | $stars |
| 📥 Clones (last 14 days) | $clones |
| 🟢 Open Issues | $open_issues |
| 📋 Total Issues | $total_issues |
| 🛡️ Dependabot Open Alerts | $count_dependabot |
| 🔍 CodeScan Open Alerts | $count_codescan |

## Issues
EOF

    # Download issues (paginated)
    page=1
    issue_count=0
    while true; do
        issues_page=$(gh api "repos/$USER/$repo/issues?state=all&per_page=100&page=$page" --jq '.[] | select(.pull_request == null)' 2>/dev/null) || break
        if [ -z "$issues_page" ] || [ "$(echo "$issues_page" | jq -s 'length')" -eq 0 ]; then
            break
        fi

        echo "$issues_page" | jq -c '.' | while read -r issue; do
            save_issue "$repo" "$issue"
            ((issue_count++))
        done

        if [ "$(echo "$issues_page" | jq -s 'length')" -lt 100 ]; then
            break
        fi
        ((page++))
    done

    # Save Dependabot alerts
    if [ "$count_dependabot" -gt 0 ]; then
        echo "" >> "$REPO_DIR/README.md"
        echo "## Dependabot Alerts" >> "$REPO_DIR/README.md"
        echo "$dependabot_alerts" | jq -c '.' 2>/dev/null | while read -r alert; do
            save_dependabot_alert "$repo" "$alert"
        done
    fi

    # Save CodeScan alerts
    if [ "$count_codescan" -gt 0 ]; then
        echo "" >> "$REPO_DIR/README.md"
        echo "## Code Scanning Alerts" >> "$REPO_DIR/README.md"
        echo "$codescan_alerts" | jq -c '.' 2>/dev/null | while read -r alert; do
            save_codescan_alert "$repo" "$alert"
        done
    fi

    # Append total issues to README
    echo "" >> "$REPO_DIR/README.md"
    echo "Total issues downloaded: $issue_count" >> "$REPO_DIR/README.md"

    # Update global counters
    global_issues=$((global_issues + issue_count))
    global_dependabot=$((global_dependabot + count_dependabot))
    global_codescan=$((global_codescan + count_codescan))
    global_stars=$((global_stars + stars))
    global_clones=$((global_clones + clones))
    ((global_repos_processed++))

    # Add entry to global INDEX
    echo "| [$repo]($REPO_DIR/README.md) | $stars | $clones | $open_issues | $total_issues | $count_dependabot | $count_codescan |" >> "$INDEX_FILE"

    echo "[+] Completed $repo ($issue_count issues, $count_dependabot Dependabot, $count_codescan CodeScan)"
done

# --- Generate SUMMARY file ---
cat > "$SUMMARY_FILE" <<EOF
# Global Summary for $USER

- **Total repositories processed:** $global_repos_processed
- **Total issues downloaded:** $global_issues
- **Total Dependabot alerts (open):** $global_dependabot
- **Total Code Scanning alerts (open):** $global_codescan
- **Total stars across all repos:** $global_stars
- **Total clones (last 14 days):** $global_clones

## Breakdown by Repository

See the [INDEX](./INDEX.md) for detailed per-repo statistics.

---

*Generated on $(date)*
EOF

echo ""
echo "[*] All done! Processed $global_repos_processed repositories."
echo "[*] Output directory: $OUTPUT_DIR"
echo "[*] Global index: $INDEX_FILE"
echo "[*] Summary: $SUMMARY_FILE"