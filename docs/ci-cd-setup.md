# CI/CD setup — GitHub Actions → Cloud Run

Los pipelines ya están en cada repo (`backend/.github/workflows/ci-cd.yml`,
`frontend/.github/workflows/ci-cd.yml`). Esto es lo que falta hacer a mano,
una sola vez, para que funcionen.

## 1. Aplicar el Terraform (WIF + service accounts de deploy)

```bash
cd school-infra/environments/staging
terraform plan     # deberías ver: 1 pool, 1 provider, 2 SAs nuevas, 4 IAM bindings
terraform apply
```

Esto crea:
- Un Workload Identity Pool/Provider que confía en tokens OIDC de GitHub Actions,
  restringido a repos del owner `mromero91`.
- `school-staging-be-deployer` y `school-staging-fe-deployer`: service accounts
  dedicadas solo a deployar cada servicio (no las mismas que usan los
  contenedores en runtime).
- Permiso de cada deployer para actuar como su SA de runtime correspondiente,
  y para autenticarse vía WIF *solo* desde su propio repo (my-school-api no puede
  usar la SA de my-school-app, y viceversa).

## 2. Sacar los valores para los secrets de GitHub

```bash
terraform output workload_identity_provider
terraform output backend_deployer_email
terraform output frontend_deployer_email
terraform output backend_url    # para VITE_API_URL del frontend
```

## 3. Configurar secrets/variables en GitHub

**En `mromero91/my-school-api`** (Settings → Secrets and variables → Actions):

| Tipo | Nombre | Valor |
|---|---|---|
| Secret | `GCP_WORKLOAD_IDENTITY_PROVIDER` | output `workload_identity_provider` |
| Secret | `GCP_BACKEND_DEPLOYER_SA` | output `backend_deployer_email` |
| Secret | `SONAR_TOKEN` | ver paso 4 |

**En `mromero91/my-school-app`**:

| Tipo | Nombre | Valor |
|---|---|---|
| Secret | `GCP_WORKLOAD_IDENTITY_PROVIDER` | output `workload_identity_provider` |
| Secret | `GCP_FRONTEND_DEPLOYER_SA` | output `frontend_deployer_email` |
| Variable | `VITE_API_URL` | output `vite_api_url` (custom API domain + `/api/v1`) |

## 4. Crear el proyecto en SonarCloud (solo backend)

1. Entra a https://sonarcloud.io con tu cuenta de GitHub.
2. "+" → Analyze new project → selecciona `mromero91/my-school-api`.
3. Confirma que la organización (`sonar.organization`) y el project key
   (`sonar.projectKey`) coincidan con `backend/sonar-project.properties`
   (por defecto puse `mromero91` / `mromero91_api-school` — ajústalos si
   SonarCloud te asigna otros al crear el proyecto).
4. En "Analysis Method", elige **GitHub Actions** (no "Automatic Analysis" —
   ese modo choca con el scan que corre el pipeline).
5. My Account → Security → genera un token → guárdalo como el secret
   `SONAR_TOKEN` en `my-school-api`.

## 5. Migraciones de base de datos (automáticas en deploy)

Terraform crea el Cloud Run Job `school-staging-migrate` (mismo image/SA/
Cloud SQL que el backend). El workflow de `my-school-api` hace, **antes**
de desplegar la nueva revisión:

1. `gcloud run jobs update … --image=<nueva tag>`
2. `gcloud run jobs execute … --wait` → corre `npx prisma migrate deploy`
3. Solo si eso sale bien → `gcloud run deploy` del servicio

Si el job aún no existe (primer setup), aplica Terraform en staging antes
del primer push que despliegue:

```bash
cd school-infra/environments/staging
terraform plan   # deberías ver google_cloud_run_v2_job.migrate
terraform apply
```

Hotfix manual (si hace falta sin redeploy):

```bash
gcloud run jobs execute school-staging-migrate \
  --project=school-503805 --region=us-central1 --wait
```

## 6. Primer deploy

Los workflows solo hacen build+push+deploy en `push` (no en pull_request).
Para el primer despliegue real, mergea a `develop` o `main` — el pipeline
reemplazará la imagen placeholder (`hello`) que Terraform dejó puesta.
