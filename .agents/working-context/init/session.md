# Análisis: n8n-docker-template (Session Init)

**Fecha:** 2026-03-13
**Contexto:** Análisis inicial para definir la implementación del template repository n8n-shbase.

---

## 1. Comprensión del Objetivo

El proyecto busca un **template repository** que permita instanciar entornos n8n aislados por proyecto, con:
- Persistencia independiente (DB + volúmenes propios por instancia)
- Configuración reproducible vía `.env`
- Integración con Claude Code mediante n8n-mcp (aprovisionamiento de workflows desde el IDE)
- Soporte para casos de uso heterogéneos: integración con apps web, bots de Telegram, ERPs, Google Sheets

### Casos de uso orientativos
| Proyecto | Integraciones clave |
|---|---|
| notesmd | Next.js + React, Telegram, RAG/IA, resumen de documentos |
| gastos-personal | Telegram/WhatsApp, Google Sheets, comprobantes de pago |
| ERP | Telegram, procesamiento de documentos, horarios de empleados |

---

## 2. Decisiones Arquitectónicas

### 2.1 Multi-instancia vs Mono-instancia

**Decisión: Multi-instancia aislada** (confirmada por el plan).

| Criterio | Multi-instancia | Mono-instancia |
|---|---|---|
| Aislamiento de datos | ✅ Total | ❌ Compartido |
| Backups independientes | ✅ Por proyecto | ❌ Complejo |
| Ciclo de vida independiente | ✅ | ❌ |
| Consumo de recursos | Mayor (1 DB por proyecto) | Menor |
| Portabilidad | ✅ Máxima | Moderada |

Para el caso de uso (instancias dev por proyecto, eventual producción), el modelo multi-instancia es el correcto. El overhead de recursos es manejable en desarrollo local.

### 2.2 Base de datos

**Decisión: PostgreSQL** (no SQLite).

- Recomendado por n8n para entornos que requieren estabilidad a largo plazo.
- SQLite es aceptable solo para testing rápido sin persistencia real.
- Permite escalar a producción sin migración de motor.

### 2.3 Self-hosted AI Starter Kit (n8n)

**Conclusión: NO es apropiado para este caso.**

El AI Starter Kit de n8n está orientado a montar una stack completa con Ollama, Qdrant y n8n en una sola instancia. Está pensado para demos o experimentación, no para el modelo multi-proyecto aislado que se propone aquí. Usar el template propio da mayor control y portabilidad.

---

## 3. Componentes del Template

### 3.1 Estructura de archivos propuesta

```
n8n-shbase/                    ← Template repository (este repo)
├── docker-compose.yml         ← Servicios: n8n + PostgreSQL
├── .env.example               ← Variables críticas documentadas
├── .env                       ← (gitignored) Variables reales
├── volumes/
│   ├── n8n_data/              ← Persistencia de /home/node/.n8n
│   └── postgres_data/         ← Persistencia de PostgreSQL
├── scripts/
│   ├── init.sh                ← Setup inicial (copiar .env, generar claves)
│   └── backup.sh              ← Backup de volúmenes y DB
├── .mcp.json                  ← Configuración n8n-mcp para Claude Code
└── .agents/
    └── working-context/
        └── init/
            └── session.md     ← Este documento
```

### 3.2 Variables de entorno críticas

Basado en n8n-docs (Self-Hosting):

```env
# Identidad del proyecto
PROJECT_NAME=mi-proyecto          # Prefijo para nombres de contenedores

# n8n
N8N_PORT=5678                     # Puerto único por instancia en el host
N8N_ENCRYPTION_KEY=               # OBLIGATORIO. Estático para no perder credenciales
WEBHOOK_URL=http://localhost:5678/ # URL pública/local para webhooks externos
N8N_HOST=localhost
N8N_PROTOCOL=http

# PostgreSQL
DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=postgres
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=n8n
DB_POSTGRESDB_USER=n8n
DB_POSTGRESDB_PASSWORD=           # Generar password seguro
DB_POSTGRESDB_SCHEMA=public

# Usuario admin inicial (opcional, si user management habilitado)
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=
```

**Punto crítico:** `N8N_ENCRYPTION_KEY` debe ser fijo y persistido. Si el contenedor se recrea sin esta clave, todas las credenciales almacenadas quedan ilegibles.

### 3.3 docker-compose.yml (estructura)

```yaml
services:
  postgres:
    image: postgres:16
    container_name: ${PROJECT_NAME}-postgres
    environment:
      POSTGRES_DB: ${DB_POSTGRESDB_DATABASE}
      POSTGRES_USER: ${DB_POSTGRESDB_USER}
      POSTGRES_PASSWORD: ${DB_POSTGRESDB_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_POSTGRESDB_USER}"]

  n8n:
    image: n8nio/n8n:latest
    container_name: ${PROJECT_NAME}-n8n
    ports:
      - "${N8N_PORT}:5678"
    environment:
      # Variables desde .env
    volumes:
      - n8n_data:/home/node/.n8n
      - ./local-files:/files        # Opcional: acceso a archivos locales
    depends_on:
      postgres:
        condition: service_healthy

volumes:
  n8n_data:
  postgres_data:
```

---

## 4. Integración n8n-mcp con Claude Code

### 4.1 ¿Qué es n8n-mcp?

Servidor MCP ([czlonkowski/n8n-mcp](https://github.com/czlonkowski/n8n-mcp)) que expone herramientas para que Claude Code pueda:

**Core tools (siempre disponibles, sin API key):**
- `search_nodes` — buscar nodos n8n por nombre/funcionalidad
- `get_node` — obtener info detallada de un nodo
- `validate_node` / `validate_workflow` — validar configuraciones
- `search_templates` / `get_template` — buscar y obtener templates de workflows

**n8n Management tools (requieren `N8N_API_URL` + `N8N_API_KEY`):**
- `n8n_create_workflow`, `n8n_update_partial_workflow`, `n8n_list_workflows`
- `n8n_deploy_template` — desplegar template directamente
- `n8n_test_workflow`, `n8n_executions` — testing y monitoreo
- `n8n_health_check`, `n8n_diagnostic`

### 4.2 Configuración .mcp.json para el template

El template incluirá un `.mcp.json` con ambas opciones documentadas. **Por defecto activa: npx** (requiere Node.js en el host, sin overhead de contenedor adicional).

```json
{
  "mcpServers": {
    // OPCIÓN ACTIVA: npx (recomendada si tenés Node.js instalado)
    // Ventajas: sin overhead de container, startup más rápido, sin pull de imagen
    "n8n-mcp": {
      "command": "npx",
      "args": ["n8n-mcp"],
      "env": {
        "MCP_MODE": "stdio",
        "LOG_LEVEL": "error",
        "DISABLE_CONSOLE_OUTPUT": "true",
        "N8N_API_URL": "http://localhost:${N8N_PORT}",
        "N8N_API_KEY": "${N8N_API_KEY}"
      }
    }

    // OPCIÓN ALTERNATIVA: Docker stdio
    // Usar si no tenés Node.js en el host o preferís aislamiento total.
    // IMPORTANTE: usa host.docker.internal para alcanzar n8n desde dentro del container.
    // Para activar: comentar el bloque npx de arriba y descomentar este.
    //
    // "n8n-mcp": {
    //   "command": "docker",
    //   "args": [
    //     "run", "-i", "--rm", "--init",
    //     "-e", "MCP_MODE=stdio",
    //     "-e", "LOG_LEVEL=error",
    //     "-e", "DISABLE_CONSOLE_OUTPUT=true",
    //     "-e", "N8N_API_URL=http://host.docker.internal:${N8N_PORT}",
    //     "-e", "N8N_API_KEY=${N8N_API_KEY}",
    //     "ghcr.io/czlonkowski/n8n-mcp:latest"
    //   ]
    // }
  }
}
```

**Nota:** El `.mcp.json` en el template usará placeholders; el `scripts/init.sh` los reemplazará con los valores del `.env`.

### 4.3 Flujo de aprovisionamiento

```
1. git clone n8n-shbase → nuevo-proyecto/
2. cp .env.example .env && editar .env
3. ./scripts/init.sh   ← genera N8N_ENCRYPTION_KEY, valida puertos, configura .mcp.json
4. docker compose up -d
5. Claude Code carga .mcp.json → n8n-mcp activo
6. Claude Code usa n8n_deploy_template / n8n_create_workflow para inyectar workflows iniciales
```

---

## 5. Consideraciones de Seguridad

- `N8N_ENCRYPTION_KEY`: generada una vez con `openssl rand -hex 32`, nunca regenerada.
- `.env` en `.gitignore` siempre.
- `N8N_API_KEY`: generada desde la UI de n8n post-deploy, almacenada en `.env`.
- Para producción: agregar reverse proxy (Nginx/Traefik) con HTTPS y cambiar `WEBHOOK_URL`.

---

## 6. Opciones de Implementación

### Opción A: Template minimalista (recomendada para comenzar)
- `docker-compose.yml` con n8n + PostgreSQL únicamente
- `.env.example` bien documentado
- `scripts/init.sh` básico
- `.mcp.json` con n8n-mcp en modo stdio/npx
- Sin reverse proxy (uso local/dev)

**Ventaja:** Simple, funciona de inmediato, sin dependencias adicionales.

### Opción B: Template con reverse proxy incluido
- Agrega Traefik o Nginx al compose
- Soporta HTTPS con Let's Encrypt
- WEBHOOK_URL apunta a dominio real

**Ventaja:** Listo para producción.
**Desventaja:** Mayor complejidad inicial, requiere dominio/IP pública.

### Opción C: Template con queue mode
- Agrega Redis + workers n8n separados
- Para workflows de alta concurrencia

**Desventaja:** Overhead significativo, innecesario para dev.

---

## 7. Recomendación de Implementación

**Implementar Opción A como base del template**, con documentación clara de cómo escalar a Opción B para producción.

### Próximos pasos concretos:
1. Crear `docker-compose.yml` con n8n + PostgreSQL y health checks
2. Crear `.env.example` con todas las variables documentadas
3. Crear `scripts/init.sh` (generar encryption key, copiar .env, validar puertos)
4. Crear `.mcp.json` con configuración n8n-mcp
5. Crear `.gitignore` (excluir `.env`, `volumes/`, datos sensibles)
6. Probar el flujo completo: `up` → acceso UI → obtener API key → activar n8n-mcp

---

## 8. Decisiones Confirmadas

1. **Puertos:** Rango base `5678–5699` reservado para instancias n8n locales. Documentar en README con tabla de asignación por proyecto (ej: 5678=notesmd, 5679=gastos-personal, 5680=erp). Cada instancia define su `N8N_PORT` en su propio `.env`.

2. **n8n-mcp mode:** npx por defecto (Node.js disponible en host). Docker stdio incluido como opción comentada en `.mcp.json`.

3. **N8N_API_KEY:** Manual — el usuario la genera desde la UI de n8n post-deploy y la agrega al `.env`. Documentar en README como "Feature futuro: automatización de API key via script" en sección de roadmap.

4. **Producción / Webhooks externos:** No aplica por ahora. Se resolverá en fase de pruebas de implementación por proyecto. Documentar en README como sección "Producción (reverse proxy + HTTPS)" con referencia a Opción B.

---

## 9. TODO: Plan de Primera Implementación

Pasos ordenados para construir el template funcional. Indica quién ejecuta cada paso.

### Fase 1 — Repositorio base
- [x] **[YO]** Crear repositorio en GitHub como Template Repository (`n8n-shbase`)
- [x] **[YO]** Clonar localmente y abrir en Claude Code
- [x] **[CLAUDE]** Crear `.gitignore` (`.env`, `volumes/`, `local-files/`, `*.log`)
- [x] **[CLAUDE]** Crear estructura de directorios base (`volumes/`, `scripts/`, `.agents/`)

### Fase 2 — Archivos de configuración
- [x] **[CLAUDE]** Crear `docker-compose.yml` (n8n + PostgreSQL con health check, variables desde `.env`)
- [x] **[CLAUDE]** Crear `.env.example` con todas las variables documentadas y comentadas
- [x] **[CLAUDE]** Crear `.mcp.json` con npx activo y Docker comentado (placeholders para `N8N_PORT` y `N8N_API_KEY`)
- [x] **[CLAUDE]** Crear `.mcp.docker.json.example` como referencia para modo Docker stdio

### Fase 3 — Scripts
- [x] **[CLAUDE]** Crear `scripts/init.sh`:
  - Verifica prereqs (Docker, docker compose)
  - Copia `.env.example` → `.env` si no existe
  - Genera `N8N_ENCRYPTION_KEY` con `openssl rand -hex 32` y la escribe en `.env`
  - Reemplaza placeholders en `.mcp.json` con valores del `.env`
  - Imprime instrucciones del siguiente paso

### Fase 4 — Primera prueba de la instancia
- [ ] **[YO]** Copiar `.env.example` a `.env`, asignar `PROJECT_NAME`, `N8N_PORT=5678`, contraseñas
- [ ] **[YO]** Ejecutar `./scripts/init.sh`
- [ ] **[YO]** Ejecutar `docker compose up -d` y verificar que los contenedores levanten
- [ ] **[YO]** Acceder a `http://localhost:5678`, completar setup inicial de n8n
- [ ] **[YO]** Generar API key desde UI de n8n → Settings > API > Create API Key
- [ ] **[YO]** Agregar `N8N_API_KEY` al `.env`

### Fase 5 — Integración n8n-mcp
- [ ] **[YO]** Reejecutar `./scripts/init.sh` (o actualizar `.mcp.json` manualmente con la API key)
- [ ] **[YO]** Reiniciar Claude Code para que cargue el `.mcp.json` actualizado
- [ ] **[YO+CLAUDE]** Verificar que n8n-mcp esté activo: pedir a Claude que ejecute `n8n_health_check`
- [ ] **[YO+CLAUDE]** Crear un workflow de prueba simple desde Claude Code usando `n8n_create_workflow`

### Fase 6 — README
- [ ] **[CLAUDE]** Crear `README.md` con:
  - Descripción del template
  - Tabla de puertos reservados (rango 5678–5699)
  - Instrucciones de uso (clone → init → up)
  - Sección "n8n-mcp con Claude Code" (npx y Docker stdio)
  - Sección "Producción" (Opción B — reverse proxy, futuro)
  - Sección "Roadmap / Features futuros" (automatización API key, etc.)

### Fase 7 — Validación final
- [ ] **[YO]** Probar el flujo completo desde cero en un directorio limpio (simular uso del template)
- [ ] **[YO+CLAUDE]** Ajustes y correcciones según lo encontrado en la prueba

---

*Fuentes consultadas: czlonkowski/n8n-mcp (DeepWiki), n8n-io/n8n-docs (DeepWiki), plan-base.md*
*Decisiones actualizadas: 2026-03-13*
