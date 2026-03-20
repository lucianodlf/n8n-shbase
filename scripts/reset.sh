#!/usr/bin/env bash
# reset.sh — Revierte el repositorio al estado de template limpio.
# Elimina toda configuración específica de la instancia actual:
#   - .env (claves reales, contraseñas, API keys)
#   - .mcp.json eliminado (generado por init.sh, contiene credenciales reales)
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
  echo "    - .mcp.json (eliminado — regenerar con 'make init')"
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
# 3. Eliminar .mcp.json generado (contiene credenciales reales)
# -----------------------------------------------------------------------------
MCP_FILE="$ROOT_DIR/.mcp.json"
if [ -f "$MCP_FILE" ]; then
  rm "$MCP_FILE"
  info ".mcp.json eliminado (regenerar con 'make init' cuando sea necesario)"
fi

# -----------------------------------------------------------------------------
# 4. Limpiar volúmenes de datos
# Los archivos son propiedad del usuario interno del container (uid 999),
# por lo que se usa un container efímero para eliminarlos sin requerir sudo.
# -----------------------------------------------------------------------------
for dir in volumes/n8n_data volumes/postgres_data; do
  TARGET="$ROOT_DIR/$dir"
  if [ -d "$TARGET" ]; then
    docker run --rm -v "$TARGET:/target" alpine sh -c "rm -rf /target/*" 2>/dev/null || {
      warn "$dir: no se pudo limpiar automáticamente. Ejecutá manualmente: sudo rm -rf $TARGET/*"
      continue
    }
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
