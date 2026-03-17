#!/usr/bin/env bash
# reset.sh — Revierte el repositorio al estado de template limpio.
# Elimina toda configuración específica de la instancia actual:
#   - .env (claves reales, contraseñas, API keys)
#   - .mcp.json restaurado a placeholders
#   - Volúmenes de datos (postgres_data, n8n_data)
#   - Archivos locales montados en el container
#
# USO: ./scripts/reset.sh [--hard]
#   Sin flags : pide confirmación interactiva
#   --hard    : omite confirmaciones (útil en scripts CI/CD)
#
# ⚠️  DESTRUCTIVO: los datos de la instancia se perderán.
#     Hacer backup antes si es necesario (ver scripts/backup.sh cuando exista).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

warn()  { echo -e "${YELLOW}[reset]${NC} $1"; }
info()  { echo -e "${GREEN}[reset]${NC} $1"; }
error() { echo -e "${RED}[error]${NC} $1"; exit 1; }

HARD=false
[[ "${1:-}" == "--hard" ]] && HARD=true

# -----------------------------------------------------------------------------
# Confirmación
# -----------------------------------------------------------------------------
if [ "$HARD" = false ]; then
  echo ""
  echo -e "${RED}⚠️  ATENCIÓN: este script eliminará toda la configuración de la instancia actual.${NC}"
  echo ""
  echo "  Se eliminarán / restaurarán:"
  echo "    - .env"
  echo "    - .mcp.json (placeholders restaurados)"
  echo "    - volumes/n8n_data/"
  echo "    - volumes/postgres_data/"
  echo "    - local-files/"
  echo ""
  read -rp "  ¿Continuar? (escribí 'reset' para confirmar): " CONFIRM
  [[ "$CONFIRM" == "reset" ]] || { warn "Cancelado."; exit 0; }
fi

# -----------------------------------------------------------------------------
# 1. Bajar contenedores si están corriendo
# -----------------------------------------------------------------------------
if [ -f "$ROOT_DIR/docker-compose.yml" ]; then
  if docker compose -f "$ROOT_DIR/docker-compose.yml" ps --quiet 2>/dev/null | grep -q .; then
    warn "Bajando contenedores Docker..."
    docker compose -f "$ROOT_DIR/docker-compose.yml" down -v 2>/dev/null || true
  fi
fi

# -----------------------------------------------------------------------------
# 2. Eliminar .env
# -----------------------------------------------------------------------------
if [ -f "$ROOT_DIR/.env" ]; then
  rm "$ROOT_DIR/.env"
  info ".env eliminado"
fi

# -----------------------------------------------------------------------------
# 3. Restaurar .mcp.json a placeholders
# -----------------------------------------------------------------------------
MCP_FILE="$ROOT_DIR/.mcp.json"
if [ -f "$MCP_FILE" ]; then
  # Extraer el puerto actual para mostrarlo en el log (informativo)
  CURRENT_PORT=$(grep -oP '"N8N_API_URL":\s*"http://localhost:\K[0-9]+' "$MCP_FILE" 2>/dev/null || echo "?")

  cat > "$MCP_FILE" <<'MCPEOF'
{
  "mcpServers": {
    "n8n-mcp": {
      "command": "npx",
      "args": ["n8n-mcp"],
      "env": {
        "MCP_MODE": "stdio",
        "LOG_LEVEL": "error",
        "DISABLE_CONSOLE_OUTPUT": "true",
        "N8N_API_URL": "http://localhost:N8N_PORT_PLACEHOLDER",
        "N8N_API_KEY": "N8N_API_KEY_PLACEHOLDER"
      }
    }
  }
}
MCPEOF
  info ".mcp.json restaurado a placeholders (tenía puerto: $CURRENT_PORT)"
fi

# -----------------------------------------------------------------------------
# 4. Limpiar volúmenes de datos
# -----------------------------------------------------------------------------
for dir in volumes/n8n_data volumes/postgres_data; do
  TARGET="$ROOT_DIR/$dir"
  if [ -d "$TARGET" ]; then
    find "$TARGET" -mindepth 1 ! -name '.gitkeep' -delete 2>/dev/null || true
    info "$dir limpiado"
  fi
done

# -----------------------------------------------------------------------------
# 5. Limpiar local-files
# -----------------------------------------------------------------------------
LOCAL_FILES="$ROOT_DIR/local-files"
if [ -d "$LOCAL_FILES" ]; then
  find "$LOCAL_FILES" -mindepth 1 ! -name '.gitkeep' -delete 2>/dev/null || true
  info "local-files limpiado"
fi

# -----------------------------------------------------------------------------
# 6. Resultado
# -----------------------------------------------------------------------------
echo ""
info "=== Reset completo ==="
echo ""
echo "  El repositorio volvió al estado de template limpio."
echo "  Para iniciar una nueva instancia: ./scripts/init.sh"
echo ""
