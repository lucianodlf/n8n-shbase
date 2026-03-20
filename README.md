# n8n-shbase

Template repository para desplegar instancias [n8n](https://n8n.io) aisladas por proyecto usando Docker + PostgreSQL. Cada instancia tiene su propio ciclo de vida, base de datos y configuración independiente.

## Características

- **Multi-instancia aislada** — una instancia n8n + PostgreSQL por proyecto
- **Configuración reproducible** — todo vía `.env`, sin estado hardcodeado
- **Integración con Claude Code** — n8n-mcp preconfigurado para crear y gestionar workflows desde el IDE
- **Ciclo de vida simple** — `make init && make up` para arrancar; `make reset` para limpiar

## Requisitos

- Docker y Docker Compose plugin
- `openssl` (para generar claves)
- Node.js (para n8n-mcp en modo npx) — o Docker como alternativa

## Inicio rápido

### Opción A: repo independiente por proyecto (recomendado para proyectos nuevos)

```bash
# 1. Clonar como base de tu proyecto
git clone https://github.com/tu-usuario/n8n-shbase mi-proyecto
cd mi-proyecto

# 2. Inicializar (crea .env, genera N8N_ENCRYPTION_KEY)
make init

# 3. Editar .env con tus valores
#    - PROJECT_NAME=mi-proyecto
#    - N8N_PORT=5678  (ver tabla de puertos abajo)
#    - DB_POSTGRESDB_PASSWORD=...
#    - N8N_BASIC_AUTH_PASSWORD=...

# 4. Levantar los servicios
make up

# 5. Abrir n8n en el navegador
open http://localhost:5678
```

### Opción B: como submodule dentro de un proyecto existente

Para integrar n8n-shbase en un proyecto que ya tiene su propio repositorio git:

```bash
# Dentro del proyecto existente (ej: notesmd/)
git submodule add https://github.com/tu-usuario/n8n-shbase services/n8n
git submodule update --init

# Inicializar la instancia
cd services/n8n
make init
# editar services/n8n/.env con los valores del proyecto
make up
```

#### `.mcp.json` en el proyecto padre

Al usar como submodule, lo habitual es trabajar con Claude Code desde la raíz del proyecto padre, no desde `services/n8n/`. En ese caso el `.mcp.json` del submodule no es leído por Claude Code.

`make init` resuelve esto automáticamente: en la segunda pasada (cuando `N8N_API_KEY` ya está configurada), escribe el `.mcp.json` de n8n-mcp directamente en el directorio raíz del proyecto padre.

El path destino se determina con la variable `PARENT_MCP_PATH` en el `.env` del submodule:

```env
# Default — estructura estándar (raiz/services/n8n/)
PARENT_MCP_PATH=../../.mcp.json

# Si el submodule está en otro nivel de anidamiento, ajustar:
# PARENT_MCP_PATH=../../../.mcp.json
```

Si la variable no está definida o está en blanco, se asume `../../.mcp.json` (estructura estándar `services/n8n`).

> **Nota:** el `.mcp.json` generado en el padre contiene la `N8N_API_KEY` en texto plano. Asegurarse de que el `.gitignore` del proyecto padre excluya `.mcp.json` o que el archivo no sea commiteado.

Al clonar el proyecto en otra máquina:

```bash
git clone --recurse-submodules https://github.com/tu-usuario/notesmd
# o si ya estaba clonado:
git submodule update --init --recursive
```

Para actualizar n8n-shbase a la última versión:

```bash
cd services/n8n && git pull origin main && cd ../..
git add services/n8n && git commit -m "chore: actualizar n8n-shbase"
```

> Ver [`docs/integracion-multi-repo.md`](docs/integracion-multi-repo.md) para la guía completa:
> coordinación de múltiples `docker-compose.yml`, redes Docker compartidas y
> centralización de configuración en `.env`.

## Comandos disponibles

| Comando | Descripción |
|---|---|
| `make init` | Setup inicial: crea `.env`, genera claves, configura `.mcp.json` |
| `make up` | Levanta n8n + PostgreSQL en background |
| `make down` | Detiene los servicios |
| `make restart` | Reinicia los servicios |
| `make logs` | Logs en tiempo real |
| `make status` | Estado de los contenedores |
| `make reset` | ⚠️ Revierte al estado template limpio (con confirmación) |
| `make reset-hard` | ⚠️ Revierte al estado template limpio (sin confirmación) |

## Tabla de puertos

Rango reservado `5678–5699` para instancias n8n locales. Asignar un puerto único por proyecto en el `.env`.

| Puerto | Proyecto |
|---|---|
| 5678 | notesmd |
| 5679 | gastos-personal |
| 5680 | erp-interno |
| 5681–5699 | disponibles |

## Flujo completo de configuración

```
make init              → crea .env vacío con la encryption key generada
  editar .env          → completar PROJECT_NAME, N8N_PORT, contraseñas
make up                → levanta n8n + postgres
  abrir UI             → http://localhost:{N8N_PORT}
  completar setup      → crear usuario admin en el wizard inicial
  generar API key      → Settings → API → Create API Key
  agregar al .env      → N8N_API_KEY=...
make init              → segunda pasada: configura .mcp.json con la API key
  reiniciar Claude Code → n8n-mcp queda activo
```

## Integración con Claude Code (n8n-mcp)

El template incluye `.mcp.json` preconfigurado con [n8n-mcp](https://github.com/czlonkowski/n8n-mcp), que permite a Claude Code interactuar directamente con n8n:

- Crear y modificar workflows
- Buscar nodos y templates
- Validar configuraciones
- Ejecutar tests

**Documentación de referencia:**
- [n8n-mcp en DeepWiki](https://deepwiki.com/czlonkowski/n8n-mcp) — arquitectura, herramientas disponibles e integración
- [n8n en DeepWiki](https://deepwiki.com/n8n-io/n8n) — internals de la plataforma
- [n8n-docs en DeepWiki](https://deepwiki.com/n8n-io/n8n-docs) — documentación oficial de self-hosting, variables de entorno, webhooks

### Modo npx (por defecto)

Requiere Node.js instalado en el host. Es el modo por defecto — sin overhead de container adicional.

```json
{
  "mcpServers": {
    "n8n-mcp": {
      "command": "npx",
      "args": ["n8n-mcp"],
      "env": {
        "MCP_MODE": "stdio",
        "N8N_API_URL": "http://localhost:{N8N_PORT}",
        "N8N_API_KEY": "{tu-api-key}"
      }
    }
  }
}
```

### Modo Docker stdio (alternativa)

Si no tenés Node.js en el host. El archivo `.mcp.docker.json.example` contiene la configuración lista para usar. Nota: usa `host.docker.internal` en lugar de `localhost` para alcanzar n8n desde dentro del container.

## Estado template vs instancia

El repo tiene dos estados diferenciados:

**Estado template** (lo que se commitea):
- `.env.example`, `.mcp.json` con placeholders, `docker-compose.yml`, `scripts/`
- Sin datos de instancia — listo para clonar y reutilizar

**Estado instancia** (ignorado por git):
- `.env` con claves reales, `volumes/` con datos de n8n y PostgreSQL
- Generado por `make init` + `make up`

Para volver al estado template antes de commitear:

```bash
make reset   # detiene containers, elimina .env, limpia volúmenes, restaura placeholders
git push     # repo queda limpio y reutilizable
```

## Variables de entorno

Ver `.env.example` para la lista completa con descripción de cada variable.

Variables críticas:

| Variable | Descripción |
|---|---|
| `PROJECT_NAME` | Prefijo para nombres de contenedores Docker |
| `N8N_PORT` | Puerto en el host (único por instancia, rango 5678–5699) |
| `N8N_ENCRYPTION_KEY` | Generada por `init.sh`. **No cambiar** una vez que la instancia tiene credenciales |
| `N8N_API_KEY` | Generada desde la UI de n8n post-deploy |
| `DB_POSTGRESDB_PASSWORD` | Contraseña de PostgreSQL |
| `PARENT_MCP_PATH` | Path relativo al `.mcp.json` del proyecto padre (uso como submodule). Default: `../../.mcp.json` |

> ⚠️ **`N8N_ENCRYPTION_KEY`**: generada una sola vez. Si se pierde o regenera con la instancia en uso, todas las credenciales almacenadas en n8n quedan ilegibles. Guardar copia segura fuera del repo.

## Estructura del repositorio

```
n8n-shbase/
├── docker-compose.yml          # Servicios: n8n + PostgreSQL
├── .env.example                # Variables con documentación
├── .mcp.json                   # Configuración n8n-mcp (npx, con placeholders)
├── .mcp.docker.json.example    # Configuración n8n-mcp alternativa (Docker stdio)
├── Makefile                    # Comandos de ciclo de vida
├── scripts/
│   ├── init.sh                 # Setup: genera claves, valida vars, configura mcp
│   └── reset.sh                # Revierte al estado template limpio
├── volumes/
│   ├── n8n_data/               # Persistencia de n8n (gitignored)
│   └── postgres_data/          # Persistencia de PostgreSQL (gitignored)
└── local-files/                # Archivos accesibles desde n8n (gitignored)
```

## Producción

> Esta sección describe una configuración futura — el template actual está orientado a entornos de desarrollo local.

Para exponer n8n en producción se requiere:

1. **Reverse proxy** (Nginx o Traefik) con terminación HTTPS
2. **Dominio propio** con certificado SSL (Let's Encrypt via Certbot o Traefik)
3. Actualizar `WEBHOOK_URL` en `.env` con la URL pública (`https://n8n.mi-dominio.com/`)
4. Configurar `N8N_PROTOCOL=https` y `N8N_HOST=n8n.mi-dominio.com`

Ver `docker-compose.yml` comentarios para una estructura base con Traefik (Opción B).

## Referencias

### n8n
- [Documentación oficial — Docker self-hosting](https://docs.n8n.io/hosting/installation/docker/)
- [Variables de entorno](https://docs.n8n.io/hosting/configuration/environment-variables/)
- [User management self-hosted](https://docs.n8n.io/hosting/configuration/user-management-self-hosted/)
- [n8n en DeepWiki](https://deepwiki.com/n8n-io/n8n)
- [n8n-docs en DeepWiki](https://deepwiki.com/n8n-io/n8n-docs)

### n8n-mcp
- [Repositorio czlonkowski/n8n-mcp](https://github.com/czlonkowski/n8n-mcp)
- [n8n-mcp en DeepWiki](https://deepwiki.com/czlonkowski/n8n-mcp)

### Integración multi-repo
- [`docs/integracion-multi-repo.md`](docs/integracion-multi-repo.md) — submodules, redes Docker compartidas, coordinación de stacks

## Roadmap

- [ ] **Automatización de API key** — script que genere la API key vía API de n8n post-deploy, sin necesidad de UI
- [ ] **CLI nativa** (`nsh`) — binario Go + Cobra que reemplace el Makefile con subcomandos (`nsh init`, `nsh up`, `nsh reset`) y eventual TUI con Bubble Tea para gestionar múltiples instancias
- [ ] **docker-compose con Traefik** — configuración lista para producción con HTTPS automático
- [ ] **scripts/backup.sh** — backup de volúmenes y dump de PostgreSQL
