import json
import os

import redis
from flask import Flask, abort, redirect, render_template, request, url_for

import db

REDIS_URL = os.environ.get("REDIS_URL", "redis://redis:6379/0")

STATUSES = ["новая", "в работе", "выполнена"]
STATUS_COLORS = {
    "новая": "secondary",
    "в работе": "warning",
    "выполнена": "success",
}
QUEUE_NAME = "task_events"

app = Flask(__name__)
cache = redis.Redis.from_url(REDIS_URL, decode_responses=True)


def push_event(project_id):
    """Положить событие в очередь Redis, его обработает Worker"""
    try:
        cache.rpush(QUEUE_NAME, json.dumps({"project_id": project_id}))
    except redis.RedisError as exc:
        print("Не удалось положить событие в очередь Redis:", exc)


def queue_length():
    """Сколько событий ждёт в очереди (показывается на главной странице)"""
    try:
        return cache.llen(QUEUE_NAME)
    except redis.RedisError:
        return "?"


def get_stats(project_id):
    """Статистика проекта: сначала кэш Redis, при промахе из PostgreSQL"""
    key = "stats:project:%d" % project_id
    try:
        cached = cache.get(key)
    except redis.RedisError:
        cached = None
    if cached:
        stats = json.loads(cached)
        stats["from_cache"] = True
        return stats

    rows = db.query(
        "SELECT status, COUNT(*) AS cnt FROM tasks "
        "WHERE project_id = %s GROUP BY status",
        (project_id,),
    )
    counts = {status: 0 for status in STATUSES}
    for row in rows:
        if row["status"] in counts:
            counts[row["status"]] = row["cnt"]
    return {
        "total": sum(counts.values()),
        "counts": counts,
        "from_cache": False,
    }


@app.route("/")
def index():
    """Главная страница: список проектов и форма создания нового"""
    projects = db.query(
        "SELECT p.id, p.name, p.description, p.created_at, "
        "       (SELECT COUNT(*) FROM tasks t WHERE t.project_id = p.id) AS task_count "
        "FROM projects p ORDER BY p.id DESC"
    )
    return render_template("index.html", projects=projects, queue_len=queue_length())


@app.route("/project/add", methods=["POST"])
def project_add():
    """Создание проекта (форма на главной странице)"""
    name = request.form.get("name", "").strip()
    description = request.form.get("description", "").strip()
    if name:
        rows = db.query(
            "INSERT INTO projects (name, description) VALUES (%s, %s) RETURNING id",
            (name[:100], description[:500]),
        )
        return redirect(url_for("project_page", project_id=rows[0]["id"]))
    return redirect(url_for("index"))


@app.route("/project/<int:project_id>")
def project_page(project_id):
    """Страница проекта: статистика, список задач, формы"""
    rows = db.query("SELECT * FROM projects WHERE id = %s", (project_id,))
    if not rows:
        abort(404)
    tasks = db.query(
        "SELECT id, title, status, assignee_id, created_at "
        "FROM tasks WHERE project_id = %s ORDER BY id",
        (project_id,),
    )
    employees = db.query("SELECT id, full_name FROM employees ORDER BY full_name")
    return render_template(
        "project.html",
        project=rows[0],
        tasks=tasks,
        employees=employees,
        stats=get_stats(project_id),
        statuses=STATUSES,
        status_colors=STATUS_COLORS,
    )


@app.route("/project/<int:project_id>/task/add", methods=["POST"])
def task_add(project_id):
    """Добавление задачи в проект"""
    title = request.form.get("title", "").strip()
    if title:
        db.query(
            "INSERT INTO tasks (project_id, title) VALUES (%s, %s)",
            (project_id, title[:200]),
        )
        push_event(project_id)
    return redirect(url_for("project_page", project_id=project_id))


@app.route("/task/<int:task_id>/status", methods=["POST"])
def task_set_status(task_id):
    """Изменение статуса задачи (новая / в работе / выполнена)"""
    status = request.form.get("status")
    if status not in STATUSES:
        abort(400)
    rows = db.query(
        "UPDATE tasks SET status = %s WHERE id = %s RETURNING project_id",
        (status, task_id),
    )
    if not rows:
        abort(404)
    push_event(rows[0]["project_id"])
    return redirect(url_for("project_page", project_id=rows[0]["project_id"]))


@app.route("/task/<int:task_id>/assign", methods=["POST"])
def task_assign(task_id):
    """Назначение исполнителя задачи"""
    raw = request.form.get("assignee_id", "")
    assignee_id = int(raw) if raw.isdigit() else None
    rows = db.query(
        "UPDATE tasks SET assignee_id = %s WHERE id = %s RETURNING project_id",
        (assignee_id, task_id),
    )
    if not rows:
        abort(404)
    return redirect(url_for("project_page", project_id=rows[0]["project_id"]))


@app.route("/employees")
def employees_page():
    """Список сотрудников и сколько задач на них назначено"""
    rows = db.query(
        "SELECT e.id, e.full_name, e.position, COUNT(t.id) AS task_count "
        "FROM employees e LEFT JOIN tasks t ON t.assignee_id = e.id "
        "GROUP BY e.id, e.full_name, e.position ORDER BY e.full_name"
    )
    return render_template("employees.html", employees=rows)


@app.route("/employees/add", methods=["POST"])
def employee_add():
    """Добавление нового сотрудника"""
    full_name = request.form.get("full_name", "").strip()
    position = request.form.get("position", "").strip() or "сотрудник"
    if full_name:
        db.query(
            "INSERT INTO employees (full_name, position) VALUES (%s, %s)",
            (full_name[:100], position[:100]),
        )
    return redirect(url_for("employees_page"))


@app.route("/health")
def health():
    """Проверка доступности: используется Docker-ом в healthcheck"""
    db.query("SELECT 1")
    cache.ping()
    return {"status": "ok"}


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
