# my-school-infra

Infraestructura de **MiEscuela+** en Google Cloud Platform, gestionada con Terraform.

Solo staging por ahora. Los servicios viven en repos separados:

| Repo | Rol |
|---|---|
| [`my-school-api`](https://github.com/mromero91/my-school-api) | Backend NestJS → Cloud Run |
| [`my-school-app`](https://github.com/mromero91/my-school-app) | Frontend Vite/React → Cloud Run |
| **my-school-infra** (este) | Terraform + bootstrap |

## Arquitectura (staging)

```
                    ┌─────────────────────────────────────┐
  DNS (externo)     │  school-staging(.api).m-romero.dev  │
                    └──────────────┬──────────────────────┘
                                   │ Cloud Run domain mapping
           ┌───────────────────────┴───────────────────────┐
           ▼                                               ▼
   Frontend (Cloud Run)                          Backend (Cloud Run)
   scale-to-zero · port 8080                     scale-to-zero · port 3000
                                                 + Redis sidecar (redis:7-alpine)
           │                                               │
           │                                    ┌──────────┼──────────┐
           │                                    ▼          ▼          ▼
           │                              Cloud SQL   Secret Mgr   GCS uploads
           │                              Postgres    JWT + DB URL
           │                              db-f1-micro
           │                                    ▲
           │                         Cloud Run Jobs: migrate + seed
           ▼                                    │
   Artifact Registry ◄──── GitHub Actions (OIDC / WIF, sin JSON keys)
```

| Componente | Detalle |
|---|---|
| **Backend** | Cloud Run v2, min 0 / max 2. Redis en **sidecar** (no Memorystore) para el piloto. Cloud SQL vía conector Unix socket (`/cloudsql`), no IP pública. |
| **Frontend** | Cloud Run v2 sirviendo el build estático de Vite. `VITE_API_URL` se bakea en build (CI), no en runtime. |
| **DB** | Cloud SQL Postgres `db-f1-micro`, ZONAL, 10 GB. Backups off en piloto. |
| **Migraciones** | Job `school-staging-migrate` (`prisma migrate deploy`). El CI del API lo ejecuta con `--wait` antes de cada deploy. |
| **Seed** | Job `school-staging-seed` (`node dist/prisma/seed.js`). Manual — no corre en cada deploy. |
| **Secrets** | Secret Manager (`DATABASE_URL`, `JWT_SECRET`, `JWT_REFRESH_SECRET`) inyectados como secret refs en Cloud Run. |
| **CI/CD** | Workload Identity Federation → SAs deployer por repo (`my-school-api` / `my-school-app`). |
| **Dominios** | Domain mappings opcionales; DNS fuera de este Terraform. |

## Estructura

```
my-school-infra/
├── docs/
│   ├── ci-cd-setup.md       # Secrets de GitHub + SonarCloud + primer deploy
│   └── custom-domains.md    # Domain mappings + CNAMEs
├── environments/
│   └── staging/             # Única env por ahora → environments/prod/ cuando toque
├── modules/
│   ├── artifact-registry/
│   ├── cloud-run/
│   ├── cloud-run-job/
│   ├── database/
│   ├── github-oidc/
│   ├── iam/
│   ├── secrets/
│   └── storage/
└── scripts/
    └── bootstrap.sh         # APIs + bucket de state (una vez)
```

## Requisitos

- [Terraform](https://developer.hashicorp.com/terraform/install) `>= 1.7`
- [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) (`gcloud`) autenticado con rol Owner/Editor en el proyecto
- Permisos para crear el bucket de state y los recursos listados arriba

## Costo estimado (piloto, 1 escuela)

| Ítem | $/mes |
|---|---|
| Cloud Run backend + frontend (scale-to-zero, tráfico bajo) | 0–8 |
| Cloud SQL `db-f1-micro` + 10 GB | 10–15 |
| Cloud Storage + egress | 1–3 |
| Artifact Registry / builds | 0–2 |
| Redis (sidecar, no Memorystore) | 0 |
| **Total** | **~15–25** |

Memorystore + HA subirían el total a ~$45–60/mes. Notas en `modules/cloud-run/main.tf`.

## Uso

### 1. Bootstrap (una sola vez)

```bash
gcloud auth login
gcloud auth application-default login
./scripts/bootstrap.sh <project_id> [region]   # default region: us-central1
```

Habilita APIs y crea el bucket GCS `<project_id>-tfstate` (con versioning) para el state remoto.

### 2. Variables

```bash
cd environments/staging
cp terraform.tfvars.example terraform.tfvars
# Editar project_id, dominios opcionales, etc.
```

Los secretos **no** van commiteados. Opciones:

```bash
# A) En terraform.tfvars local (gitignored), o
# B) Por entorno / CLI:
export TF_VAR_db_password='...'
export TF_VAR_jwt_secret='...'
export TF_VAR_jwt_refresh_secret='...'
```

### 3. Init + plan

```bash
terraform init \
  -backend-config="bucket=<project_id>-tfstate" \
  -backend-config="prefix=staging"

terraform plan
```

### 4. Apply

Crea recursos facturables — revisa el plan antes:

```bash
terraform apply
```

El apply inicial deja Cloud Run con imagen placeholder (`hello`). Las imágenes reales las sube CI a Artifact Registry; el módulo `cloud-run` usa `lifecycle.ignore_changes` en la imagen para no pelear con deploys de GitHub Actions.

### 5. Post-apply

```bash
terraform output
```

| Output | Uso |
|---|---|
| `workload_identity_provider` | Secret GitHub (ambos repos) |
| `backend_deployer_email` / `frontend_deployer_email` | Secrets de deploy por repo |
| `vite_api_url` | Variable `VITE_API_URL` en `my-school-app` |
| `domain_dns_records` | CNAMEs en tu DNS |
| `artifact_registry_repository` | Destino de `docker push` |
| `migrate_job_name` | `gcloud run jobs execute …` (migrate) |
| `seed_job_name` | `gcloud run jobs execute …` (seed manual) |

Siguiente: [docs/ci-cd-setup.md](docs/ci-cd-setup.md) y, si usas dominios custom, [docs/custom-domains.md](docs/custom-domains.md).

## Dominios custom

Terraform crea los domain mappings de Cloud Run. Los CNAMEs de `m-romero.dev` se agregan a mano en el DNS a partir de `terraform output domain_dns_records`. Guía completa: [docs/custom-domains.md](docs/custom-domains.md).

## Pendiente / fuera de alcance

- `environments/prod/` — HA en Cloud SQL, Memorystore real, load balancer HTTPS (no domain mapping preview).
- DNS de `m-romero.dev` (fuera de GCP / este repo).
- `VITE_API_URL` bake-time: sincronizar con `terraform output -raw vite_api_url` en GitHub Actions y redesplegar el frontend.
