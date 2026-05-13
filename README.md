# cicd-pipeline-demo / docker-python-app

> A single FastAPI project that fulfils **two** DevOps assignments:
>
> | # | Assignment | Key Topics |
> |---|-----------|------------|
> | 1 | Containerizing a Python Application with Best Practices | Docker, Multi-stage builds, Security |
> | 2 | Building a Complete CI/CD Pipeline with GitHub Actions | GitHub Actions, Testing, Deployment |

---

## Project Structure

```text
.
├── .github/workflows/
│   ├── ci.yml              # CI pipeline (lint + matrix test)
│   ├── docker.yml          # Docker build, push & scan
│   └── deploy.yml          # Staging / production deploy
├── config/
│   └── app.json            # Read-only config (mounted in compose)
├── scripts/
│   └── deploy.sh           # Deployment helper script
├── src/
│   └── cicd_pipeline_demo/
│       ├── __init__.py
│       └── app.py           # FastAPI application
├── tests/
│   └── test_app.py          # Pytest test suite
├── .dockerignore
├── .env.example             # Environment variable reference
├── .gitignore
├── Dockerfile               # Multi-stage (optimized, production-ready)
├── Dockerfile.basic         # Single-stage (for comparison)
├── docker-compose.yml       # Local development stack
├── pyproject.toml           # Python project metadata & dependencies
├── requirements.txt         # Production dependencies
├── requirements-dev.txt     # Dev dependencies (pytest, ruff, black)
└── README.md
```

## Application Endpoints

| Endpoint | Purpose |
|----------|---------|
| `/` | Welcome response |
| `/health` | Health check (used by Docker `HEALTHCHECK` and deployment scripts) |
| `/info` | Application metadata (environment, Python version) |

---

# Part 1 — Docker Containerization

## Task 1: Basic Dockerfile (20 pts)

### 1.1 Python Web Application

The FastAPI application lives in `src/cicd_pipeline_demo/app.py` with three
endpoints (`/`, `/health`, `/info`). Dependencies are declared in both
`pyproject.toml` (for pip editable installs) and `requirements.txt` (for
Docker).

### 1.2 Basic Dockerfile

`Dockerfile.basic` is the **initial, unoptimized** Dockerfile:

```dockerfile
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/src

WORKDIR /app

COPY . .

RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir -r requirements-dev.txt

EXPOSE 8000

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
```

Key points:
- Uses `python:3.11-slim` as base to keep the image smaller than the full
  Python image.
- `PYTHONDONTWRITEBYTECODE=1` prevents `.pyc` files.
- `PYTHONUNBUFFERED=1` ensures logs appear immediately.
- `EXPOSE 8000` documents the application port.

### 1.3 Build and Test

```bash
# Build the basic image
docker build -f Dockerfile.basic -t myapp:v1 .

# Run it
docker run -d -p 8000:8000 myapp:v1

# Test
curl http://localhost:8000/health
```

---

## Task 2: Layer Caching Optimization (20 pts)

### Problems in the Basic Dockerfile

| Issue | Impact |
|-------|--------|
| `COPY . .` before `pip install` | **Every** code change invalidates the pip-install cache → full reinstall |
| Dev dependencies installed in every image | Unnecessary packages in production |
| Single `COPY` mixes rarely-changed files with frequently-changed ones | Poor cache utilisation |

### Optimized Strategy (applied in `Dockerfile`)

| Optimization | Why it helps |
|-------------|-------------|
| **Copy dependency files first** (`requirements.txt`), then install, then copy source code | Dependency layers are cached when only source code changes |
| **Separate prod & dev dependencies** | Production image never downloads test tools |
| **Use `--no-cache-dir`** in pip install | Avoids storing pip's HTTP cache inside the image layer |
| **Order: base → deps → app code** | Least-changed layers at the top → maximum cache reuse |

Before (basic):
```dockerfile
COPY . .                          # ← invalidates everything below
RUN pip install -r requirements.txt
```

After (optimized):
```dockerfile
COPY requirements.txt .           # ← rarely changes
RUN pip install -r requirements.txt
COPY src ./src                    # ← changes often, but deps are cached
```

---

## Task 3: Multi-stage Build (25 pts)

### 3.1 Stage Design

The optimized `Dockerfile` implements **5 stages**:

```text
┌─────────────────────────────────────────────┐
│  Stage 1: base                              │
│  python:3.11-slim + env vars + WORKDIR      │
├─────────────────────────────────────────────┤
│  Stage 2: builder-prod                      │
│  venv + install production deps only        │
├─────────────────────────────────────────────┤
│  Stage 3: builder-dev                       │
│  inherits builder-prod + install dev deps   │
├──────────────────┬──────────────────────────┤
│  Stage 4:        │  Stage 5:               │
│  development     │  production (DEFAULT)   │
│  full venv +     │  prod venv only +       │
│  all source      │  src/ only +            │
│  hot-reload      │  non-root user          │
└──────────────────┴──────────────────────────┘
```

### 3.2 Image Size Comparison

> **Hướng dẫn đo kích thước**: Chạy các lệnh sau rồi điền kết quả vào bảng.

```bash
# Build cả 3 target
docker build -f Dockerfile.basic -t myapp:basic .
docker build --target development -t myapp:dev .
docker build --target production -t myapp:prod .

# Xem kích thước
docker images myapp
```

| Image | Size | Notes |
|-------|------|-------|
| `myapp:basic` (single-stage) | **319 MB** | All deps (prod + dev) + all source code |
| `myapp:dev` (development) | **334 MB** | Full venv (prod + dev deps), multi-stage |
| `myapp:prod` (production) | **269 MB** | Prod deps only, non-root user, minimal |

### 3.3 Build Specific Targets

```bash
# Development: includes pytest, ruff, black for testing & linting
docker build --target development -t myapp:dev .

# Production: minimal runtime, non-root user, no dev tools
docker build --target production -t myapp:prod .
```

---

## Task 4: Security Best Practices (25 pts)

### 4.1 Non-root User

The production stage creates and switches to a dedicated user:

```dockerfile
RUN groupadd --gid 1001 appgroup && \
    useradd --uid 1001 --gid appgroup --shell /bin/false --create-home appuser

# ... (copy files, set permissions) ...

USER appuser
```

The container runs as `appuser` (UID 1001) — never as root.

### 4.2 `.dockerignore`

The `.dockerignore` file excludes:

| Pattern | Reason |
|---------|--------|
| `.git` | Version control history — not needed in image |
| `__pycache__/`, `*.pyc` | Python cache files |
| `.venv`, `venv`, `env` | Local virtual environments |
| `tests/`, `.pytest_cache/` | Test files (excluded from prod image) |
| `docs/` | Documentation |
| `.env`, `.env.*` | Environment files with potential secrets |
| `.vscode`, `.idea` | IDE configuration |
| `.DS_Store`, `Thumbs.db` | OS metadata |

### 4.3 HEALTHCHECK

Both development and production stages include a `HEALTHCHECK`:

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1
```

Verify health status:

```bash
docker run -d --name myapp-test myapp:prod
# Wait ~15 seconds for start_period
docker inspect --format='{{.State.Health.Status}}' myapp-test
# Expected output: healthy
docker rm -f myapp-test
```

### 4.4 Vulnerability Scanning

Scan the production image with Trivy or Docker Scout:

```bash
# Option A: Trivy
trivy image myapp:prod

# Option B: Docker Scout
docker scout cves myapp:prod

# Save results to file
trivy image myapp:prod > scan-results.txt 2>&1
```

> **Hướng dẫn**: Chạy lệnh scan, chụp ảnh kết quả, lưu vào thư mục
> `screenshot/`. File `scan-results.txt` trong repo chứa kết quả scan tham
> khảo.

Mitigation strategies:
- Use `python:3.11-slim` instead of full `python:3.11` to minimize OS
  packages.
- Pin dependency versions in `requirements.txt` for reproducibility.
- Regularly rebuild images to pick up security patches in base images.
- Only install production dependencies in the production stage.

---

## Task 5: Volume and Port Configuration (10 pts)

### 5.1 Volume Configuration

| Volume | Mount | Purpose |
|--------|-------|---------|
| `app-data` (named volume) | `/app/data` | Persistent data storage (survives container restarts) |
| `./config` (bind mount) | `/app/config:ro` | Read-only configuration files |
| `.` (bind mount, dev only) | `/app` | Hot-reload source code during development |

The Dockerfile declares:

```dockerfile
VOLUME ["/app/data", "/app/config"]
```

### 5.2 Port Mapping

| Container Port | Host Port | Protocol | Purpose |
|---------------|-----------|----------|---------|
| 8000 | 8000 | TCP | FastAPI HTTP server |

### 5.3 docker-compose.yml

`docker-compose.yml` provides a complete local development setup:

```yaml
services:
  app:
    build:
      context: .
      target: development        # Use dev stage with test tools
    container_name: myapp-dev
    ports:
      - "8000:8000"
    volumes:
      - .:/app                   # Hot-reload: mount source code
      - app-data:/app/data       # Persistent data storage
      - ./config:/app/config:ro  # Read-only config mount
    environment:
      - APP_ENV=development
      - PYTHONDONTWRITEBYTECODE=1
      - PYTHONUNBUFFERED=1
      - DATA_DIR=/app/data
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
    restart: unless-stopped

volumes:
  app-data:
    driver: local
```

Run the development stack:

```bash
docker compose up -d --build
curl http://localhost:8000/health
docker compose down
```

---

# Part 2 — CI/CD Pipeline with GitHub Actions

## Task 1: Basic CI Workflow (20 pts)

### 1.1 Repository Structure

The project follows the required structure:
- Source code in `src/` directory
- Tests in `tests/` directory
- `pyproject.toml` with both production and dev dependencies

### 1.2 CI Workflow

File: `.github/workflows/ci.yml`

```yaml
name: CI Pipeline

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]
```

Triggers on push to `main`/`develop` branches, pull requests to `main`, and
manual `workflow_dispatch`.

### 1.3 Jobs and Dependencies

| Job | Purpose | Dependency |
|-----|---------|------------|
| `lint` | Runs **Ruff** (linter) and **Black** (formatter check) | None |
| `test` | Runs **pytest** with coverage reporting | `needs: lint` |

Tests **only run after linting passes** — enforced by the `needs` keyword:

```yaml
test:
  needs: lint      # ← test waits for lint to pass
```

---

## Task 2: Matrix Testing (15 pts)

### 2.1 Matrix Configuration

```yaml
strategy:
  fail-fast: false
  matrix:
    os: [ubuntu-latest, macos-latest]
    python-version: ["3.10", "3.11", "3.12"]
```

This produces **6 combinations** (2 OS × 3 Python versions):

| | Python 3.10 | Python 3.11 | Python 3.12 |
|---|:-:|:-:|:-:|
| **ubuntu-latest** | ✅ | ✅ | ✅ |
| **macos-latest** | ✅ | ✅ | ✅ |

### 2.2 `fail-fast: false`

Setting `fail-fast: false` means **all** matrix combinations run to
completion even if one fails. This is useful because:
- You can see which specific OS + Python version combinations have issues
- A failure on macOS doesn't hide a separate failure on Ubuntu

### 2.3 When to Use `exclude`

Use `exclude` when a specific combination is **unsupported or wasteful**.
Example: if a dependency doesn't support Python 3.12 on macOS:

```yaml
strategy:
  matrix:
    os: [ubuntu-latest, macos-latest]
    python-version: ["3.10", "3.11", "3.12"]
    exclude:
      - os: macos-latest
        python-version: "3.12"    # Not supported on macOS yet
```

This removes only that one combination without affecting the rest of the
matrix.

---

## Task 3: Caching and Artifacts (20 pts)

### 3.1 Dependency Caching

Caching is configured via `actions/setup-python`:

```yaml
- name: Set up Python
  uses: actions/setup-python@v5
  with:
    python-version: ${{ matrix.python-version }}
    cache: pip
    cache-dependency-path: pyproject.toml   # ← cache key
```

- Cache key is based on the **hash of `pyproject.toml`**.
- When dependencies change, the cache is invalidated automatically.
- When dependencies don't change, pip skips downloading → faster builds.

### 3.2 Uploaded Artifacts

| Artifact | Format | Content |
|----------|--------|---------|
| `coverage-{os}-py{version}` | HTML | Interactive coverage report (`htmlcov/`) |
| `junit-{os}-py{version}` | XML | JUnit test results for CI integrations |
| `coverage.xml` | XML | Machine-readable coverage for Codecov |

### 3.3 Codecov Integration

Coverage is uploaded to Codecov from a single matrix cell to avoid
duplicates:

```yaml
- name: Upload coverage to Codecov
  uses: codecov/codecov-action@v4
  if: matrix.os == 'ubuntu-latest' && matrix.python-version == '3.11'
  with:
    files: coverage.xml
    token: ${{ secrets.CODECOV_TOKEN }}
    fail_ci_if_error: false
```

Setup: Add `CODECOV_TOKEN` as a repository secret in GitHub Settings →
Secrets and variables → Actions.

### 3.4 Caching Time Measurement

> **Hướng dẫn đo thời gian cache**: Vào GitHub Actions → CI Pipeline →
> chọn 2 lần chạy (lần đầu chưa có cache, lần sau đã có cache), ghi lại
> thời gian build rồi điền vào bảng.

| Run Type | Build Time |
|----------|-----------|
| Without cache | _<!-- TODO: xem lần chạy đầu tiên trên Actions -->_ |
| With cache | _<!-- TODO: xem lần chạy thứ 2 trên Actions -->_ |

---

## Task 4: Docker Build and Push (20 pts)

### 4.1 Docker Workflow

File: `.github/workflows/docker.yml`

The workflow:
1. Builds the `production` Docker target
2. Tags images with **commit SHA** and **`latest`**
3. Pushes to **GitHub Container Registry** (`ghcr.io`)
4. Scans the image with **Trivy**

### 4.2 Registry Authentication

Uses the built-in `GITHUB_TOKEN` — no manual secret setup needed:

```yaml
- name: Log in to GHCR
  uses: docker/login-action@v3
  with:
    registry: ghcr.io
    username: ${{ github.actor }}
    password: ${{ secrets.GITHUB_TOKEN }}
```

### 4.3 Conditional Builds (Path Filters)

Builds only trigger when **relevant files change**. Documentation-only
commits are skipped:

```yaml
on:
  push:
    branches: [main, develop]
    paths:
      - "src/**"
      - "Dockerfile"
      - "pyproject.toml"
      - "requirements*.txt"
      - ".github/workflows/docker.yml"
```

Files like `README.md`, `docs/`, `screenshot/` **do not** trigger a build.

### 4.4 Image Scanning (Trivy)

The workflow scans the pushed image with Trivy:

```yaml
- name: Scan image with Trivy
  uses: aquasecurity/trivy-action@v0.36.0
  continue-on-error: true
  with:
    image-ref: ghcr.io/${{ github.repository }}:${{ github.sha }}
    format: sarif
    output: trivy-results.sarif
    severity: CRITICAL,HIGH
    exit-code: "0"
```

Scan results are uploaded as both:
- **GitHub Security tab** (SARIF format, if Code Scanning is enabled)
- **Workflow artifact** (always available for download)

---

## Task 5: Deployment Strategy (25 pts)

### 5.1 Environment-specific Deployments

File: `.github/workflows/deploy.yml`

| Environment | Trigger | Approval |
|-------------|---------|----------|
| `staging` | Push to `develop` | **Automatic** |
| `production` | Push to `main` | **Manual approval** (via GitHub environment protection) |

Both environments can also be triggered manually via `workflow_dispatch`.

### 5.2 Environment Protection Rules

Setup in GitHub → Settings → Environments:

1. Create environment `staging` — no protection rules
2. Create environment `production` — add **required reviewers**

Required secrets per environment:
- `STAGING_URL` — URL of the staging server
- `PRODUCTION_URL` — URL of the production server

### 5.3 Deployment Script (`scripts/deploy.sh`)

The script performs:

1. **Pull** the new Docker image from GHCR
2. **Replace** the running container
3. **Health check** — calls `/health` endpoint up to 10 times
4. **Report** deployment status to GitHub Actions summary

```bash
bash scripts/deploy.sh
# Required env vars: DEPLOY_ENV, IMAGE, APP_URL
```

### 5.4 Deployment Flow Diagram

```text
Code Push ──→ CI Tests ──→ Build Image ──→ Deploy Staging ──→ Manual Approval ──→ Deploy Production
   │              │             │                │                   │                    │
   │         lint + test    docker.yml       deploy.yml          GitHub              deploy.yml
   │         (ci.yml)       push to GHCR    (auto on develop)   Environment         (on main)
   │                                                            Protection
   ▼                                                            Rules
 develop ───────────────────────────────→ staging (auto)
 main ──────────────────────────────────────────────────────→ production (manual)
```

### 5.5 Deployment Status Notifications

Each deployment writes a summary to the GitHub Actions job summary:

```yaml
- name: Publish deployment summary
  if: always()
  run: |
    echo "### Production deployment" >> "$GITHUB_STEP_SUMMARY"
    echo "- Image: ghcr.io/.../${{ github.sha }}" >> "$GITHUB_STEP_SUMMARY"
    echo "- Status: ${{ steps.deploy.outputs.status }}" >> "$GITHUB_STEP_SUMMARY"
```

---

# Quick Start

## Run Locally (without Docker)

```bash
# Install dependencies
python -m pip install -e ".[dev]"

# Start the server
uvicorn cicd_pipeline_demo.app:app --host 0.0.0.0 --port 8000 --reload

# Run tests
pytest --cov=src --cov-report=html --junitxml=test-results/junit.xml
```

## Run with Docker

```bash
# Build production image
docker build --target production -t myapp:prod .

# Run production image
docker run --rm -p 8000:8000 myapp:prod

# Run development stack (with hot-reload)
docker compose up -d --build
curl http://localhost:8000/health
docker compose down
```

## Scan for Vulnerabilities

```bash
trivy image myapp:prod
# or
docker scout cves myapp:prod
```

---

# Submission Checklist

## Docker Assignment (100 pts)

- [x] Source code for Python application (`src/cicd_pipeline_demo/app.py`)
- [x] Basic Dockerfile (`Dockerfile.basic`)
- [x] Optimized multi-stage Dockerfile (`Dockerfile`)
- [x] `.dockerignore` file
- [x] `docker-compose.yml` for development
- [x] Layer caching optimization documented
- [x] Non-root user configured (`appuser`, UID 1001)
- [x] `HEALTHCHECK` instruction in Dockerfile
- [x] Volume and port configuration
- [x] Vulnerability scan completed (`scan-results.txt`)
- [ ] Screenshots of running container and scan results
- [ ] Image size comparison table filled in

## CI/CD Assignment (100 pts)

- [x] `.github/workflows/ci.yml` — CI pipeline
- [x] `.github/workflows/docker.yml` — Docker build pipeline
- [x] `.github/workflows/deploy.yml` — Deployment pipeline
- [x] CI workflow runs on push and pull requests
- [x] Matrix testing across Python 3.10, 3.11, 3.12 on Ubuntu + macOS
- [x] Dependency caching implemented
- [x] Test artifacts (coverage + JUnit) uploaded
- [x] Docker image builds and pushes to GHCR
- [x] Trivy image scanning in pipeline
- [x] Path filters for conditional Docker builds
- [x] Deployment workflow with environment protection
- [x] `deploy.sh` with health check
- [ ] Screenshots of successful workflow runs
- [ ] Screenshots of coverage reports and artifacts
- [ ] Caching time measurement table filled in
