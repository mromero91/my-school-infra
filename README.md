# school-infra

Terraform para la infraestructura de staging de **MiEscuela+** (backend NestJS + frontend Vite/React) en GCP. Ver `../docs/pricing.md` para el modelo de negocio; este repo es solo infraestructura.

## Arquitectura (staging)

- **Backend** (`backend/`): Cloud Run v2, escala a 0, con un **sidecar Redis** (`redis:7-alpine`) en vez de Memorystore — evita el costo fijo (~$35/mes) de Memorystore para el piloto. Se conecta a Cloud SQL vía el conector nativo de Cloud Run (`/cloudsql` socket), no por IP pública.
- **Frontend** (`frontend/`): Cloud Run v2 sirviendo el build estático de Vite, escala a 0.
- **Base de datos**: Cloud SQL Postgres, tier `db-f1-micro`, sin HA (`ZONAL`), 10GB disco.
- **Uploads**: bucket de Cloud Storage (ya referenciado como `GCP_BUCKET_NAME` en `backend/.env.example`).
- **Secrets**: Secret Manager (`DATABASE_URL`, `JWT_SECRET`, `JWT_REFRESH_SECRET`), inyectados como secret refs en Cloud Run — nunca como env var plano.
- **Imágenes**: un repo de Artifact Registry para ambas imágenes.

Estructura del repo, calcada del patrón que ya usamos en melodix-infra:

```
modules/           # artifact-registry, storage, secrets, database, iam, cloud-run, cloud-run-job
environments/
  staging/         # única env por ahora — agregar environments/prod/ cuando se necesite
```

Migraciones Prisma: Cloud Run Job `school-staging-migrate` (módulo
`cloud-run-job`). El CI del backend lo ejecuta con `--wait` antes de cada
deploy — ver [docs/ci-cd-setup.md](docs/ci-cd-setup.md).

## Costo estimado (piloto, 1 escuela)

| Ítem | Costo/mes |
|---|---|
| Cloud Run backend + frontend (scale-to-zero, tráfico bajo) | $0–8 |
| Cloud SQL `db-f1-micro` + 10GB | $10–15 |
| Cloud Storage + egress | $1–3 |
| Artifact Registry / builds | $0–2 |
| Redis (sidecar, no Memorystore) | $0 |
| **Total** | **~$15–25/mes** |

Si más adelante se necesita Redis persistente (no sidecar) o alta disponibilidad, ver notas en `modules/cloud-run/main.tf` — el cambio a Memorystore sube el total a ~$45–60/mes.

## Uso

1. **Bootstrap** (una sola vez, requiere `gcloud auth login` con permisos de owner/editor en el proyecto):
   ```
   ./scripts/bootstrap.sh <project_id> [region]
   ```
   Habilita las APIs necesarias y crea el bucket de state en GCS.

2. **Configurar variables**:
   ```
   cd environments/staging
   cp terraform.tfvars.example terraform.tfvars   # editar project_id, etc.
   ```
   `db_password`, `jwt_secret`, `jwt_refresh_secret` no van en el `.tfvars` — pásalos con `-var` o variables de entorno `TF_VAR_*`.

3. **Init + plan** (no corras `apply` sin revisar el plan primero):
   ```
   terraform init -backend-config="bucket=<project_id>-tfstate" -backend-config="prefix=staging"
   terraform plan
   ```

4. **Apply** — esto sí crea recursos facturables en GCP, confirmar antes de correrlo:
   ```
   terraform apply
   ```

5. **Primer deploy real**: el `apply` inicial deja Cloud Run corriendo con una imagen placeholder (`hello`). Construye y sube las imágenes reales a Artifact Registry (`outputs.artifact_registry_repository`) y despliega con `gcloud run deploy` o CI — el módulo `cloud-run` ya ignora cambios de imagen hecho por Terraform (`lifecycle.ignore_changes`) para no pelear con deploys de CI.

## Dominios custom (staging)

Ver [docs/custom-domains.md](docs/custom-domains.md). Terraform crea los
domain mappings de Cloud Run; los CNAMEs de `m-romero.dev` se agregan a mano
en tu DNS a partir de `terraform output domain_dns_records`.

## Pendiente / no incluido aún

- `environments/prod/` — duplicar `staging/` cuando se negocie el contrato distrital, probablemente con HA en Cloud SQL y Memorystore real + load balancer (no domain mapping preview).
- DNS de `m-romero.dev` no vive en este Terraform (el dominio está fuera de GCP).
- `VITE_API_URL` es bake-time de Vite: usa `terraform output vite_api_url` como variable de GitHub Actions en `my-school-app` y redespliega el frontend.
