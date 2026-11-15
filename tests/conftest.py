import os
import sys
from pathlib import Path

import psycopg2
import pytest
import redis

ROOT = Path(__file__).resolve().parent.parent

os.environ.setdefault(
    "DATABASE_URL",
    "postgresql://cloudproject:cloudproject@localhost:5432/cloudproject",
)
os.environ.setdefault("REDIS_URL", "redis://localhost:6379/0")

sys.path.insert(0, str(ROOT / "app"))

import db


def init_schema():
    """Создать схему БД из db/init.sql (безопасно при повторном запуске)"""
    sql = (ROOT / "db" / "init.sql").read_text(encoding="utf-8")
    with psycopg2.connect(db.DATABASE_URL) as conn:
        with conn.cursor() as cur:
            cur.execute(sql)


@pytest.fixture(scope="session", autouse=True)
def prepare_database():
    """Перед всеми тестами: схема БД, чистые таблицы, чистый Redis"""
    init_schema()
    db.query("TRUNCATE tasks, projects, employees RESTART IDENTITY CASCADE")
    redis.Redis.from_url(
        os.environ["REDIS_URL"], decode_responses=True
    ).flushdb()
    yield
