## Idea: n8n-docker-template

La idea es implementar una arquitectura para un Template Repository diseñado para desplegar instancias aisladas de n8n mediante Docker. (para iniciarlas como instancias dev en distintos proyecto, con la posibilidad de generard las instancias de produccion)
El objetivo es proporcionar una base sólida y reproducible que permita inicializar entornos de automatización específicos por proyecto (ej. notesmd, gastos-personal) con configuraciones de red y persistencia independientes.
Los primeros casos de aplicacion que me interesa probar: (estos son ejemplos para las instancias, proyectos separados a este. Son de forma orientativa para comprender este proyecto)
    1. Una instancia docker n8n para integrarse con una app next + reac (notesmd) sobre la cual configurar workflows que permitan por ejemplo:
       1. adjuntar un documento a una nota y que se realiza un summary del documento escrito en la nota.
       2. integrar la carga de notas por telegram
       3. integrar IA con RAG sobre las notas y que esta se puede usar via telegram
       4. etc...
    2. Una instacia docker n8n para un workflow personal en el que pueda cargar por telegram o wsp comprobantes de pago de diferentes formatos, o pasarle texto con slash command especificos para que un agente actualice documentos de google sheet y registre los gastos.
    3. Una instancia docker n8n para integrar con una aplicacion ERP:
       1.  en la que se puedan pasar documentos por telegram y se les haga un procesamiento determinado
       2.  registrar horarios de empleados via telegram
       3.  etc...

### Arquitectura propuesta para las instancias
Se propone un modelo de Aislamiento por Proyecto utilizando contenedores independientes. A diferencia de un mono-repo tradicional donde una sola instancia maneja todo, este enfoque permite que cada proyecto tenga su propio ciclo de vida, base de datos y variables de entorno.
Multi-instancia (Sugerida)	Un contenedor n8n + DB por cada proyecto.	Aislamiento total; portabilidad; backups independientes.	Mayor overhead de recursos; gestión de puertos.

### Componentes del Repositorio Modelo
Para que el repositorio funcione como una plantilla efectiva, deberia incluir los siguientes elementos base:
- Estructura de Archivos:
  - docker-compose.yml: Define los servicios (n8n, PostgreSQL).
  - .env.example: Plantilla de variables críticas.
  - volumes/: Directorios para persistencia de datos y certificados.
  - scripts/: Scripts de inicialización o backup.

### Puntos Clave de la Documentación n8n (Self-Hosted)
Basado en las referencias de n8n-io/n8n-docs, es fundamental incluir en la plantilla:
- Persistencia de Datos: El uso de volúmenes para /home/node/.n8n es mandatorio para no perder flujos ni configuraciones al reiniciar contenedores.
- Seguridad y Cifrado: Definir obligatoriamente N8N_ENCRYPTION_KEY. Si no se define de forma estática, n8n generará una nueva y los datos cifrados (credenciales) serán ilegibles si el contenedor se recrea sin persistencia del archivo de configuración.
- Base de Datos Externa: n8n recomienda PostgreSQL sobre SQLite para entornos que requieran mayor concurrencia o estabilidad a largo plazo.
- Configuración de Webhooks: El parámetro WEBHOOK_URL es crítico. Debe coincidir con la URL pública o local accesible para que los servicios externos (GitHub, Stripe, etc.) puedan enviar datos a n8n.

### Integración con Ecosistema de Agentes (MCP)
El flujo de desarrollo se optimizará mediante el uso de Model Context Protocol (MCP):

- n8n-mcp: Se integrará para permitir que Claude Code interactúe directamente con la API de n8n (crear workflows, listar nodos, ejecutar tests).
  - https://github.com/czlonkowski/n8n-mcp
  - https://deepwiki.com/czlonkowski/n8n-mcp

- DeepWiki-mcp: para obtener info del repo
  - Ejemplo: https://deepwiki.com/n8n-io/n8n-docs, deepwiki.com/n8n-io/n8n


1. Estrategia de Despliegue (Workflow Sugerido)
   - Clonación: git clone del Template Repo hacia un nuevo repositorio de proyecto.
   - Configuración de Entorno: * Copiar .env.example a .env.
   - Asignar un N8N_PORT único para evitar colisiones en el host.
   - Definir el PROJECT_NAME para etiquetar los contenedores.
   - Ejecución: docker compose up -d.
   - Aprovisionamiento: Uso de Claude Code para inyectar los primeros workflows base mediante n8n-mcp.

### Opcion
- Veo que existe Self-hosted AI starter kit, pero no estoy seguro que sea lo apropiado para el caso de uso que estoy planteando.

### Referencias generales:
- https://docs.devin.ai/es/work-with-devin/deepwiki-mcp
- https://deepwiki.com/czlonkowski/n8n-mcp
- https://deepwiki.com/n8n-io/n8n
- https://deepwiki.com/n8n-io/n8n-docs
- https://github.com/czlonkowski/n8n-mcp
- https://github.com/n8n-io/n8n-docs/tree/main
- https://docs.n8n.io/hosting/installation/docker/
- https://docs.n8n.io/hosting/configuration/environment-variables/
- https://docs.n8n.io/hosting/configuration/user-management-self-hosted/
- https://docs.n8n.io/hosting/starter-kits/ai-starter-kit/

### Ideas / Features Futuros

#### CLI nativa para n8n-shbase

**Objetivo inferido:** reemplazar el Makefile + scripts Bash actuales por una herramienta de línea de comandos propia (`n8n-shbase` o `nsh`) que gestione el ciclo de vida de las instancias con subcomandos claros (`init`, `up`, `down`, `reset`, `status`...), distribución como binario único sin dependencias, y potencialmente una TUI interactiva para gestionar múltiples instancias desde un solo lugar.

**Análisis de opciones:**

| Opción | Ventaja principal | Desventaja para este caso |
|---|---|---|
| **Go + Cobra** | Binario estático, estándar de infraestructura (Docker/K8s usan esto), excelente para wrappers de docker compose | Curva de aprendizaje si no hay experiencia previa en Go |
| **Rust + Clap** | Máximo rendimiento y seguridad de memoria | Complejidad innecesaria para una CLI de orquestación de Docker |
| **Node.js/TS + oclif** | Desarrollo rápido, familiar para devs web | Requiere Node.js en el sistema destino (o bundle pesado) |
| **Bash + Gum** | Mínimo cambio desde el estado actual, interactividad visual con poco esfuerzo | Sigue siendo un script con dependencias externas; no es un binario distribuible |
| **Just** | Reemplaza Makefile con sintaxis más limpia, sin necesidad de compilar nada | Es solo un command runner, no permite lógica compleja ni TUI |

**Recomendación: Go + Cobra (+ Bubble Tea opcional)**

Go es la elección más adecuada para este caso por las siguientes razones:

1. **Alineación con el ecosistema**: la CLI wrappea `docker compose` — el mismo lenguaje que usa Docker. Los patrones son idénticos.
2. **Binario estático**: se distribuye como un único ejecutable sin requerir Go, Node.js ni ningún runtime en el sistema donde se use. Ideal para que cualquier colaborador del proyecto pueda usarlo clonando solo el repo.
3. **Cobra maneja la estructura de subcomandos** (`nsh init`, `nsh up`, `nsh reset`) con help automático y autocompletado sin trabajo extra.
4. **Bubble Tea** (de Charm.sh) permitiría agregar a futuro una TUI para listar y gestionar múltiples instancias activas visualmente — muy útil cuando haya varios proyectos corriendo en paralelo.
5. **Madurez y ejemplos**: abundante documentación y proyectos de referencia (el propio CLI de GitHub, Terraform, etc. siguen este patrón).

**Scope sugerido para una primera versión:**
- Subcomandos: `init`, `up`, `down`, `restart`, `logs`, `status`, `reset`
- Lectura de configuración desde `.env` (con Viper)
- Sin TUI en v1 — agregar con Bubble Tea en v2 si se valida la necesidad

**No implementar hasta:** completar y validar el template base con Bash/Makefile. La CLI es una mejora de UX, no un prerequisito funcional.

### Objetivos:
- Analizar en profundidad esta informacion y los objetivos propuestos para determinar una propuesta de implementacion que los satisfaga. Buscar en internet sobre otras fuentes y recursos de ser necesario.
- Escribir en un documento session.md en .agents/working-context/init/ el analisis y las opciones propuestas.
- Si hay mas informacion que requieras, puedes frenar el analisis y consultarme.