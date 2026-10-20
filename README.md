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
check fails the workflow; security scans, container publishing, infrastructure,
deployment, and observability are intentionally left for later project phases.

## Branch workflow

Use `develop` as the integration branch and `feature/*` for changes. Open pull
requests from feature branches into `develop`; promote validated work through a
release branch before merging it into `main`. Create `hotfix/*` branches from
`main` for urgent production fixes.
