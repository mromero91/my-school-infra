# GitHub Actions Setup: Main → Prod Auto-Deploy

Configure estos workflows en `my-school-api` y `my-school-app` para auto-deploy a producción cuando hagas push a `main`.

## 1. Crear Workflow para Backend (my-school-api)

Crear archivo: `.github/workflows/deploy-prod.yml`

```yaml
name: Deploy Backend to Production

on:
  push:
    branches:
      - main

env:
  REGISTRY: us-central1-docker.pkg.dev
  IMAGE_NAME: escuelahub
  SERVICE_NAME: my-school-api-prod
  REGION: us-central1

jobs:
  deploy:
    runs-on: ubuntu-latest
    
    permissions:
      contents: read
      id-token: write

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      # Authenticate using Workload Identity Federation (no JSON keys!)
      - name: Authenticate to Google Cloud
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ secrets.WORKLOAD_IDENTITY_PROVIDER_PROD }}
          service_account_email: ${{ secrets.DEPLOYER_SERVICE_ACCOUNT_PROD }}

      - name: Set up Cloud SDK
        uses: google-github-actions/setup-gcloud@v2

      - name: Configure Docker authentication
        run: |
          gcloud auth configure-docker ${{ env.REGISTRY }}

      - name: Build Docker image
        run: |
          docker build \
            -t ${{ env.REGISTRY }}/${{ secrets.GCP_PROJECT_ID }}/${{ env.IMAGE_NAME }}/backend:latest \
            -t ${{ env.REGISTRY }}/${{ secrets.GCP_PROJECT_ID }}/${{ env.IMAGE_NAME }}/backend:${{ github.sha }} \
            .

      - name: Push to Artifact Registry
        run: |
          docker push ${{ env.REGISTRY }}/${{ secrets.GCP_PROJECT_ID }}/${{ env.IMAGE_NAME }}/backend:latest
          docker push ${{ env.REGISTRY }}/${{ secrets.GCP_PROJECT_ID }}/${{ env.IMAGE_NAME }}/backend:${{ github.sha }}

      - name: Deploy to Cloud Run
        run: |
          gcloud run deploy ${{ env.SERVICE_NAME }} \
            --image=${{ env.REGISTRY }}/${{ secrets.GCP_PROJECT_ID }}/${{ env.IMAGE_NAME }}/backend:latest \
            --region=${{ env.REGION }} \
            --project=${{ secrets.GCP_PROJECT_ID }} \
            --platform=managed \
            --no-allow-unauthenticated

      - name: Run database migrations
        run: |
          gcloud run jobs execute school-prod-migrate \
            --region=${{ env.REGION }} \
            --project=${{ secrets.GCP_PROJECT_ID }} \
            --wait

      - name: Notify deployment
        if: success()
        run: |
          echo "✅ Deployment successful!"
          echo "Service: https://api.escuelahub.mx/api/v1/health"

      - name: Notify failure
        if: failure()
        run: |
          echo "❌ Deployment failed. Check logs above."
          exit 1
```

## 2. Crear Workflow para Frontend (my-school-app)

Crear archivo: `.github/workflows/deploy-prod.yml`

```yaml
name: Deploy Frontend to Production

on:
  push:
    branches:
      - main

env:
  REGISTRY: us-central1-docker.pkg.dev
  IMAGE_NAME: escuelahub
  SERVICE_NAME: my-school-app-prod
  REGION: us-central1

jobs:
  deploy:
    runs-on: ubuntu-latest
    
    permissions:
      contents: read
      id-token: write

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set Node.js version
        uses: actions/setup-node@v4
        with:
          node-version: '22'

      - name: Install pnpm
        uses: pnpm/action-setup@v2
        with:
          version: 9

      - name: Install dependencies
        run: pnpm install --frozen-lockfile

      # Build with VITE_API_URL pointing to prod backend
      - name: Build Vite frontend
        run: |
          VITE_API_URL=https://api.escuelahub.mx/api/v1 \
          pnpm build

      - name: Authenticate to Google Cloud
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ secrets.WORKLOAD_IDENTITY_PROVIDER_PROD }}
          service_account_email: ${{ secrets.DEPLOYER_SERVICE_ACCOUNT_PROD }}

      - name: Set up Cloud SDK
        uses: google-github-actions/setup-gcloud@v2

      - name: Configure Docker authentication
        run: |
          gcloud auth configure-docker ${{ env.REGISTRY }}

      - name: Build Docker image
        run: |
          docker build \
            -t ${{ env.REGISTRY }}/${{ secrets.GCP_PROJECT_ID }}/${{ env.IMAGE_NAME }}/frontend:latest \
            -t ${{ env.REGISTRY }}/${{ secrets.GCP_PROJECT_ID }}/${{ env.IMAGE_NAME }}/frontend:${{ github.sha }} \
            .

      - name: Push to Artifact Registry
        run: |
          docker push ${{ env.REGISTRY }}/${{ secrets.GCP_PROJECT_ID }}/${{ env.IMAGE_NAME }}/frontend:latest
          docker push ${{ env.REGISTRY }}/${{ secrets.GCP_PROJECT_ID }}/${{ env.IMAGE_NAME }}/frontend:${{ github.sha }}

      - name: Deploy to Cloud Run
        run: |
          gcloud run deploy ${{ env.SERVICE_NAME }} \
            --image=${{ env.REGISTRY }}/${{ secrets.GCP_PROJECT_ID }}/${{ env.IMAGE_NAME }}/frontend:latest \
            --region=${{ env.REGION }} \
            --project=${{ secrets.GCP_PROJECT_ID }} \
            --platform=managed \
            --allow-unauthenticated

      - name: Notify deployment
        if: success()
        run: |
          echo "✅ Frontend deployment successful!"
          echo "URL: https://escuelahub.mx"

      - name: Notify failure
        if: failure()
        run: |
          echo "❌ Frontend deployment failed. Check logs above."
          exit 1
```

## 3. Configurar GitHub Secrets

En cada repositorio (`my-school-api` y `my-school-app`):

1. Ve a **Settings → Secrets and variables → Actions**
2. Crea los siguientes secrets:

### Backend Secrets (my-school-api)

| Secret | Valor | Origen |
|--------|-------|--------|
| `GCP_PROJECT_ID` | tu-project-id | Tu ID en GCP |
| `WORKLOAD_IDENTITY_PROVIDER_PROD` | `providers/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/POOL_NAME/providers/PROVIDER_NAME` | Ejecutar: `terraform output -raw workload_identity_provider` en `environments/prod/` |
| `DEPLOYER_SERVICE_ACCOUNT_PROD` | `school-prod-be-deployer@PROJECT_ID.iam.gserviceaccount.com` | Ejecutar: `terraform output -raw backend_deployer_email` en `environments/prod/` |

### Frontend Secrets (my-school-app)

| Secret | Valor | Origen |
|--------|-------|--------|
| `GCP_PROJECT_ID` | tu-project-id | Tu ID en GCP |
| `WORKLOAD_IDENTITY_PROVIDER_PROD` | (igual que backend) | Ejecutar: `terraform output -raw workload_identity_provider` en `environments/prod/` |
| `DEPLOYER_SERVICE_ACCOUNT_PROD` | `school-prod-fe-deployer@PROJECT_ID.iam.gserviceaccount.com` | Ejecutar: `terraform output -raw frontend_deployer_email` en `environments/prod/` |

## 4. Obtener Valores de Terraform

Después de completar `terraform apply` en prod:

```bash
cd environments/prod

# Copiar estos valores a GitHub Secrets
terraform output -raw workload_identity_provider
terraform output -raw backend_deployer_email
terraform output -raw frontend_deployer_email
terraform output -raw gcp_project_id  # o usar el tuyo directamente
```

## 5. Probar el Workflow

```bash
# En my-school-api
git checkout main
echo "test" >> README.md
git add README.md
git commit -m "test: trigger prod deploy"
git push origin main

# Ir a GitHub → Actions → Deploy Backend to Production
# Monitorear logs
```

Debería ver:
1. Build Docker image ✓
2. Push a Artifact Registry ✓
3. Deploy a Cloud Run ✓
4. Run migrations ✓

## 6. Monitorear Deployments

### Cloud Run Logs

```bash
# Ver últimos logs del backend
gcloud run services describe my-school-api-prod \
  --region=us-central1 \
  --project=<id>

# Ver logs en tiempo real
gcloud run services logs read my-school-api-prod \
  --region=us-central1 \
  --project=<id> \
  --limit=50
```

### GitHub Actions

- Ve a **Actions** en ambos repos
- Monitorea `Deploy Backend to Production` y `Deploy Frontend to Production`
- Revisa logs si hay fallos

## 7. Rollback Rápido

Si algo sale mal después del deploy:

```bash
# Revertir a última imagen funcional
gcloud run deploy my-school-api-prod \
  --image=us-central1-docker.pkg.dev/<project>/escuelahub/backend:COMMIT_HASH_ANTERIOR \
  --region=us-central1 \
  --project=<id>

# O simplemente hacer push a main con un commit anterior
git revert HEAD
git push origin main
# El workflow se dispara automáticamente
```

## 8. Checklist Final

- [ ] ✅ Workflows `.github/workflows/deploy-prod.yml` creados en ambos repos
- [ ] ✅ GitHub Secrets configurados en ambos repos
- [ ] ✅ `terraform apply` completado en prod
- [ ] ✅ Test push a main en ambos repos
- [ ] ✅ Deployments exitosos en Cloud Run
- [ ] ✅ Endpoints https://escuelahub.mx y https://api.escuelahub.mx responden
- [ ] ✅ Migraciones de DB ejecutadas sin errores

---

## Notas Importantes

1. **Workload Identity Federation:** No usa JSON keys. Los workflows intercambian tokens OIDC de GitHub por credenciales GCP de corta vida.

2. **Frontend VITE_API_URL:** Se bake en build time (no en runtime). Asegúrate que el valor coincida con tu backend en prod.

3. **Permisos:** Los deployers SAs solo tienen permisos para `run.developer` (deploy) y `artifactregistry.writer` (push images). No pueden destruir ni modificar BD.

4. **Migrations:** Se ejecutan automáticamente después del deploy del backend. Usa `--wait` para bloquear hasta que completen.

5. **Rollback:** Es tan simple como hacer push a main con un commit anterior o cambiar la imagen manualmente.
