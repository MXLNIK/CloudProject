# CloudProject – корпоративная облачная система управления проектами

Курсовая работа по дисциплине "Настройка и администрирование сервисного программного обеспечения"
Тема: "Настройка и администрирование корпоративного облачного решения для управления проектами"


## Быстрый локальный запуск (Docker Compose)

Проверить систему без Swarm, команды выполняются в PowerShell:

```bat
docker compose up -d --build
```

- сайт: http://localhost:8080
- PgAdmin: http://localhost:5050 (логин `admin@cloudproject.com`, пароль `admin`)

Остановка: `docker compose down` (данные PostgreSQL сохранятся в томе `pgdata`,
полная очистка – `docker compose down -v`).

## Развёртывание в Docker Swarm из трёх узлов

```bat
scripts\init-swarm.bat
:: кластер: manager + 2 worker-узла

scripts\deploy.bat <логин_Docker_Hub>
:: сборка образов -> Docker Hub -> стек

scripts\verify.bat
:: проверка: узлы, сервисы, доступность
```

- сайт: http://localhost:8080
- PgAdmin: http://localhost:5050 (логин `admin@cloudproject.com`, пароль `admin`)

Подключение PgAdmin к базе: Add New Server, вкладка Connection:
host `postgres`, port `5432`, username `cloudproject`, password `cloudproject`.

Полная остановка и удаление стенда: `scripts\teardown.bat`. Повторное поднятие – `init-swarm.bat` и `deploy.bat`.

## CI/CD-конвейер (GitHub Actions)

При каждом `git push` в ветку `main` автоматически:

1. **Автотесты** – pytest PostgreSQL и Redis
2. **Сборка образов** – `cloudproject` (приложение) и `cloudproject-nginx` публикуются в Docker Hub с тегами `latest`
3. **Деплой** – SSH на Windows-машину с кластером и запуск `scripts\update.bat`:
   обновление трёх сервисов без простоя сайта и проверка работоспособности

### Секреты репозитория

| Имя                  | Значение                                              |
|----------------------|-------------------------------------------------------|
| `DOCKERHUB_USERNAME` | логин в Docker Hub                                    |
| `DOCKERHUB_TOKEN`    | токен доступа Docker Hub (Access Token)               |
| `SERVER_HOST`        | адрес Windows-машины с кластером                      |
| `SERVER_USER`        | имя пользователя Windows для входа по SSH            |
| `SSH_PRIVATE_KEY`    | приватный SSH-ключ, открытый лежит в authorized_keys  |
| `SERVER_PROJECT_DIR` | путь к репозиторию на машине, например C:\cloudproject |

### Подготовка Windows-машины

1. Включить OpenSSH Server – PowerShell от имени администратора:

2. Сгенерировать ключи и разрешить вход. Приватный ключ целиком – в секрет `SSH_PRIVATE_KEY`.

3. Склонировать репозиторий на машину, поднять кластер и сделать первичный
деплой. Путь к клону указать в секрете `SERVER_PROJECT_DIR`.

4. Чтобы GitHub добрался до вашей машины, она должна быть доступна из
интернета. Если машина за NAT и недоступна, этап deploy можно временно отключить
в `ci-cd.yml`, а обновление выполнять руками: `scripts\update.bat логин` –
это ровно те же команды, которые выполняет CI.

После подготовки любой `git push` обновляет систему автоматически.

## Масштабирование и отказоустойчивость

```bat
scripts\scale-demo.bat
```

Скрипт показывает масштабирование приложения 3 -> 6 реплик, задачи
распределяются по трём узлам, затем узел `swarm-worker2` переводится в `drain` – Swarm переносит его задачи
на другие узлы, после чего узел возвращается в строй. Сайт всё это время остаётся доступным.

Имитация отказа целого узла:

```bat
docker stop swarm-worker2
:: Swarm перенесёт задачи узла на manager и worker1
docker start swarm-worker2
:: узел возвращается в кластер
```