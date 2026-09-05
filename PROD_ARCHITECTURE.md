# Production Architecture: MiEscuela+ HA Stack

## Overview

This document describes the production infrastructure architecture for MiEscuela+ with full High Availability (HA) configured in `environments/prod/`.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         GCP Project (prod)                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌───────────────────────┐        ┌───────────────────────┐   │
│  │  Cloud Run Backend    │        │ Cloud Run Frontend    │   │
│  │ (min_instances: 1)    │        │ (min_instances: 1)    │   │
│  │                       │        │                       │   │
│  │ • NODE_ENV=prod       │        │ • Built with React   │   │
│  │ • 2 max instances     │        │ • 2 max instances     │   │
│  │ • Always warm         │        │ • Always warm         │   │
│  └──────────┬────────────┘        └───────────────────────┘   │
│             │                                                   │
│             │ Database connection                              │
│             ├─────────────────────────────────────────┐        │
│             │                                         │        │
│  ┌──────────▼──────────────────────────────────────┐ │        │
│  │   Cloud SQL (PostgreSQL 16)                    │ │        │
│  │   • Instance: db-custom-2-8192                  │ │        │
│  │   • Availability: REGIONAL (HA)                 │ │        │
│  │   • Primary + Replica in different AZs          │ │        │
│  │   • Automatic failover                          │ │        │
│  │   • Backups: Point-in-time recovery (PITR)      │ │        │
│  │   • Connection: Cloud SQL Connector             │ │        │
│  └──────────────────────────────────────────────────┘ │        │
│                                                       │        │
│  ┌──────────────────────────────────────────────────┐ │        │
│  │  Memorystore Redis (STANDARD_HA)                │ │        │
│  │  • Tier: STANDARD_HA                             │ │        │
│  │  • Memory: 1 GB (configurable)                   │ │        │
│  │  • Primary + Replica in different AZs            │ │        │
│  │  • Automatic failover (< 30 sec)                 │ │        │
│  │  • AUTH enabled                                  │ │        │
│  │  • Connection: DIRECT_PEERING                    │ │        │
│  └──────────────────────────────────────────────────┘ │        │
│                                                       │        │
│  ┌──────────────────────────────────────────────────┐ │        │
│  │  GCS Uploads Bucket                              │ │        │
│  │  • Shared storage for both staging & prod        │ │        │
│  │  • Object uploads, student files, documents      │ │        │
│  └──────────────────────────────────────────────────┘ │        │
│                                                       │        │
│  ┌──────────────────────────────────────────────────┐ │        │
│  │  Artifact Registry (Docker images)               │ │        │
│  │  • Backend image pushed by CI/CD                 │ │        │
│  │  • Frontend image pushed by CI/CD                │ │        │
│  │  • Separate repository from staging              │ │        │
│  └──────────────────────────────────────────────────┘ │        │
│                                                       │        │
│  ┌──────────────────────────────────────────────────┐ │        │
│  │  Secret Manager (credentials)                    │ │        │
│  │  • school-prod-database-url                      │ │        │
│  │  • school-prod-jwt-secret                        │ │        │
│  │  • school-prod-jwt-refresh-secret                │ │        │
│  │  • school-prod-sendgrid-api-key                  │ │        │
│  │  • school-prod-twilio-auth-token                 │ │        │
│  │  • school-prod-twilio-account-sid                │ │        │
│  └──────────────────────────────────────────────────┘ │        │
│                                                       │        │
│  ┌──────────────────────────────────────────────────┐ │        │
│  │  IAM Service Accounts                            │ │        │
│  │  • school-prod-backend (runtime)                 │ │        │
│  │  • school-prod-frontend (runtime)                │ │        │
│  │  • school-prod-be-deployer (CI/CD)               │ │        │
│  │  • school-prod-fe-deployer (CI/CD)               │ │        │
│  │                                                  │ │        │
│  │  Workload Identity Federation (WIF):             │ │        │
│  │  • GitHub OIDC provider (shared)                 │ │        │
│  │  • Each deployer SA bound to its GitHub repo     │ │        │
│  │  • No long-lived API keys                        │ │        │
│  └──────────────────────────────────────────────────┘ │        │
│                                                       │        │
│  ┌──────────────────────────────────────────────────┐ │        │
│  │  Observability                                   │ │        │
│  │  • Cloud Logging: all Cloud Run logs             │ │        │
│  │  • Cloud Monitoring: metrics, alerts             │ │        │
│  │  • Cloud Trace: distributed tracing (optional)   │ │        │
│  └──────────────────────────────────────────────────┘ │        │
│                                                       │        │
└───────────────────────────────────────────────────────┘        │
                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Component Details

### 1. Cloud Run Services (Backend & Frontend)

**Configuration:**
- Backend: 2 vCPU, 512 MB RAM (configurable via `memory` var)
- Frontend: 2 vCPU, 512 MB RAM
- **min_instances: 1** — always keep at least one container warm
- **max_instances: 2** — cap at 2 concurrent containers (tune to traffic)
- Ingress: `INGRESS_TRAFFIC_ALL` (public)
- Allow unauthenticated access

**Why Always Warm?**
- Eliminates cold start latency (~2-5 seconds for Node.js)
- Provides predictable tail latency for user-facing requests
- Cost trade-off: ~$50-75/month per service for minimum instance

**Environment Variables (Backend):**
```
NODE_ENV             = "prod"
REDIS_HOST           = <memorystore-host>
REDIS_PORT           = <memorystore-port>
GCP_BUCKET_NAME      = school-prod-uploads
GCP_PROJECT_ID       = <project-id>
FRONTEND_URL         = https://school.m-romero.dev (or *.run.app)
SENDGRID_FROM_EMAIL  = no-reply@m-romero.dev
SENDGRID_FROM_NAME   = No responder
```

### 2. Cloud SQL (PostgreSQL 16)

**Configuration:**
- **Instance Class:** `db-custom-2-8192` (2 vCPU, 8 GB RAM)
  - Capacity for ~500-1000 concurrent connections
  - Plenty of headroom for a school app (typically < 50 concurrent users)
- **Availability Type:** REGIONAL (HA)
  - Primary instance in one AZ, replica in another
  - Automatic failover triggered by health checks
  - RTO: < 5 minutes (usually < 1 minute)
  - RPO: 0 (synchronous replication)

**Backups:**
- Automated daily backups (retention: 35 days)
- Point-in-time recovery enabled
- Manual backups can be created via Cloud Console

**Database Initialization:**
- Name: `school_db`
- User: `school_app`
- Password: from `var.db_password` (required to pass at deploy time)

**Connection:**
- Via Cloud SQL Connector (internal connection from Cloud Run)
- DATABASE_URL stored in Secret Manager
- Format: `postgresql://school_app:password@localhost/school_db?host=/cloudsql/<connection-name>&schema=public`

### 3. Memorystore Redis (STANDARD_HA)

**Configuration:**
- **Tier:** STANDARD_HA (production-ready, automatic failover)
- **Memory:** 1 GB (configurable; start small, scale up if needed)
- **Redis Version:** redis_7_x
- **AUTH:** Enabled (password-protected)
- **Persistence:** RDB snapshots (not AOF)

**Failover Behavior:**
- Automatic failover to replica on primary failure
- Failover time: < 30 seconds
- Standby replica in different AZ within same region

**Usage in Backend:**
```javascript
const redis = new Redis({
  host: process.env.REDIS_HOST,
  port: parseInt(process.env.REDIS_PORT),
  // password: provided by auth_string from Memorystore
})
```

### 4. GCS Uploads Bucket

- Shared storage for both staging and production
- Bucket name: `{project-id}-school-prod-uploads`
- No versioning enabled (can be added if needed)
- All objects readable/writable by backend service account

### 5. Artifact Registry

- Repository: `school-prod` (or shared across envs)
- Images pushed by CI/CD (my-school-api and my-school-app repos)
- Pull images in Cloud Run deployments

### 6. Secret Manager

**Required Secrets (create before `terraform apply`):**
- `school-prod-database-url`: PostgreSQL connection string
- `school-prod-jwt-secret`: Symmetric key for access tokens (long random)
- `school-prod-jwt-refresh-secret`: Symmetric key for refresh tokens (long random)
- `school-prod-sendgrid-api-key`: SendGrid API key (or empty)
- `school-prod-twilio-auth-token`: Twilio token
- `school-prod-twilio-account-sid`: Twilio account ID

**Rotation Policy:**
- Rotate JWT secrets annually
- Rotate SendGrid/Twilio tokens after any suspected breach
- Update password in backend code/container, then invalidate old instances

### 7. IAM & Workload Identity Federation

**Service Accounts:**

1. **school-prod-backend** (runtime)
   - Roles: `roles/cloudsql.client`, `roles/secretmanager.secretAccessor`, `roles/storage.objectAdmin`
   - Used by: Cloud Run backend service
   - Connects to Cloud SQL via connector, reads secrets, uploads files to GCS

2. **school-prod-frontend** (runtime)
   - Roles: None (stateless, unauthenticated)
   - Used by: Cloud Run frontend service

3. **school-prod-be-deployer** (CI/CD)
   - Roles: `roles/run.developer`, `roles/artifactregistry.writer`
   - Used by: GitHub Actions (my-school-api repo)
   - Scoped to: only the backend service and AR repository

4. **school-prod-fe-deployer** (CI/CD)
   - Roles: `roles/run.developer`, `roles/artifactregistry.writer`
   - Used by: GitHub Actions (my-school-app repo)
   - Scoped to: only the frontend service and AR repository

**Workload Identity Federation (WIF):**
- OIDC provider: GitHub (one pool, shared between staging & prod)
- Each deployer SA bound to its GitHub repo (attribute filtering)
- Example: `principalSet://iam.googleapis.com/<pool-name>/attribute.repository/mromero91/my-school-api`
- No JSON keys needed; GitHub Actions authenticates via short-lived OIDC token

## Monitoring & Alerting

### Key Metrics to Monitor

1. **Database (Cloud SQL Insights)**
   - CPU utilization
   - Query latency (p50, p95, p99)
   - Replication lag (should be ~0 for sync replication)
   - Connections count
   - Disk I/O

2. **Redis (Cloud Monitoring)**
   - Memory usage % (set alert at 80%)
   - Evicted keys (should be 0; if not, increase memory)
   - Keyspace hits/misses
   - Replication lag

3. **Cloud Run**
   - Request count and latency
   - Error rate (5xx, 4xx)
   - Cold start rate (should be 0% with min_instances=1)
   - CPU and memory utilization
   - Container restart count

4. **GCS**
   - Object count and size
   - Request latency

### Recommended Alerts

- Database CPU > 80% for 5 min
- Redis memory > 80%
- Cloud Run 5xx error rate > 1% for 2 min
- Database replication lag > 10 sec
- Cloud Run cold start rate > 0 (if detected, investigate why min_instances dropped)

## Cost Breakdown (Approximate)

| Component | Size | Monthly Cost |
|-----------|------|--------------|
| Cloud SQL (db-custom-2-8192 Regional) | 2 vCPU, 8 GB RAM | $280-350 |
| Cloud SQL Backups | 35-day retention, ~10 GB | $10-20 |
| Memorystore (STANDARD_HA) | 1 GB | $70-100 |
| Cloud Run (backend + frontend) | 2 min + traffic | $150-250 |
| GCS Storage | Varies | $10-50 |
| Network Egress | Varies | $100-300 |
| **Total Estimate** | | **$620-1070** |

*Note: Prices are us-central1; other regions may differ.*

## Scaling Strategy

### When to Scale Up

1. **Database:**
   - CPU > 80%: upgrade to db-custom-4-16384
   - Disk > 80%: enable auto-resize (already enabled)
   - Connections > 400: review app connection pooling

2. **Redis:**
   - Memory > 80%: increase `redis_memory_size_gb` in terraform.tfvars
   - Evicted keys > 0: likely cache too small; scale up

3. **Cloud Run:**
   - Requests p99 latency increasing: raise `max_instances`
   - Error rate increasing: investigate app logs, then scale if needed

### How to Scale

**Database:**
```bash
# Edit terraform.tfvars:
db_instance_class = "db-custom-4-16384"

terraform plan
terraform apply
# Rolling update; no downtime with REGIONAL HA
```

**Redis:**
```bash
redis_memory_size_gb = 2

terraform plan
terraform apply
# Recreates instance; brief connectivity loss (~2 min)
```

**Cloud Run:**
```bash
# Edit main.tf module "backend_service":
max_instances = 4

terraform plan
terraform apply
# No downtime; new instances start in parallel
```

## Disaster Recovery Plan

### Backup & Restore

**Database Backup Restore:**
```bash
# List backups
gcloud sql backups list --instance=school-prod-db

# Restore to a specific point in time
gcloud sql backups restore <BACKUP_ID> \
  --backup-instance=school-prod-db \
  --target-instance=school-prod-db-restore
```

**Redis Backup:**
- Memorystore does NOT have user-facing backups
- Persistence via RDB snapshots (internal)
- If data is lost, must manually repopulate cache from database queries

**GCS Bucket Versioning:**
- Not enabled by default; consider enabling for sensitive files:
  ```bash
  gsutil versioning set on gs://project-id-school-prod-uploads
  ```

### Failover Simulation

**Test Database Failover:**
1. In Cloud SQL console, click "Failover" on primary instance
2. Monitor failover status; should complete in < 5 min
3. Verify replication lag returns to 0 and app continues to work

**Test Redis Failover:**
1. Scale down primary Redis instance memory temporarily
2. Observe failover trigger and Memorystore re-promote replica
3. Verify cache is accessible from app

**Test Cloud Run Failover:**
1. Manually stop one Cloud Run instance
2. Observe Cloud Run automatically starts replacement
3. Monitor logs for any spike in 5xx errors (should be ~0)

## Production Checklist

Before going live with production data:

- [ ] Database backups tested (restore one to staging, verify data)
- [ ] Redis failover tested manually
- [ ] Cloud Run domain mappings created (DNS CNAMEs verified)
- [ ] SSL certificates auto-renewed via Let's Encrypt (if using custom domain)
- [ ] SendGrid/Twilio credentials verified (send test email/SMS)
- [ ] Monitoring dashboards created and alerts configured
- [ ] Runbook written for on-call engineer
- [ ] Staging environment running in parallel (mirror of prod config)
- [ ] DR playbook rehearsed (database restore, failover procedures)
- [ ] Load testing performed (identify capacity limits)
- [ ] Security audit completed (IAM, secret rotation, network)

## References

- [Google Cloud SQL HA](https://cloud.google.com/sql/docs/postgres/high-availability-regional)
- [Memorystore Standard HA](https://cloud.google.com/memorystore/docs/redis/redis-ha)
- [Cloud Run Scaling](https://cloud.google.com/run/docs/configuring/min-instances)
- [Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation)
