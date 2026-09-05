# Production Environment Configuration

This environment represents the **MiEscuela+ production deployment** with full High Availability (HA).

## Key Differences from Staging

### Database (Cloud SQL)

| Feature | Staging | Production |
|---------|---------|------------|
| Instance Class | `db-f1-micro` (0.6 CPU, 0.6 GB RAM) | `db-custom-2-8192` (2 CPU, 8 GB RAM) |
| Availability | ZONAL (single AZ, no HA) | REGIONAL (HA with automatic failover) |
| Backups | Disabled (no real data yet) | Enabled with point-in-time recovery |
| Connection | via Cloud SQL sidecar in Cloud Run | via Cloud SQL Connector (same) |

**Regional HA Detail:** When a Cloud SQL instance is set to `availability_type = "REGIONAL"`, GCP automatically:
- Provisions a replica standby instance in a different AZ within the same region
- Performs automatic failover when the primary fails (RTO < 5 min)
- Maintains synchronous replication for data durability

### Redis Cache (Memorystore)

| Feature | Staging | Production |
|---------|---------|------------|
| Type | Sidecar (`redis:7-alpine`) in Cloud Run | Managed Memorystore Redis |
| Tier | N/A (ephemeral) | STANDARD_HA |
| Durability | Lost on pod scale-to-zero | Persistent with automatic failover |
| Memory | 256 MB | 1 GB (configurable via `redis_memory_size_gb`) |

**Memorystore STANDARD_HA Detail:** Provides active-passive replication with automatic failover within the region. Each instance placement group automatically gets a standby replica that takes over on primary failure (< 30 seconds).

### Cloud Run Services

| Setting | Staging | Production |
|---------|---------|------------|
| Backend min_instances | 0 (scale-to-zero) | 1 (always warm) |
| Frontend min_instances | 0 (scale-to-zero) | 1 (always warm) |
| Redis Connection | `localhost:6379` (sidecar) | Memorystore host/port |

**Always-Warm Strategy:** `min_instances = 1` ensures:
- No cold start latency on first request
- Consistent tail latency for user experience
- Predictable cost (at least 1 vCPU + memory always running)

## Deployment

### Prerequisites

1. **GCP Project** with `compute.googleapis.com`, `sqladmin.googleapis.com`, `redis.googleapis.com`, `run.googleapis.com` APIs enabled.

2. **Terraform Backend** configured: a GCS bucket for state (remote state is mandatory for prod):
   ```bash
   terraform init \
     -backend-config="bucket=<your-state-bucket>" \
     -backend-config="prefix=prod"
   ```

3. **Secrets in Secret Manager** (create these before `terraform apply`):
   - `school-prod-database-url`: `postgresql://...` (auto-generated, but can override)
   - `school-prod-jwt-secret`: Long random string for JWT signing
   - `school-prod-jwt-refresh-secret`: Separate long random string
   - `school-prod-sendgrid-api-key`: SendGrid API key (or empty to disable email)
   - `school-prod-twilio-auth-token`: Twilio auth token
   - `school-prod-twilio-account-sid`: Twilio account SID

### First Deploy

1. **Copy the example tfvars:**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Fill in secrets** (do NOT commit `terraform.tfvars`):
   ```hcl
   project_id  = "your-prod-gcp-project"
   region      = "us-central1"
   
   # Provide via environment or at prompt:
   # db_password        = "..."
   # jwt_secret         = "..."
   # jwt_refresh_secret = "..."
   ```

3. **Plan the deployment:**
   ```bash
   terraform plan -out=tfplan
   ```

4. **Review the plan** carefully:
   - New resources: database, Redis, Cloud Run services
   - Storage bucket, IAM roles, Secrets
   - No destructive changes expected on first apply

5. **Apply:**
   ```bash
   terraform apply tfplan
   ```

6. **After apply, run the migration:**
   ```bash
   gcloud run jobs execute school-prod-migrate --wait --region us-central1
   ```

## Monitoring & Maintenance

### Database
- **Cloud SQL Insights** in Cloud Console: CPU, disk I/O, replication lag
- **Backups:** Automated daily backups; can restore via Cloud Console or `gcloud sql backups restore`
- **Failover Testing:** Monthly manual failover in dev/staging to validate RTO/RPO

### Redis
- **Memory Usage:** Monitor in Cloud Monitoring; set up alerts at 80%+ utilization
- **Eviction Policy:** Default is `noeviction`; if reaching memory limit, review cache strategy in the app
- **AUTH:** Credentials stored in Secret Manager; rotate regularly

### Cloud Run
- **Concurrency & Throughput:** Monitor via Cloud Logging; adjust `max_instances` if hitting quota
- **Cold Starts:** Should be zero or near-zero with `min_instances = 1`
- **Cost Tracking:** CPU, memory, request count visible in Cloud Console

## Cost Estimates (Approximate, us-central1)

- **Cloud SQL db-custom-2-8192 Regional HA:** ~$280-350/month
  - includes storage, backups, HA replica
- **Memorystore STANDARD_HA 1GB:** ~$70-100/month
  - includes standby replica
- **Cloud Run (backend + frontend, 2 min + traffic):** ~$150-200/month
- **GCS Storage (uploads bucket):** ~$10-20/month
- **Network egress:** ~$100-200/month (depending on data transferred)

**Total estimate:** $600-900/month for a small production deployment.

## Disaster Recovery

### Data Retention
- **Database:** PITR enabled; 35-day automatic backup retention (configurable)
- **GCS uploads:** Versioning disabled; recommend enabling for important files
- **Redis:** Not backed up (ephemeral cache data); no RTO requirement

### Failover Procedure
1. **Database:** Automatic; no action required. Monitor Cloud SQL dashboard for replica promotion.
2. **Redis:** Automatic within 30 seconds; no action required.
3. **Cloud Run:** Stateless; automatic; new replicas spin up on failure.

### Manual Recovery
- **Database Restore:** `gcloud sql backups restore <backup-id> --backup-instance=<instance>`
- **Cloud Run Redeployment:** Re-run CI/CD pipeline to push latest image

## Security Notes

- **Secrets:** All sensitive data (passwords, tokens) stored in Secret Manager, never in `.tfvars` or code
- **IAM:** Least-privilege roles per service account:
  - Backend SA: `roles/cloudsql.client`, `roles/secretmanager.secretAccessor`, `roles/storage.objectAdmin`
  - Frontend SA: None (public, unauthenticated)
  - Deployer SAs: `roles/run.developer`, `roles/artifactregistry.writer` (CI/CD only)
- **Workload Identity Federation (WIF):** GitHub Actions authenticate via OIDC, no long-lived keys
- **Network:** Cloud Run and Cloud SQL are in the same region; Redis via managed VPC peering

## Checklist for Going Live

- [ ] All Cloud SQL automated backups confirmed working
- [ ] Database PITR tested (restore a backup to dev to verify)
- [ ] Redis AUTH enabled and password in Secret Manager
- [ ] Custom domains (e.g., `school.m-romero.dev`, `school-api.m-romero.dev`) verified in Google Search Console
- [ ] DNS CNAMEs created for Cloud Run domain mappings
- [ ] SendGrid/Twilio credentials verified (send test email/SMS)
- [ ] Logging + monitoring dashboards set up in Cloud Console
- [ ] Runbook for on-call engineer (restart procedures, escalation)
- [ ] Staging environment running in parallel for testing
- [ ] Failover drill completed (kill primary database, verify failover works)
