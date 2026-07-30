# Custom domains (staging)

Terraform maps hostnames to Cloud Run via `google_cloud_run_domain_mapping`
(preview — fine for staging; for production prefer a global HTTPS load balancer).

Configured in `environments/staging/terraform.tfvars`:

| Hostname | Cloud Run service |
|---|---|
| `school-staging.m-romero.dev` | `school-staging-frontend` |
| `school-staging-api.m-romero.dev` | `school-staging-backend` |

DNS for `m-romero.dev` lives at your registrar/DNS host (not in this Terraform
project). GCP only creates the domain mapping + managed certificate.

## 1. Verify the domain once

In [Google Search Console](https://search.google.com/search-console), add
`m-romero.dev` (or each subdomain) and verify ownership with the **same Google
account** that owns the GCP project `school-503805`. Without this, `terraform
apply` fails creating the domain mapping.

## 2. Apply Terraform

```bash
cd environments/staging
terraform plan
terraform apply
terraform output domain_dns_records
terraform output vite_api_url
```

`FRONTEND_URL` on the backend is set automatically to
`https://school-staging.m-romero.dev` when `frontend_domain` is set.

## 3. Create DNS records

From `terraform output -json domain_dns_records`, create each record at your
DNS provider. Typical shape:

| Type | Name | Value | Notes |
|---|---|---|---|
| CNAME | `school-staging` | `ghs.googlehosted.com.` | |
| CNAME | `school-staging-api` | `ghs.googlehosted.com.` | |

If you use Cloudflare, keep proxy **DNS only** (grey cloud) until the Google
managed certificate becomes Active — orange proxy often breaks issuance.

Certificate provisioning can take 15–60 minutes after DNS propagates.

## 4. Point the frontend build at the API domain

`VITE_API_URL` is bake-time. Set the GitHub Actions **variable** on
`my-school-app` to the Terraform output:

```bash
gh variable set VITE_API_URL -R mromero91/my-school-app \
  --body "$(cd environments/staging && terraform output -raw vite_api_url)"
```

Then re-run the frontend CI deploy so the new URL is baked into the image.

## 5. Smoke test

```bash
curl -I https://school-staging.m-romero.dev
curl -I https://school-staging-api.m-romero.dev/api/v1
```
