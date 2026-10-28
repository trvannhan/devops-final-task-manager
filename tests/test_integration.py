"""Kiểm thử tích hợp với PostgreSQL thật.

Cần biến môi trường TEST_DATABASE_URL trỏ tới một database dùng riêng cho test
(bảng tasks sẽ bị xóa sạch). Trên máy cá nhân nếu không đặt biến này thì các test
được bỏ qua; trong GitHub Actions (CI=true) thiếu biến này sẽ làm test thất bại.
"""

import os
import pathlib

import psycopg
import pytest

from app.main import app

TEST_DB = os.environ.get("TEST_DATABASE_URL")
SCHEMA = (pathlib.Path(__file__).resolve().parent.parent / "schema.sql").read_text()

pytestmark = pytest.mark.skipif(
    not TEST_DB and not os.environ.get("CI"),
    reason="TEST_DATABASE_URL chưa được đặt",
)


@pytest.fixture
def client(monkeypatch):
    assert TEST_DB, "CI cần TEST_DATABASE_URL để chạy test tích hợp"
    monkeypatch.setenv("DATABASE_URL", TEST_DB)
    with psycopg.connect(TEST_DB) as conn:
        conn.execute(SCHEMA)
        conn.execute("TRUNCATE tasks RESTART IDENTITY")
    return app.test_client()


def test_health_reports_database_connected(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.get_json()["database"] == "connected"


def test_task_crud_roundtrip(client):
    created = client.post(
        "/api/tasks", json={"title": "  CI task  ", "description": "from pytest"}
    )
    assert created.status_code == 201
    task = created.get_json()
    assert task["title"] == "CI task"
    assert task["completed"] is False

    listed = client.get("/api/tasks").get_json()
    assert [t["id"] for t in listed] == [task["id"]]

    updated = client.patch(f"/api/tasks/{task['id']}", json={"completed": True})
    assert updated.status_code == 200
    assert client.get("/api/tasks").get_json()[0]["completed"] is True

    assert client.delete(f"/api/tasks/{task['id']}").status_code == 204
    assert client.get("/api/tasks").get_json() == []
    assert (
        client.patch(f"/api/tasks/{task['id']}", json={"completed": False}).status_code
        == 404
    )


def test_created_task_is_stored_in_postgresql(client):
    task = client.post("/api/tasks", json={"title": "Persisted"}).get_json()
    with psycopg.connect(TEST_DB) as conn:
        row = conn.execute(
            "SELECT title, completed FROM tasks WHERE id = %s", (task["id"],)
        ).fetchone()
    assert row == ("Persisted", False)
