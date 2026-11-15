import json
import os

import pytest
import redis as redis_lib

import db
import worker
from app import app as flask_app

QUEUE_NAME = "task_events"


@pytest.fixture()
def client():
    """Тестовый клиент Flask (без запуска сервера)"""
    flask_app.config["TESTING"] = True
    return flask_app.test_client()


@pytest.fixture()
def r():
    """Клиент Redis из тестового окружения"""
    return redis_lib.Redis.from_url(
        os.environ["REDIS_URL"], decode_responses=True
    )


def create_project(client, name):
    """Создать проект через веб-форму, вернуть его id"""
    resp = client.post(
        "/project/add",
        data={"name": name, "description": "создано автотестом"},
    )
    assert resp.status_code == 302
    # redirect ведёт на страницу /project/<id>
    return int(resp.headers["Location"].rsplit("/", 1)[-1])


def add_task(client, project_id, title):
    """Добавить задачу через веб-форму, вернуть её id"""
    client.post(
        f"/project/{project_id}/task/add", data={"title": title}
    )
    rows = db.query(
        "SELECT id FROM tasks WHERE project_id = %s AND title = %s",
        (project_id, title),
    )
    return rows[0]["id"]


def test_health(client):
    """/health должен вернуть ok"""
    resp = client.get("/health")
    assert resp.status_code == 200
    assert json.loads(resp.data)["status"] == "ok"


def test_index_and_create_project(client):
    """Создание проекта через форму, он появляется в списке"""
    pid = create_project(client, "Тестовый проект А")
    assert pid > 0

    resp = client.get("/")
    text = resp.get_data(as_text=True)
    assert resp.status_code == 200
    assert "Тестовый проект А" in text
    assert "Событий в очереди Redis" in text


def test_project_page_shows_live_stats(client):
    """Страница проекта: статистика есть, кэш пуст, считается из БД"""
    pid = create_project(client, "Тестовый проект Б")
    resp = client.get(f"/project/{pid}")
    text = resp.get_data(as_text=True)
    assert resp.status_code == 200
    assert "Статистика задач" in text
    assert "посчитано из БД" in text


def test_project_not_found(client):
    """Несуществующий проект отдаёт 404"""
    resp = client.get("/project/999999")
    assert resp.status_code == 404


def test_add_task_appears_and_queues_event(client, r):
    """Задача создаётся со статусом «новая», событие попадает в очередь"""
    pid = create_project(client, "Тестовый проект В")
    tid = add_task(client, pid, "Тестовая задача №1")

    rows = db.query("SELECT status FROM tasks WHERE id = %s", (tid,))
    assert rows[0]["status"] == "новая"

    assert r.llen(QUEUE_NAME) >= 1  # событие лежит в очереди Redis

    resp = client.get(f"/project/{pid}")
    assert "Тестовая задача №1" in resp.get_data(as_text=True)


def test_change_status(client, r):
    """Смена статуса обновляет БД и кладёт событие в очередь"""
    pid = create_project(client, "Тестовый проект Г")
    tid = add_task(client, pid, "Тестовая задача №2")

    resp = client.post(f"/task/{tid}/status", data={"status": "в работе"})
    assert resp.status_code == 302

    rows = db.query("SELECT status FROM tasks WHERE id = %s", (tid,))
    assert rows[0]["status"] == "в работе"
    assert r.llen(QUEUE_NAME) >= 1

    # некорректный статус отклоняется
    resp = client.post(f"/task/{tid}/status", data={"status": "мусор"})
    assert resp.status_code == 400


def test_assign_employee(client):
    """Назначение и снятие исполнителя задачи"""
    pid = create_project(client, "Тестовый проект Д")
    tid = add_task(client, pid, "Тестовая задача №3")
    rows = db.query(
        "INSERT INTO employees (full_name) VALUES (%s) RETURNING id",
        ("Тестов Тест",),
    )
    eid = rows[0]["id"]

    resp = client.post(f"/task/{tid}/assign", data={"assignee_id": str(eid)})
    assert resp.status_code == 302
    rows = db.query("SELECT assignee_id FROM tasks WHERE id = %s", (tid,))
    assert rows[0]["assignee_id"] == eid

    # пустое значение — снять исполнителя
    resp = client.post(f"/task/{tid}/assign", data={"assignee_id": ""})
    assert resp.status_code == 302
    rows = db.query("SELECT assignee_id FROM tasks WHERE id = %s", (tid,))
    assert rows[0]["assignee_id"] is None


def test_employees_page(client):
    """Страница сотрудников показывает список и число задач"""
    db.query(
        "INSERT INTO employees (full_name, position) VALUES (%s, %s)",
        ("Сотрудников Сотрудник", "инженер"),
    )
    resp = client.get("/employees")
    text = resp.get_data(as_text=True)
    assert resp.status_code == 200
    assert "Сотрудников Сотрудник" in text


def test_worker_recalculates_and_caches(client, r):
    """Полная цепочка: событие в очереди -> Worker -> статистика в кэш
    -> страница берёт статистику из кэша Redis"""

    pid = create_project(client, "Тестовый проект Е")
    tid = add_task(client, pid, "Тестовая задача №4")
    client.post(f"/task/{tid}/status", data={"status": "выполнена"})

    seen = False
    while True:
        item = r.blpop(QUEUE_NAME, timeout=1)
        if item is None:
            break
        if json.loads(item[1])["project_id"] == pid:
            seen = True
    assert seen, "событие по проекту не попало в очередь"

    stats = worker.recalc_and_cache(r, pid)
    assert stats["counts"]["выполнена"] == 1
    assert stats["total"] == 1

    cached = json.loads(r.get("stats:project:%d" % pid))
    assert cached["counts"]["выполнена"] == 1

    resp = client.get(f"/project/{pid}")
    assert "из кэша Redis" in resp.get_data(as_text=True)
