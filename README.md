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
IaC scanning is ready for infrastructure files added in later phases; the
repository does not currently contain Terraform or Kubernetes manifests.

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
