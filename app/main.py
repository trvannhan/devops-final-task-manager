import os
import logging
from flask import Flask, render_template, jsonify, request
import psycopg
from psycopg.rows import dict_row

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
APP_VERSION = os.environ.get("APP_VERSION", "dev")


def db():
    url = os.environ.get("DATABASE_URL")
    if not url:
        raise RuntimeError("DATABASE_URL not configured")
    return psycopg.connect(url, row_factory=dict_row)


@app.get("/")
def home():
    return render_template("index.html")


@app.get("/health")
def health():
    try:
        with db() as conn:
            conn.execute("SELECT 1")
        return jsonify(status="ok", database="connected", version=APP_VERSION)
    except (psycopg.Error, RuntimeError):
        app.logger.exception("Database health check failed")
        return jsonify(status="error", database="unavailable", version=APP_VERSION), 503


@app.errorhandler(psycopg.OperationalError)
def database_unavailable(error):
    app.logger.error("Database unavailable: %s", error)
    return jsonify(error="Database unavailable"), 503


@app.get("/api/tasks")
def tasks():
    with db() as conn:
        result = conn.execute(
            "SELECT id,title,description,completed,created_at FROM tasks ORDER BY id DESC"
        ).fetchall()
    return jsonify([{**t, "created_at": t["created_at"].isoformat()} for t in result])


@app.post("/api/tasks")
def add_task():
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify(error="JSON object required"), 400
    title = data.get("title")
    description = data.get("description", "")
    if not isinstance(title, str) or not 1 <= len(title.strip()) <= 200:
        return jsonify(error="Title must contain 1-200 characters"), 400
    if not isinstance(description, str) or len(description) > 1000:
        return jsonify(error="Description too long"), 400
    with db() as conn:
        row = conn.execute(
            "INSERT INTO tasks (title,description) VALUES (%s,%s) RETURNING id,title,description,completed",
            (title.strip(), description.strip()),
        ).fetchone()
    app.logger.info("Created task id=%s", row["id"])
    return jsonify(row), 201


@app.patch("/api/tasks/<int:task_id>")
def edit_task(task_id):
    data = request.get_json(silent=True)
    if not isinstance(data, dict) or not isinstance(data.get("completed"), bool):
        return jsonify(error="completed must be a boolean"), 400
    with db() as conn:
        row = conn.execute(
            "UPDATE tasks SET completed=%s WHERE id=%s RETURNING id,title,completed",
            (data["completed"], task_id),
        ).fetchone()
    return (jsonify(row), 200) if row else (jsonify(error="Task not found"), 404)


@app.delete("/api/tasks/<int:task_id>")
def remove_task(task_id):
    with db() as conn:
        row = conn.execute(
            "DELETE FROM tasks WHERE id=%s RETURNING id", (task_id,)
        ).fetchone()
    return ("", 204) if row else (jsonify(error="Task not found"), 404)
