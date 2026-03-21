# CLAUDE.md — n8n-shbase

## Memoria del proyecto

Los aprendizajes técnicos, contexto y decisiones de este proyecto están en:
`~/.claude/projects/-home-rafiki-Projects-n8n-shbase/memory/`

Consultar `MEMORY.md` en ese directorio para el índice completo.

## n8n — Conocimiento operativo

Aprendizajes clave sobre workflows, MCP y operaciones frecuentes:
`n8n-knowledge.md` (raíz del submodule) — leer antes de trabajar con workflows o ante errores.

Resumen de reglas críticas:
- Webhook node: siempre incluir `webhookId` UUID explícito al crear vía MCP/API.
- Activar workflows explícitamente post-creación vía `POST /api/v1/workflows/:id/activate`.
- Ante webhook 404: verificar tabla `webhook_entity` en la DB antes de asumir problema de red.
- `make reset` antes de cualquier commit final para limpiar datos de instancia.

## Workflow de trabajo
Directorio: `.agents/working-context` (sobreescribible con `WORKFLOW_DIR` en `.env`)
Sesiones: `init` · `feat-[nombre]` · `feat-[nombre]-[issue]` · `fix-[nombre]` · `refactor-[nombre]`
Archivos por sesión: `prompt.md` · `research.md` · `plan.md` · `fase-N-plan.md` · `roadmap.md`
Nueva sesión: `/ns` — crea subdirectorio y `prompt.md`
Al retomar: leer `prompt.md` y `plan.md` de la sesión activa
TODOs: editar directamente el archivo de plan marcando `[x]`
No incluir credenciales ni datos sensibles en documentos de trabajo
Guía completa: `.agents/working-context/WORKFLOW.md` (leer solo si hay dudas sobre el proceso)
Al iniciar sesión nueva (sin contexto de trabajo activo): sugerir al usuario ejecutar `/ns` para crear la sesión.
