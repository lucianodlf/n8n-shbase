# n8n Knowledge Base

Aprendizajes acumulados trabajando con n8n-shbase en diferentes proyectos.
Para actualizar: editar este archivo desde cualquier proyecto y hacer push a n8n-shbase.

---

## MCP / Claude Code

### `n8n_create_workflow` no activa el workflow
El workflow creado queda `active: false` por diseño. Activar explícitamente después de crear:
```bash
curl -X POST "http://localhost:{N8N_PORT}/api/v1/workflows/{id}/activate" \
  -H "X-N8N-API-KEY: {N8N_API_KEY}"
```
O verificar con `n8n_get_workflow mode=minimal` que `active: true` antes de probar triggers.

### n8n-mcp no expone endpoint de activación
El MCP cubre CRUD de workflows pero la activación requiere llamada directa a la REST API de n8n (`/api/v1/workflows/:id/activate`).

### `n8n_health_check` reporta versión del paquete MCP, no de la instancia
Para obtener la versión real de n8n:
```bash
docker exec {PROJECT_NAME}-n8n n8n --version
```

---

## Nodos

### Webhook node requiere `webhookId` explícito
Al crear un workflow con nodo Webhook vía MCP o la API REST, siempre incluir un `webhookId` UUID:
```json
{
  "id": "uuid-del-nodo",
  "name": "Webhook",
  "type": "n8n-nodes-base.webhook",
  "typeVersion": 2,
  "webhookId": "uuid-distinto-al-id",
  "parameters": { "path": "mi-path" }
}
```
Sin `webhookId`, el path queda como `{workflowId}/webhook/{path}` en vez de `{path}` limpio.
Generar UUID con: `python3 -c "import uuid; print(uuid.uuid4())"`

---

## Nodos — Telegram Polling (getUpdates)

### `$getWorkflowStaticData` no persiste el offset de forma confiable
En la versión 2.40.1 self-hosted con Schedule Trigger, `$getWorkflowStaticData('global')` no persiste correctamente entre ejecuciones — el valor siempre arranca en `undefined` (offset 0), lo que hace que `getUpdates` devuelva toda la cola de mensajes en cada ciclo.

**Solución verificada:** usar **Data Tables** (`n8n-nodes-base.dataTable`) para persistir el `last_update_id`.
1. Crear la tabla manualmente en la UI de n8n (Settings → Data tables) con columna `last_update_id` (número).
2. Al inicio del workflow: nodo dataTable con `operation: "get"` para leer el offset.
3. Al final (ambas ramas, con y sin mensajes): nodo dataTable con `operation: "update"`, filtro `{keyName: "id", condition: "eq", keyValue: "1"}`, columna `last_update_id` mapeada desde `nuevo_offset`.

Parámetros correctos del nodo dataTable:
- `resource: "row"` (requerido)
- `dataTableId: {mode: "id", value: "<tableId>"}` (resourceLocator)
- `columns: {mappingMode: "defineBelow", value: {last_update_id: "={{ $json.nuevo_offset }}"}}` (para update)
- `filters: {conditions: [{keyName: "id", condition: "eq", keyValue: "1"}]}` (fixedCollection)

---

## Errores conocidos

### Webhook 404 "not registered" aunque el workflow esté activo
Verificar directamente la tabla `webhook_entity` antes de asumir problemas de red:
```bash
docker exec {PROJECT_NAME}-postgres psql -U n8n -d n8n \
  -c 'SELECT "webhookPath", method, "webhookId", "workflowId" FROM webhook_entity;'
```
Si la tabla está vacía o no tiene el path esperado, el problema es de registro interno, no de red.

### Error de autenticación PostgreSQL al levantar la instancia
Causas frecuentes:
1. **Contraseña con caracteres especiales (`$`)** — escapar con `$$` en el `.env`:
   ```env
   DB_POSTGRESDB_PASSWORD=$$mi$password$$
   ```
2. **Volumen de postgres con datos de instancia anterior** — el directorio `volumes/postgres_data/pgdata` tiene datos inicializados con otra contraseña. Limpiar con:
   ```bash
   make reset && make init && make up
   ```
   > `make reset` usa un container Alpine efímero para eliminar los archivos (propiedad del uid 999 del container de postgres, inaccesibles sin sudo desde el host).

### Puerto ya en uso al ejecutar `make up`
Otra instancia n8n está corriendo con el mismo `N8N_PORT`. Verificar:
```bash
docker ps | grep n8n
```
Cambiar `N8N_PORT` en `.env` y reejecutar `make init && make up`.

---

## Operaciones

### `make reset` no limpia `volumes/postgres_data/pgdata` sin Docker
Los archivos del volumen pertenecen al uid 999 (usuario interno del container postgres). No son accesibles con `rm` desde el host sin `sudo`. El `reset.sh` usa `docker run alpine` para limpiarlos — no intentar hacerlo manualmente con `sudo rm` salvo como último recurso.

### Dos proyectos con el mismo `PROJECT_NAME` en el mismo host
Generan conflictos de nombres de contenedores y volúmenes Docker. Asignar un `PROJECT_NAME` único por instancia en cada `.env`.
