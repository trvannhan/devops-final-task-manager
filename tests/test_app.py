import os
os.environ.setdefault("DATABASE_URL", "postgresql://placeholder:placeholder@127.0.0.1:5432/placeholder")
from app.main import app

def test_home_renders():
    response=app.test_client().get("/")
    assert response.status_code==200
    assert b"Task Manager" in response.data

def test_post_rejects_blank_title():
    response=app.test_client().post("/api/tasks",json={"title":"   "})
    assert response.status_code==400

def test_patch_rejects_invalid_payload():
    response=app.test_client().patch("/api/tasks/1",json={"completed":"yes"})
    assert response.status_code==400
