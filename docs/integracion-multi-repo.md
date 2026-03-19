# Integración de n8n-shbase en otro proyecto

Guía de referencia para integrar n8n-shbase como parte de un proyecto existente
que ya tiene git y Docker propios (ej: notesmd con Supabase + Qdrant).

---

## 1. Estrategia de repos: Git Submodules

**Git submodule** permite incluir un repo dentro de otro manteniendo historiales
independientes — cada repo se versiona, actualiza y gestiona por separado.

```bash
# Dentro del proyecto destino (ej: notesmd/)
git submodule add https://github.com/tu-usuario/n8n-shbase services/n8n
git submodule update --init
```

Al clonar el proyecto destino en una máquina nueva:
```bash
git clone --recurse-submodules https://github.com/tu-usuario/notesmd
# o si ya estaba clonado sin el flag:
git submodule update --init --recursive
```

Para actualizar el submodule a la última versión de n8n-shbase:
```bash
cd services/n8n && git pull origin main && cd ../..
git add services/n8n && git commit -m "chore: actualizar n8n-shbase"
```

**Relación con monorepos:** un monorepo pone todo en un solo repo con herramientas
(Turborepo, Nx) que gestionan los límites entre paquetes. Los submodules son el
enfoque opuesto (multi-repo): repos independientes que se componen. Para un
template reutilizable en múltiples proyectos, submodules es la estrategia correcta.

---

## 2. Centralizar configuración de red en `.env`

Docker Compose lee el `.env` automáticamente y permite usar sus variables en el yaml.
El Makefile también puede leerlo con `-include .env`. Esto permite centralizar el
nombre de la red compartida en un solo lugar.

### `.env` del proyecto destino

```env
# Red Docker compartida entre stacks
DOCKER_NETWORK=notesmd-shared
```

### `docker-compose.yml` del proyecto destino

```yaml
networks:
  shared:
    external: true
    name: ${DOCKER_NETWORK}   # lee del .env automáticamente
  internal:
    driver: bridge
```

### `services/n8n/docker-compose.yml`

```yaml
networks:
  shared:
    external: true
    name: ${DOCKER_NETWORK}   # mismo .env, misma variable
  n8n-internal:
    driver: bridge
```

> **Nota:** Docker Compose busca el `.env` en el directorio desde donde se ejecuta
> el comando, no donde está el `docker-compose.yml`. Al usar `-f services/n8n/docker-compose.yml`
> desde la raíz del proyecto, leerá el `.env` raíz correctamente.
> Si se ejecuta desde dentro de `services/n8n/`, leerá su propio `.env`.

### `Makefile` del proyecto destino

```makefile
# Carga las variables del .env (el - ignora si no existe)
-include .env

DOCKER_NETWORK ?= notesmd-shared   # valor por defecto si .env no lo define

network:
    docker network create $(DOCKER_NETWORK) 2>/dev/null || true

up: network
    docker compose up -d
    docker compose -f services/n8n/docker-compose.yml \
        --env-file .env up -d

down:
    docker compose down
    docker compose -f services/n8n/docker-compose.yml down

up-n8n: network
    docker compose -f services/n8n/docker-compose.yml --env-file .env up -d

up-app:
    docker compose up -d
```

---

## 3. Redes entre stacks: aislamiento y comunicación selectiva

Dos `docker-compose.yml` que corren por separado crean redes distintas por defecto.
Los contenedores en redes distintas **no se ven entre sí**.

### Estrategia: red externa compartida + redes internas por stack

```
notesmd-shared  (externa, compartida)
│
├── n8n          ← puede alcanzar: qdrant, app
├── qdrant       ← accesible desde n8n para indexar/consultar vectores
└── app          ← accesible desde n8n para webhooks / callbacks

n8n-internal (privada del stack n8n)
├── n8n
└── postgres     ← solo visible dentro del stack n8n

notesmd-internal (privada del stack notesmd)
├── app
└── supabase     ← solo visible dentro del stack notesmd
```

Cada servicio se agrega **solo a las redes que necesita**. La DB interna de cada
stack nunca queda expuesta al otro.

---

## 4. Ejemplo completo: notesmd + n8n-shbase

### Estructura de archivos

```
notesmd/
├── .env                            ← DOCKER_NETWORK y vars del proyecto
├── docker-compose.yml              ← app, supabase, qdrant
├── Makefile                        ← coordina ambos stacks
└── services/
    └── n8n/                        ← git submodule de n8n-shbase
        ├── docker-compose.yml
        └── .env                    ← vars específicas de n8n (N8N_PORT, etc.)
```

### `.env` (raíz de notesmd)

```env
# Red compartida entre stacks
DOCKER_NETWORK=notesmd-shared

# App
APP_PORT=3000
```

### `docker-compose.yml` (notesmd)

```yaml
networks:
  shared:
    external: true
    name: ${DOCKER_NETWORK}
  internal:
    driver: bridge

services:
  app:
    build: .
    ports:
      - "${APP_PORT}:3000"
    networks: [shared, internal]
    environment:
      SUPABASE_URL: http://supabase:8000
      QDRANT_URL: http://qdrant:6333   # interno, no necesita pasar por shared

  supabase:
    image: supabase/postgres:15
    networks: [internal]               # nunca expuesto a n8n

  qdrant:
    image: qdrant/qdrant
    ports:
      - "6333:6333"
    networks: [shared, internal]       # n8n puede indexar/consultar vectores
```

### `services/n8n/docker-compose.yml`

```yaml
networks:
  shared:
    external: true
    name: ${DOCKER_NETWORK}            # lee del .env raíz cuando se lanza con --env-file
  n8n-internal:
    driver: bridge

services:
  n8n:
    image: n8nio/n8n:latest
    container_name: ${PROJECT_NAME}-n8n
    ports:
      - "${N8N_PORT}:5678"
    networks: [shared, n8n-internal]
    # Desde n8n se puede alcanzar por nombre de servicio:
    #   qdrant:6333   → base vectorial
    #   app:3000      → webhook callbacks a la app

  postgres:
    image: postgres:16
    container_name: ${PROJECT_NAME}-postgres
    networks: [n8n-internal]           # nunca expuesto a notesmd
```

### `Makefile` (notesmd)

```makefile
-include .env
DOCKER_NETWORK ?= notesmd-shared

network:
    docker network create $(DOCKER_NETWORK) 2>/dev/null || true

up: network
    docker compose up -d
    docker compose -f services/n8n/docker-compose.yml \
        --env-file .env \
        --env-file services/n8n/.env \
        up -d

down:
    docker compose -f services/n8n/docker-compose.yml down
    docker compose down

up-n8n: network
    docker compose -f services/n8n/docker-compose.yml \
        --env-file .env \
        --env-file services/n8n/.env \
        up -d

up-app: network
    docker compose up -d

status:
    @echo "=== notesmd ==="
    @docker compose ps
    @echo "=== n8n ==="
    @docker compose -f services/n8n/docker-compose.yml ps
```

> **Nota sobre `--env-file` múltiple:** Docker Compose acepta múltiples `--env-file`.
> El segundo sobreescribe al primero en caso de conflicto. Aquí `.env` define
> `DOCKER_NETWORK` y `services/n8n/.env` define `PROJECT_NAME`, `N8N_PORT`, etc.

---

## 5. Resumen de decisiones

| Decisión | Recomendación |
|---|---|
| Incluir n8n-shbase en otro proyecto | Git submodule en `services/n8n/` |
| Coordinar múltiples stacks | Makefile con `-f` flags (más flexible que `include`) |
| Nombre de red compartida | Centralizado en `.env` raíz como `DOCKER_NETWORK` |
| Comunicación entre stacks | Red Docker externa compartida creada con `docker network create` |
| Aislamiento de DBs internas | Red interna por stack, nunca agregada a `shared` |
| Servicios expuestos entre stacks | Solo los necesarios (ej: qdrant, app) |
