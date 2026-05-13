# cicd-pipeline-demo

FastAPI demo project for **Building a Complete CI/CD Pipeline with GitHub Actions**.
The repository includes a Python application, automated linting and tests, Docker
image publishing to GitHub Container Registry, image scanning, and environment
deployment workflows.

## Project Structure

```text
.
├── .github/workflows/
│   ├── ci.yml
│   ├── docker.yml
│   └── deploy.yml
├── scripts/
│   └── deploy.sh
├── src/
│   └── cicd_pipeline_demo/
│       ├── __init__.py
│       └── app.py
├── tests/
│   └── test_app.py
├── Dockerfile
├── docker-compose.yml
├── pyproject.toml
├── requirements.txt
├── requirements-dev.txt
└── README.md
```

## Application

| Endpoint | Purpose |
|---|---|
| `/` | Basic welcome response |
| `/health` | Health check endpoint used by Docker and deployments |
| `/info` | Application metadata |

Run locally:

```bash
python -m pip install -e ".[dev]"
uvicorn cicd_pipeline_demo.app:app --host 0.0.0.0 --port 8000 --reload
```

Run tests:

```bash
pytest --cov=src --cov-report=xml --cov-report=html --junitxml=test-results/junit.xml
```

## CI Pipeline

Workflow: `.github/workflows/ci.yml`

Triggers:

- Push to `main` or `develop`
- Pull request targeting `main`
- Manual `workflow_dispatch`

Jobs:

| Job | Purpose | Dependency |
|---|---|---|
| `lint` | Runs Ruff and Black | None |
| `test` | Runs pytest with coverage and JUnit reports | `needs: lint` |

The test job only starts after linting passes.

## Matrix Testing

The `test` job runs across this matrix:

| OS | Python versions |
|---|---|
| `ubuntu-latest` | `3.10`, `3.11`, `3.12` |
| `macos-latest` | `3.10`, `3.11`, `3.12` |

`fail-fast: false` is used so one failing environment does not cancel the rest of
the matrix. That makes failures easier to diagnose because every OS/version
combination reports its own result.

Use `exclude` when one matrix combination is unsupported or wasteful. Example:
if a package does not support Python 3.12 on macOS yet, exclude only
`os: macos-latest` with `python-version: "3.12"` instead of removing the whole
Python or OS row.

## Caching and Artifacts

Dependency caching uses `actions/setup-python` with:

```yaml
cache: pip
cache-dependency-path: pyproject.toml
```

This creates a cache key from `pyproject.toml`, so dependency caches refresh
when project dependencies change.

Uploaded artifacts:

| Artifact | Source |
|---|---|
| Coverage HTML report | `htmlcov/` |
| JUnit XML test results | `test-results/junit.xml` |
| Codecov coverage upload | `coverage.xml` |

Caching measurement:

| Run Type | Build Time |
|---|---:|
| Without cache | Record first uncached Actions run |
| With cache | Record later cached Actions run |

Codecov setup:

- Add repository secret `CODECOV_TOKEN` if required by your Codecov project.
- The workflow sets `fail_ci_if_error: false` so a Codecov outage does not fail
  the main CI checks.

## Docker Build Pipeline

Workflow: `.github/workflows/docker.yml`

Triggers:

- Push to `main` or `develop`
- Manual `workflow_dispatch`
- Path filters limit runs to source, dependency, Docker, and workflow changes

The workflow:

- Builds the `production` Docker target
- Tags images as `${{ github.sha }}` and `latest`
- Pushes images to GitHub Container Registry:
  `ghcr.io/<owner>/<repository>`
- Uses `GITHUB_TOKEN` for GHCR authentication
- Uses Docker Buildx GitHub Actions cache
- Scans the pushed image with Trivy
- Uploads Trivy SARIF results to GitHub code scanning

Required repository/package settings:

- Workflow permissions must allow package writes.
- The repository must allow GitHub Actions to read and write packages.

## Deployment Strategy

Workflow: `.github/workflows/deploy.yml`

| Environment | Trigger | Approval |
|---|---|---|
| `staging` | Push to `develop` | Automatic |
| `production` | Push to `main` | Manual approval through GitHub environment protection |

Deployment flow:

```text
Code Push -> CI Tests -> Build Image -> Deploy Staging -> Manual Approval -> Deploy Production
```

The deployment script `scripts/deploy.sh`:

- Pulls the Docker image for the commit SHA
- Replaces the running container when Docker is available
- Calls `/health` after deployment
- Writes deployment status to the GitHub Actions summary

Environment setup in GitHub:

1. Create environments named `staging` and `production`.
2. Add required reviewers to the `production` environment.
3. Add environment or repository secrets:
   - `STAGING_URL`
   - `PRODUCTION_URL`
   - `CODECOV_TOKEN` if using Codecov token authentication

## Docker Commands

Build production image:

```bash
docker build --target production -t cicd-pipeline-demo:prod .
```

Run production image:

```bash
docker run --rm -p 8000:8000 cicd-pipeline-demo:prod
```

Run development stack:

```bash
docker compose up -d --build
curl http://localhost:8000/health
docker compose down
```

Scan locally with Trivy:

```bash
trivy image cicd-pipeline-demo:prod
```

## Submission Checklist

- [x] Source code in `src/`
- [x] Tests in `tests/`
- [x] `pyproject.toml` with app and dev dependencies
- [x] `.github/workflows/ci.yml`
- [x] `.github/workflows/docker.yml`
- [x] `.github/workflows/deploy.yml`
- [x] Dependency caching configured
- [x] Coverage and JUnit artifacts configured
- [x] Docker image build and GHCR push configured
- [x] Trivy image scanning configured
- [x] Staging and production deployment workflow configured
- [ ] GitHub repository URL added to submission
- [ ] Screenshots of successful CI, Docker, and deployment workflow runs
- [ ] Screenshots of coverage reports and uploaded artifacts

