import json
import os
import time

import redis

import db

REDIS_URL = os.environ.get("REDIS_URL", "redis://redis:6379/0")
QUEUE_NAME = "task_events"
CACHE_TTL = 3600

STATUSES = ("новая", "в работе", "выполнена")


def recalc_and_cache(r, project_id):
    """Пересчитать статистику проекта и записать её в кэш Redis"""
    rows = db.query(
        "SELECT status, COUNT(*) AS cnt FROM tasks "
        "WHERE project_id = %s GROUP BY status",
        (project_id,),
    )
    counts = {status: 0 for status in STATUSES}
    for row in rows:
        if row["status"] in counts:
            counts[row["status"]] = row["cnt"]
    stats = {
        "total": sum(counts.values()),
        "counts": counts,
        "updated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
    }
    r.set("stats:project:%d" % project_id, json.dumps(stats), ex=CACHE_TTL)
    return stats


def main():
    r = redis.Redis.from_url(REDIS_URL, decode_responses=True)
    print("[worker] запущен: слушаю очередь", QUEUE_NAME, flush=True)
    while True:
        try:
            item = r.blpop(QUEUE_NAME, timeout=10)
        except redis.RedisError as exc:
            print("[worker] Redis недоступен, повтор через 5 c:", exc, flush=True)
            time.sleep(5)
            continue
        if item is None:
            continue
        try:
            event = json.loads(item[1])
            project_id = int(event["project_id"])
            stats = recalc_and_cache(r, project_id)
            print(
                "[worker] проект %d: всего задач %d (новая=%d, в работе=%d, выполнена=%d)"
                % (
                    project_id,
                    stats["total"],
                    stats["counts"]["новая"],
                    stats["counts"]["в работе"],
                    stats["counts"]["выполнена"],
                ),
                flush=True,
            )
        except Exception as exc:
            print("[worker] ошибка обработки события:", exc, flush=True)


if __name__ == "__main__":
    main()
