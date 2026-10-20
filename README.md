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
workflow; infrastructure, deployment, and observability are left for later
project phases.

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

The S3 and KMS provider endpoints are explicitly configured to use
`http://localhost:4566`; AWS credential/account validation is skipped and S3
path-style requests are enabled. Do not change these endpoints to real AWS
endpoints without first reviewing the configuration and its potential costs.
Destroy the local resources with
`terraform -chdir=terraform destroy` before stopping LocalStack.

## Kubernetes

The `k8s/` manifests deploy the API, PostgreSQL, and Redis in the `contracts`
namespace. PostgreSQL uses a persistent volume claim; Redis is ephemeral. The
API runs as a non-root user with a read-only root filesystem, restricted
capabilities, resource requests/limits, and HTTP health probes.

The API image is `ghcr.io/tomattyy/contracts-api:develop`. If the GHCR package
is private, create an `imagePullSecret` named `ghcr-pull-secret` in the
`contracts` namespace using a GitHub token with `read:packages`, then apply
`k8s/overlays/private-ghcr` instead of the base manifests. Never commit that
token or the database password. Confirm the `develop` image tag exists in GHCR;
registry authentication does not help if the image has not been published.

1. Confirm the active context with `kubectl config current-context` and use the
   intended cluster.
2. Create the namespace and the Kubernetes Secret. The PowerShell example
   prompts for the password without echoing it and sends the encoded Secret
   through standard input; it does not put the password in command arguments
   or manifests:

   ```powershell
   kubectl create namespace contracts --dry-run=client -o yaml | kubectl apply -f -
   $securePassword = Read-Host "Database password" -AsSecureString
   $password = [System.Net.NetworkCredential]::new("", $securePassword).Password
   $encodedPassword = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($password))
   $secret = @{
     apiVersion = "v1"
     kind = "Secret"
     metadata = @{ name = "contracts-api-secrets"; namespace = "contracts" }
     type = "Opaque"
     data = @{ DB_PASSWORD = $encodedPassword }
   } | ConvertTo-Json -Depth 4 -Compress
   $secret | kubectl apply -f -
   Remove-Variable securePassword, password, encodedPassword, secret
   ```

   For a private GHCR package, create the pull secret with a GitHub token
   scoped to `read:packages`. This PowerShell example prompts without echoing
   the token and sends the generated Secret through standard input:

   ```powershell
   $username = Read-Host "GitHub username"
   $secureToken = Read-Host "GitHub token with read:packages" -AsSecureString
   $token = [System.Net.NetworkCredential]::new("", $secureToken).Password
   $auth = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${username}:$token"))
   $dockerConfig = @{ auths = @{ "ghcr.io" = @{ auth = $auth } } } |
     ConvertTo-Json -Compress
   $encodedConfig = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($dockerConfig))
   $pullSecret = @{
     apiVersion = "v1"
     kind = "Secret"
     metadata = @{ name = "ghcr-pull-secret"; namespace = "contracts" }
     type = "kubernetes.io/dockerconfigjson"
     data = @{ ".dockerconfigjson" = $encodedConfig }
   } | ConvertTo-Json -Depth 5 -Compress
   $pullSecret | kubectl apply -f -
   Remove-Variable username, secureToken, token, auth, dockerConfig, encodedConfig, pullSecret
   ```

3. Render and validate the resources without applying them. Use
   `k8s/overlays/private-ghcr` instead of `k8s` if the GHCR package is private:

   ```powershell
   kubectl kustomize k8s
   kubectl kustomize k8s/overlays/private-ghcr
   kubectl apply --dry-run=server -k k8s
   kubectl apply --dry-run=server -k k8s/overlays/private-ghcr
   ```

4. After reviewing the rendered resources and confirming the target context,
   deploy with `kubectl apply -k k8s` (or
   `kubectl apply -k k8s/overlays/private-ghcr` for a private package).
5. Wait for the workloads with `kubectl -n contracts rollout status deployment/contracts-api`
   and access the API locally with
   `kubectl -n contracts port-forward service/contracts-api 3000:3000`.
   The metrics endpoint is then available at `http://localhost:3000/metrics`.
6. Remove the deployment with `kubectl delete -k k8s`. This also removes the
   PostgreSQL PVC and its local data. Export any data you need first.

The included HPA targets 70% CPU utilization and requires a functioning
Metrics Server. The current Docker Desktop cluster does not have the
`metrics.k8s.io` API installed, so autoscaling remains inactive until one is
configured. The API Service is ClusterIP; no Ingress controller or external
load balancer is assumed.

### Continuous deployment to Docker Desktop

The `Deploy to local Kubernetes` workflow automatically runs after the
`Container` workflow succeeds for a push to this repository's `develop` branch.
It deploys the exact immutable `sha-<commit>` image that was built and scanned;
pull requests and feature branch pushes do not trigger automatic deployment.

To manually deploy another branch or tag, open **Actions → Deploy to local
Kubernetes → Run workflow**, then enter its exact Git ref, including the prefix:
`refs/heads/<branch>` or `refs/tags/<tag>`. For example, use
`refs/heads/release/1.2` or `refs/tags/v1.2.0`. The workflow checks out that
revision, builds and scans its production image, publishes it to GHCR under its
full immutable commit SHA, and only then deploys it. Invalid refs, failed image
scans, or failed publishing stop the deployment. The workflow file must first
be merged into the repository's default branch for manual dispatch to be
available.

GitHub-hosted runners cannot access a developer's Docker Desktop cluster.
Register a Windows self-hosted GitHub Actions runner on the same machine as the
cluster and add the custom label `docker-desktop`; keep its Kubernetes context
configured as `docker-desktop`. The runner must have permission to use that
context. Do not use this runner for untrusted repositories or workflows.

Before enabling deployments, create the `contracts` namespace and the
`contracts-api-secrets` Secret as described above, ensure the automatic
`develop` image is available, and keep Docker Desktop Kubernetes running. For
manually selected refs, the workflow builds, scans, and publishes the selected
image before deployment; ensure the repository's `GITHUB_TOKEN` has write
access to the GHCR package. The workflow checks its context and required
Secrets before applying any resources. If the GHCR package is private, create the
`ghcr-pull-secret` in the namespace and set the repository Actions variable
`GHCR_PRIVATE` to `true`; otherwise leave that variable unset or set to `false`.
The workflow uses the private GHCR overlay only when this variable is `true`.

The deployment targets the GitHub Actions `development` environment. Configure
its deployment protection rules in repository settings if approval is required
before deployment. A failed image scan/build prevents deployment; a failed
rollout is reported as a failed workflow, not treated as a successful deploy.

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
route. The `Container` workflow builds and scans an image for high and critical
vulnerabilities, and uploads a CycloneDX SBOM artifact.
After the image scan passes, pushes to `develop`, `main`, and version tags
(`v*`) publish the image to GitHub Container Registry (GHCR). Pull requests and
feature branch pushes never publish. Images receive the branch or version tag
and an immutable `sha-<short-commit>` tag; pushes to `main` also update
`latest`.

For example, pull the development image with
`docker pull ghcr.io/tomattyy/contracts-api:develop`. GitHub Actions uses its
repository-scoped `GITHUB_TOKEN`; no registry credential is stored in the
repository. Configure the package visibility in GitHub Packages according to
the intended audience.

## Branch workflow

Use `develop` as the integration branch and `feature/*` for changes. Open pull
requests from feature branches into `develop`; promote validated work through a
release branch before merging it into `main`. Create `hotfix/*` branches from
`main` for urgent production fixes.
