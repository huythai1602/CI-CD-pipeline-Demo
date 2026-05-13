"""Simple FastAPI application with health endpoint."""

import os
from datetime import datetime, timezone

from fastapi import FastAPI

app = FastAPI(title="CI/CD Pipeline Demo", version="1.0.0")

DATA_DIR = os.getenv("DATA_DIR", "/app/data")


@app.get("/")
async def root():
    """Root endpoint."""
    return {"message": "Welcome to CI/CD Pipeline Demo", "version": "1.0.0"}


@app.get("/health")
async def health():
    """Health check endpoint."""
    return {
        "status": "healthy",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "version": "1.0.0",
    }


@app.get("/info")
async def info():
    """Application info endpoint."""
    return {
        "app": "cicd-pipeline-demo",
        "environment": os.getenv("APP_ENV", "production"),
        "python_version": "3.11+",
    }
