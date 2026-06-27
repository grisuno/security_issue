#!/bin/bash
# ============================================================================
# Script: github_full_export_and_push.sh
# Descripción: Exporta issues, Dependabot y CodeScan de TODOS los repositorios
#              de un usuario de GitHub, y sube el resultado a un repositorio.
# Uso: ./github_full_export_and_push.sh [usuario]
#      Si no se proporciona usuario, usa el autenticado.
# Requisitos: gh, jq, git
# ============================================================================

set -uo pipefail

# --- Configuración ---
USER="${1:-$(gh api user --jq '.login')}"
REPO_DESTINO="https://github.com/grisuno/security_issue.git"   # Cambia si quieres otro repo
DIR_LOCAL="$HOME/security_issue"   # Directorio donde clonaremos localmente
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
EXPORT_DIR="./github_export_$TIMESTAMP"
mkdir -p "$EXPORT_DIR"

# Archivos de salida
INDEX_FILE="$EXPORT_DIR/INDEX.md"
SUMMARY_FILE="$EXPORT_DIR/SUMMARY.md"

# Inicializar índice
echo "# Repository Statistics for $USER" > "$INDEX_FILE"
echo "" >> "$INDEX_FILE"
echo "| Repository | ⭐ Stars | 📥 Clones (14d) | 🟢 Open Issues | 📋 Total Issues | 🛡 Dependabot Open | 🔍 CodeScan Open |" >> "$INDEX_FILE"
echo "|------------|---------|----------------|----------------|----------------|---------------------|-------------------|" >> "$INDEX_FILE"

# --- Funciones auxiliares ---

get_clones() {
    local repo="$1"
    gh api "repos/$USER/$repo/traffic/clones" --jq '.count' 2>/dev/null || echo "0"
}

save_issue() {
    local repo="$1"
    local issue="$2"
    local repo_dir="$EXPORT_DIR/$repo"
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
    local alert_dir="$EXPORT_DIR/$repo/dependabot"
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
    echo "- [Dependabot #$number](./dependabot/alert_${number}.md) - $package ($severity) - $state" >> "$EXPORT_DIR/$repo/README.md"
}

save_codescan_alert() {
    local repo="$1"
    local alert="$2"
    local alert_dir="$EXPORT_DIR/$repo/codescan"
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
    echo "- [CodeScan #$number](./codescan/alert_${number}.md) - $rule_id ($severity) - $state" >> "$EXPORT_DIR/$repo/README.md"
}

# --- Obtener lista de repositorios ---
echo "[*] Fetching repositories for $USER..."
repos=$(gh repo list "$USER" --limit 1000 --json name -q '.[].name' 2>/dev/null)
if [ -z "$repos" ]; then
    echo "[-] No repositories found or insufficient permissions."
    exit 1
fi

total_repos=$(echo "$repos" | wc -w)
echo "[*] Total repositories: $total_repos"

# --- Variables globales para resumen ---
global_issues=0
global_dependabot=0
global_codescan=0
global_stars=0
global_clones=0
global_repos_processed=0

count=0
for repo in $repos; do
    ((count++))
    echo "[*] ($count/$total_repos) Processing: $repo"

    REPO_DIR="$EXPORT_DIR/$repo"
    mkdir -p "$REPO_DIR"

    # Información básica
    repo_info=$(gh api "repos/$USER/$repo" --jq '{stars: .stargazers_count, open_issues: .open_issues_count, description: .description}' 2>/dev/null || echo '{"stars":0,"open_issues":0,"description":""}')
    stars=$(echo "$repo_info" | jq -r '.stars // 0')
    open_issues=$(echo "$repo_info" | jq -r '.open_issues // 0')
    description=$(echo "$repo_info" | jq -r '.description // ""')
    clones=$(get_clones "$repo")

    # Total de issues (todas las estados) - solo para estadística
    total_issues=$(gh api --paginate "repos/$USER/$repo/issues?state=all" --jq '[.[] | select(.pull_request == null)] | length' 2>/dev/null || echo "0")

    # Alertas Dependabot (abiertas)
    dependabot_alerts=$(gh api --paginate "repos/$USER/$repo/dependabot/alerts?state=open" --jq '.[]' 2>/dev/null || echo "")
    count_dependabot=$(echo "$dependabot_alerts" | jq -s 'length' 2>/dev/null || echo "0")

    # Alertas CodeScan (abiertas)
    codescan_alerts=$(gh api --paginate "repos/$USER/$repo/code-scanning/alerts?state=open" --jq '.[]' 2>/dev/null || echo "")
    count_codescan=$(echo "$codescan_alerts" | jq -s 'length' 2>/dev/null || echo "0")

    # Crear README.md del repositorio
    cat > "$REPO_DIR/README.md" <<EOF
# Repository: $repo

**Description:** $description

| Metric | Value |
|--------|-------|
| ⭐ Stars | $stars |
| 📥 Clones (last 14 days) | $clones |
| 🟢 Open Issues | $open_issues |
| 📋 Total Issues | $total_issues |
| 🛡 Dependabot Open Alerts | $count_dependabot |
| 🔍 CodeScan Open Alerts | $count_codescan |

## Issues
EOF

    # --- Descargar issues (usando proceso de sustitución para evitar subshell) ---
    issue_count=0
    # Usamos un pipe directo con while read, pero en Bash podemos usar 'lastpipe' o redirección
    # Mejor: usar while read con un pipe, pero para que las variables se actualicen, usamos proceso de sustitución
    while IFS= read -r issue; do
        save_issue "$repo" "$issue"
        ((issue_count++))
    done < <(gh api --paginate "repos/$USER/$repo/issues?state=all" --jq '.[] | select(.pull_request == null)' 2>/dev/null)

    # --- Guardar alertas Dependabot ---
    if [ "$count_dependabot" -gt 0 ]; then
        echo "" >> "$REPO_DIR/README.md"
        echo "## Dependabot Alerts" >> "$REPO_DIR/README.md"
        while IFS= read -r alert; do
            save_dependabot_alert "$repo" "$alert"
        done < <(echo "$dependabot_alerts" | jq -c '.')
    fi

    # --- Guardar alertas CodeScan ---
    if [ "$count_codescan" -gt 0 ]; then
        echo "" >> "$REPO_DIR/README.md"
        echo "## Code Scanning Alerts" >> "$REPO_DIR/README.md"
        while IFS= read -r alert; do
            save_codescan_alert "$repo" "$alert"
        done < <(echo "$codescan_alerts" | jq -c '.')
    fi

    echo "" >> "$REPO_DIR/README.md"
    echo "Total issues downloaded: $issue_count" >> "$REPO_DIR/README.md"

    # Acumular globales
    global_issues=$((global_issues + issue_count))
    global_dependabot=$((global_dependabot + count_dependabot))
    global_codescan=$((global_codescan + count_codescan))
    global_stars=$((global_stars + stars))
    global_clones=$((global_clones + clones))
    ((global_repos_processed++))

    # Agregar al índice
    echo "| [$repo]($REPO_DIR/README.md) | $stars | $clones | $open_issues | $total_issues | $count_dependabot | $count_codescan |" >> "$INDEX_FILE"

    echo "[+] Completed $repo ($issue_count issues, $count_dependabot Dependabot, $count_codescan CodeScan)"
done

# --- Generar resumen global ---
cat > "$SUMMARY_FILE" <<EOF
# Global Summary for $USER

- **Total repositories processed:** $global_repos_processed
- **Total issues downloaded:** $global_issues
- **Total Dependabot alerts (open):** $global_dependabot
- **Total Code Scanning alerts (open):** $global_codescan
- **Total stars across all repos:** $global_stars
- **Total clones (last 14 days):** $global_clones

## Detailed per‑repository statistics

See [INDEX](./INDEX.md).

---

*Generated on $(date)*
EOF

echo ""
echo "[*] Export completed. Files in: $EXPORT_DIR"

# --- SUBIR A GITHUB ---
echo "[*] Preparing to push to $REPO_DESTINO"

# Si no existe el directorio local, clonamos
if [ ! -d "$DIR_LOCAL" ]; then
    echo "[*] Cloning repository..."
    git clone "$REPO_DESTINO" "$DIR_LOCAL"
    if [ $? -ne 0 ]; then
        echo "[-] Failed to clone. Exiting."
        exit 1
    fi
else
    echo "[*] Updating existing local repository..."
    cd "$DIR_LOCAL"
    git pull origin main || git pull origin master
    cd - > /dev/null
fi

# Limpiar el contenido previo (excepto .git)
cd "$DIR_LOCAL"
rm -rf ./* .[^.]*
cd - > /dev/null

# Copiar todos los archivos generados al directorio local
cp -r "$EXPORT_DIR"/* "$DIR_LOCAL"/

# Mover el ÍNDICE y el RESUMEN a la raíz para que sean visibles
cp "$INDEX_FILE" "$DIR_LOCAL/README.md"
cp "$SUMMARY_FILE" "$DIR_LOCAL/SUMMARY.md"

# Asegurarse de que el README.md principal contenga el índice
# Ya lo hemos copiado como README.md

# Commit y push
cd "$DIR_LOCAL"
git add -A
git commit -m "Security export update $(date +'%Y-%m-%d %H:%M')"
git push origin main || git push origin master
if [ $? -eq 0 ]; then
    echo "[*] Successfully pushed to $REPO_DESTINO"
else
    echo "[-] Push failed. Please check your credentials and network."
fi
cd - > /dev/null

echo "[*] All done. Visit https://github.com/grisuno/security_issue to see the updated data."