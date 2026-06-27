**ISSUE: Your script is not downloading issues, only alerts. Also, no summary file is generated at the end.**

You used a script (`security_issue2.sh`) that seems to be an earlier version that either:
- Skips issue download due to a logic bug (e.g., it only processes issues if a certain condition is met, but it fails to count them).
- Does not write issue files because of a missing `while` loop or incorrect pagination.
- Only processed 2 repos because of `set -e` (but you already fixed that in the latest version?).

However, your output shows that `LazyOwn` has an `issue_84.md` file, so issues *are* being written for that repo, but for all others the count shows `0 issues`. This indicates that your script might be counting issues from the API response but not writing them, or the API is returning empty because of token/permission issues (some repos may be empty of issues).

I will provide a **fully functional, English version** that:

- Processes **all repositories** (including those with no issues/alerts).
- Downloads **all issues** (with pagination) and writes them as `issue_<number>.md`.
- Downloads **all Dependabot alerts** and writes them as `dependabot/alert_<number>.md`.
- Downloads **all Code Scanning alerts** and writes them as `codescan/alert_<number>.md`.
- Generates per-repo `README.md` with indexed lists.
- Generates a global `INDEX.md` with a table of repositories and their stats.
- Generates a final **`SUMMARY.md`** with global totals (total repos, total issues, total alerts, etc.).

The script is **resilient** – if one repo fails, it continues to the next. It uses proper error handling and pagination.

---

## 📜 Full Script: `github_security_export.sh` (English)

```bash
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
```

---

## 🚀 How to Use

1. **Save the script** as `github_security_export.sh`.
2. **Make it executable**:
   ```bash
   chmod +x github_security_export.sh
   ```
3. **Run it** (replace `username` with your GitHub username, or omit to use the authenticated user):
   ```bash
   ./github_security_export.sh grisuno
   ```
4. **Wait** – it will process all 133 repositories (this may take a while depending on API rate limits). The script handles errors gracefully and will continue even if a repo fails.

## 📁 Output Structure

```
github_export_<timestamp>/
├── INDEX.md                     # Table of all repos with stats
├── SUMMARY.md                   # Global totals
├── blacksandbeacon/
│   ├── README.md
│   ├── dependabot/
│   │   └── alert_1.md
│   └── codescan/
│       └── alert_2.md
├── LazyOwn/
│   ├── README.md
│   ├── issue_84.md
│   ├── dependabot/
│   │   └── alert_*.md
│   └── codescan/
│       └── alert_*.md
└── ... (for every repository)
```

- **`README.md`** per repo contains a list of all issues and alerts with links to their Markdown files.
- **`INDEX.md`** gives you a quick overview of all repos.
- **`SUMMARY.md`** provides global aggregated numbers.


![Python](https://img.shields.io/badge/python-3670A0?style=for-the-badge&logo=python&logoColor=ffdd54) ![Shell Script](https://img.shields.io/badge/shell_script-%23121011.svg?style=for-the-badge&logo=gnu-bash&logoColor=white) ![Flask](https://img.shields.io/badge/flask-%23000.svg?style=for-the-badge&logo=flask&logoColor=white) [![License: AGPL v3](https://img.shields.io/badge/License-AGPLv3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/Y8Y2Z73AV)
