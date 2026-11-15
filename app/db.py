import os

import psycopg2
import psycopg2.extras

DATABASE_URL = os.environ.get(
    "DATABASE_URL",
    "postgresql://cloudproject:cloudproject@postgres:5432/cloudproject",
)


def query(sql, params=None):
    """Выполнить SQL-запрос и вернуть строки-словари"""
    conn = psycopg2.connect(DATABASE_URL)
    try:
        with conn:
            with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
                cur.execute(sql, params)
                if cur.description is None:
                    return None
                return cur.fetchall()
    finally:
        conn.close()
