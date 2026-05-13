"""Tests for the FastAPI application."""

from fastapi.testclient import TestClient

from cicd_pipeline_demo.app import app

client = TestClient(app)


def test_root():
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert data["message"] == "Welcome to CI/CD Pipeline Demo"


def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert "timestamp" in data


def test_info():
    response = client.get("/info")
    assert response.status_code == 200
    data = response.json()
    assert data["app"] == "cicd-pipeline-demo"
