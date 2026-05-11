# RocketFlow Production Infrastructure on Yandex Cloud

This document describes the first production-ready deployment baseline for RocketFlow backend in Yandex Cloud.

## Target Architecture

- Yandex Container Registry stores backend Docker images.
- Yandex Compute Cloud VM runs the backend through Container Optimized Image.
- Yandex Managed Service for PostgreSQL stores application data.
- GitHub Actions builds, smokes, pushes, and deploys the backend container.
- The first production topology intentionally uses one backend instance until scheduler and notification behavior is certified for horizontal scaling.
- Container Optimized Image runs containers on the host network, so the backend listens on VM port `8080`; the security group controls public access to that port.

## Why This Baseline

This is the smallest production shape that still gives us managed PostgreSQL, private database networking, immutable container deploys, and an auditable CI/CD path. Kubernetes is deferred until we need multiple backend replicas, rolling orchestration, or separate worker processes.

## Terraform Bootstrap

Install and authenticate `yc` and Terraform on the operator machine, then apply:

```bash
cd infra/yandex/prod
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

The local `terraform.tfvars` file and Terraform state contain sensitive values, including the database password. Keep state in a protected backend before more people or automation manage production.

Expected Terraform outputs:

- `registry_id`
- `backend_repository`
- `backend_instance_id`
- `backend_instance_public_ip`
- `postgresql_host_fqdn`
- `rocketflow_db_url`
- `deployer_service_account_id`

## Service Account Key

Create an authorized key for the `rocketflow-prod-github-deployer` service account after Terraform apply:

```bash
yc iam key create \
  --service-account-id "$(terraform output -raw deployer_service_account_id)" \
  --output yc-prod-github-deployer-key.json
```

Store the entire JSON document in GitHub as `YC_SERVICE_ACCOUNT_KEY_JSON`.

## GitHub Secrets

Create these GitHub environment or repository secrets:

- `YC_SERVICE_ACCOUNT_KEY_JSON`: deployer service account authorized key JSON.
- `YC_CLOUD_ID`: Yandex Cloud id.
- `YC_FOLDER_ID`: Yandex Cloud folder id.
- `YC_PROD_REGISTRY_ID`: Terraform output `registry_id`.
- `YC_PROD_BACKEND_INSTANCE_ID`: Terraform output `backend_instance_id`.
- `ROCKETFLOW_PROD_DB_URL`: Terraform output `rocketflow_db_url`.
- `ROCKETFLOW_PROD_DB_USERNAME`: Terraform variable `db_user`.
- `ROCKETFLOW_PROD_DB_PASSWORD`: Terraform variable `db_password`.
- `ROCKETFLOW_PROD_FCM_CREDENTIALS_JSON`: optional, minified Firebase service account JSON.

## GitHub Variables

Create these GitHub environment or repository variables:

- `ROCKETFLOW_PROD_ALLOWED_ORIGINS`: comma-separated explicit browser origins.
- `ROCKETFLOW_PROD_ALLOWED_ORIGIN_PATTERNS`: comma-separated pattern origins, if needed.
- `ROCKETFLOW_PROD_HEALTH_URL`: `http://<backend_public_ip>:8080/actuator/health` until HTTPS ingress is added.
- `ROCKETFLOW_PROD_NOTIFICATIONS_SCHEDULER_ENABLED`: `true` only after production notification checks pass.
- `ROCKETFLOW_PROD_NOTIFICATIONS_FCM_ENABLED`: `true` only after Firebase production credentials are configured.
- `ROCKETFLOW_PROD_FCM_PROJECT_ID`: Firebase project id when FCM is enabled.

## Deploy

Run the GitHub Actions workflow `Backend Yandex Prod Deploy`.

The workflow:

1. Runs backend tests.
2. Builds the Docker image from `backend/Dockerfile`.
3. Starts a temporary PostgreSQL container and checks `/actuator/health`.
4. Pushes the image to Yandex Container Registry.
5. Updates the backend VM container through `yc compute instance update-container`.
6. Checks the production health endpoint.

The default image tag is `sha-<short-git-sha>`. A manual `image_tag` input can override it.

## Current Gaps Before Hard Production

- Add HTTPS termination through Yandex Application Load Balancer or another reverse proxy.
- Move Terraform state to a protected remote backend.
- Decide whether production SSH should stay closed or be restricted to a fixed office/VPN CIDR.
- Add database backup restore drill and document RPO/RTO.
- Certify scheduler and notification behavior before enabling more than one backend instance.
