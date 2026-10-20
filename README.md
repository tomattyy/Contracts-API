# Contracts-API

REST API built with Node.js, TypeScript, and Express.

## Local validation

Use Node.js 24 and npm. Install the locked dependencies and run the same checks
used by GitHub Actions:

```sh
npm ci
npm run lint
npm run format:check
npm run typecheck
npm run build
npm test
```

## Continuous integration

The `CI` workflow runs these checks on pushes to `develop`, `main`, and
`feature/**`, and on pull requests targeting `develop` or `main`. A failing
check fails the workflow. Security scans run separately in the `Security`
workflow; container publishing, infrastructure, deployment, and observability
are left for later project phases.

The `Security` workflow runs Gitleaks secret detection, Semgrep SAST, `npm audit`
dependency scanning, and Trivy configuration/IaC scanning on the same branches
and pull requests. High and critical dependency or IaC findings fail their
respective checks. Findings are reported rather than automatically fixed.
Trivy scans Terraform and other infrastructure files for high and critical
misconfigurations.

## Terraform and LocalStack

Terraform provisions an S3 bucket in LocalStack for demonstrating IaC without
creating AWS resources or incurring cloud costs. The API does not currently use
this bucket; it is an infrastructure-learning resource. The bucket blocks
public access, enables versioning, and uses a customer-managed LocalStack KMS
key for server-side encryption. The Terraform workflow checks formatting and
validates the configuration, while the Security workflow scans it with Trivy.
CI does not run `terraform apply`.

1. Install Terraform 1.15.8 and Docker Compose.
2. Start the LocalStack service with `docker compose up -d localstack`.
3. From the repository root, set LocalStack's dummy AWS credentials in
   PowerShell:

   ```powershell
   $env:AWS_ACCESS_KEY_ID = "test"
   $env:AWS_SECRET_ACCESS_KEY = "test"
   $env:AWS_DEFAULT_REGION = "us-east-1"
   ```

4. Initialize and review the plan:

   ```powershell
   terraform -chdir=terraform init
   terraform -chdir=terraform plan
   ```

5. Apply only to the local LocalStack endpoint:

   ```powershell
   terraform -chdir=terraform apply
   ```

The provider is explicitly configured to use `http://localhost:4566`, skip AWS
credential/account validation, and use S3 path-style requests. Do not change
the endpoint to a real AWS endpoint without first reviewing the configuration
and its potential costs. Destroy the local resource with
`terraform -chdir=terraform destroy` before stopping LocalStack.

## Docker

Docker Compose starts the API with PostgreSQL and Redis for local validation.
Docker Desktop or Docker Engine with the Compose plugin is required.

1. Copy `.env.example` to `.env`. The example password is for local development
   only; replace it with a local value and never reuse it in a shared or
   production environment.
2. Build and start the services with `docker compose up --build`.
3. Check the API health at `http://localhost:3000/metrics`.
4. Stop the services with `docker compose down`. Add `-v` only if you also want
   to remove the local PostgreSQL data volume.

The production image uses separate dependency, build, and runtime stages,
installs only production dependencies in the final image, and runs as the
non-root `node` user. The container health check uses the existing `/metrics`
route. The `Container` workflow builds the image without publishing it, scans
for high and critical vulnerabilities, and uploads a CycloneDX SBOM artifact.
Registry publishing is reserved for the artifact-management phase.

## Branch workflow

Use `develop` as the integration branch and `feature/*` for changes. Open pull
requests from feature branches into `develop`; promote validated work through a
release branch before merging it into `main`. Create `hotfix/*` branches from
`main` for urgent production fixes.
