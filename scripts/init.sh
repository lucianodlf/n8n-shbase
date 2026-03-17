#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[init]${NC} $1"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $1"; }
error() { echo -e "${RED}[error]${NC} $1"; exit 1; }

# -----------------------------------------------------------------------------
# 1. Verificar prereqs
# -----------------------------------------------------------------------------
info "Verificando dependencias..."

command -v docker &>/dev/null       || error "Docker no está instalado."
docker compose version &>/dev/null  || error "docker compose (plugin) no está disponible."
command -v openssl &>/dev/null      || error "openssl no está instalado."

info "Docker: $(docker --version)"
info "Compose: $(docker compose version --short)"

# -----------------------------------------------------------------------------
# 2. Crear .env si no existe
# -----------------------------------------------------------------------------
ENV_FILE="$ROOT_DIR/.env"
ENV_EXAMPLE="$ROOT_DIR/.env.example"

if [ ! -f "$ENV_FILE" ]; then
  cp "$ENV_EXAMPLE" "$ENV_FILE"
  info ".env creado desde .env.example"
  warn "Completá los valores requeridos en .env antes de continuar (PROJECT_NAME, contraseñas, etc.)"
  warn "Luego reejecutá: ./scripts/init.sh"
  exit 0
else
  info ".env ya existe, continuando..."
fi

# -----------------------------------------------------------------------------
# 3. Generar N8N_ENCRYPTION_KEY si está vacía
# -----------------------------------------------------------------------------
CURRENT_KEY=$(grep -E '^N8N_ENCRYPTION_KEY=' "$ENV_FILE" | cut -d'=' -f2 | tr -d '[:space:]')

if [ -z "$CURRENT_KEY" ]; then
  NEW_KEY=$(openssl rand -hex 32)
  # Reemplazar la línea en .env
  sed -i "s|^N8N_ENCRYPTION_KEY=.*|N8N_ENCRYPTION_KEY=${NEW_KEY}|" "$ENV_FILE"
  info "N8N_ENCRYPTION_KEY generada y guardada en .env"
  warn "⚠️  Guardá una copia segura de esta clave. Si se pierde, las credenciales de n8n quedan ilegibles."
else
  info "N8N_ENCRYPTION_KEY ya existe, sin cambios."
fi

# -----------------------------------------------------------------------------
# 4. Validar variables obligatorias no vacías
# -----------------------------------------------------------------------------
MISSING=()
for VAR in PROJECT_NAME DB_POSTGRESDB_PASSWORD N8N_BASIC_AUTH_PASSWORD; do
  VAL=$(grep -E "^${VAR}=" "$ENV_FILE" | cut -d'=' -f2 | tr -d '[:space:]')
  [ -z "$VAL" ] && MISSING+=("$VAR")
done

if [ ${#MISSING[@]} -gt 0 ]; then
  error "Las siguientes variables están vacías en .env: ${MISSING[*]}
       Completálas y reejecutá: ./scripts/init.sh"
fi

# -----------------------------------------------------------------------------
# 5. Leer valores del .env para reemplazar placeholders en .mcp.json
# -----------------------------------------------------------------------------
source <(grep -E '^(N8N_PORT|N8N_API_KEY)=' "$ENV_FILE" | sed 's/[[:space:]]//g')

N8N_PORT="${N8N_PORT:-5678}"
N8N_API_KEY="${N8N_API_KEY:-}"

MCP_FILE="$ROOT_DIR/.mcp.json"

if [ -f "$MCP_FILE" ]; then
  sed -i "s|N8N_PORT_PLACEHOLDER|${N8N_PORT}|g" "$MCP_FILE"

  if [ -n "$N8N_API_KEY" ]; then
    sed -i "s|N8N_API_KEY_PLACEHOLDER|${N8N_API_KEY}|g" "$MCP_FILE"
    info ".mcp.json actualizado con N8N_PORT=${N8N_PORT} y N8N_API_KEY configurada."
  else
    warn ".mcp.json actualizado con N8N_PORT=${N8N_PORT}, pero N8N_API_KEY está vacía."
    warn "Generá la API key desde la UI de n8n (Settings → API → Create API Key),"
    warn "agrégala a .env como N8N_API_KEY=... y reejecutá este script."
  fi
else
  warn ".mcp.json no encontrado, omitiendo configuración de n8n-mcp."
fi

# -----------------------------------------------------------------------------
# 6. Crear directorios de volúmenes si no existen
# -----------------------------------------------------------------------------
mkdir -p "$ROOT_DIR/volumes/n8n_data" "$ROOT_DIR/volumes/postgres_data" "$ROOT_DIR/local-files"

# -----------------------------------------------------------------------------
# 7. Instrucciones finales
# -----------------------------------------------------------------------------
echo ""
info "=== Setup completo ==="
echo ""
echo "  Próximos pasos:"
echo ""
echo "  1. Revisá .env y completá los valores faltantes (contraseñas, PROJECT_NAME, etc.)"
echo "  2. Levantá los servicios:"
echo "       docker compose up -d"
echo "  3. Accedé a n8n en: http://localhost:${N8N_PORT}"
echo "  4. Completá el setup inicial de n8n en la UI"
echo "  5. Generá la API key: Settings → API → Create API Key"
echo "  6. Agregá N8N_API_KEY en .env y reejecutá: ./scripts/init.sh"
echo "  7. Reiniciá Claude Code para activar n8n-mcp"
echo ""
