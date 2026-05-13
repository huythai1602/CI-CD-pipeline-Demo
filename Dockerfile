# ============================================================
# Multi-stage Dockerfile for Python FastAPI Application
# ============================================================
# Stages:
#   1. base           - Shared base with env vars
#   2. builder-prod   - Install production dependencies only
#   3. builder-dev    - Install all dependencies (prod + dev)
#   4. development    - Dev image with test/lint tools
#   5. production     - Minimal runtime image (default)
# ============================================================

# ----------------------------------------------------------
# Stage 1: Base image with shared configuration
# ----------------------------------------------------------
FROM python:3.11-slim AS base

# Prevent Python from writing .pyc files and enable unbuffered output
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/src

WORKDIR /app

# ----------------------------------------------------------
# Stage 2: Builder (prod) - install production deps only
# ----------------------------------------------------------
FROM base AS builder-prod

# Create a virtual environment for clean artifact copying
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy dependency files FIRST for optimal layer caching
# (these change less frequently than application code)
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# ----------------------------------------------------------
# Stage 3: Builder (dev) - install ALL deps (prod + dev)
# ----------------------------------------------------------
FROM builder-prod AS builder-dev

# Copy and install dev dependencies on top of prod deps
COPY requirements-dev.txt .
RUN pip install --no-cache-dir -r requirements-dev.txt

# ----------------------------------------------------------
# Stage 4: Development - includes dev tools (pytest, ruff)
# ----------------------------------------------------------
FROM base AS development

# Copy the full venv (including dev dependencies) from builder-dev
COPY --from=builder-dev /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy application code for development. Files excluded by .dockerignore
# stay out of the image; mount the project with compose for local tests.
COPY . .

EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

# Run with hot-reload for development
CMD ["uvicorn", "cicd_pipeline_demo.app:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]

# ----------------------------------------------------------
# Stage 5: Production - minimal runtime image (default)
# ----------------------------------------------------------
FROM base AS production

# Create a non-root user for security
RUN groupadd --gid 1001 appgroup && \
    useradd --uid 1001 --gid appgroup --shell /bin/false --create-home appuser

# Create data directory for persistent storage
RUN mkdir -p /app/data /app/config && \
    chown -R appuser:appgroup /app

# Copy ONLY production dependencies from builder-prod (no dev tools!)
COPY --from=builder-prod /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy ONLY the application code (no tests, docs, etc. - handled by .dockerignore)
COPY src ./src

# Define volumes for persistent data and config
VOLUME ["/app/data", "/app/config"]

# Expose port
EXPOSE 8000

# Health check for container orchestration
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

# Switch to non-root user
USER appuser

# Run the application
CMD ["uvicorn", "cicd_pipeline_demo.app:app", "--host", "0.0.0.0", "--port", "8000"]
