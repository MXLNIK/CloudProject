@echo off
setlocal EnableExtensions
chcp 65001 >nul

cd /d "%~dp0.."

docker info >nul 2>&1
if errorlevel 1 goto NO_DOCKER

echo Поднимаю тестовые PostgreSQL и Redis — одноразовые контейнеры...
docker rm -f cp-test-pg cp-test-redis >nul 2>&1
docker network create cp-testnet >nul 2>&1

docker run -d --name cp-test-pg --network cp-testnet -e POSTGRES_USER=cloudproject -e POSTGRES_PASSWORD=cloudproject -e POSTGRES_DB=cloudproject -v "%CD%\db\init.sql:/docker-entrypoint-initdb.d/init.sql:ro" postgres:16-alpine
if errorlevel 1 goto FAIL
docker run -d --name cp-test-redis --network cp-testnet redis:7-alpine
if errorlevel 1 goto FAIL

echo Жду готовности тестового PostgreSQL...
set /a TRIES=0
:WAIT_PG
docker exec cp-test-pg pg_isready -U cloudproject -d cloudproject >nul 2>&1
if not errorlevel 1 goto PG_OK
set /a TRIES=TRIES+1
if %TRIES% GEQ 30 goto PG_FAIL
ping -n 2 127.0.0.1 >nul
goto WAIT_PG

:PG_OK
echo Запускаю автотесты в контейнере python:3.12-slim...
docker run --rm --network cp-testnet -e "DATABASE_URL=postgresql://cloudproject:cloudproject@cp-test-pg:5432/cloudproject" -e "REDIS_URL=redis://cp-test-redis:6379/0" -v "%CD%:/src" -w /src python:3.12-slim sh -c "pip install -q -r app/requirements.txt pytest && pytest tests -v"
set RC=%ERRORLEVEL%

echo.
echo Убираю тестовые контейнеры...
docker rm -f cp-test-pg cp-test-redis >nul 2>&1
docker network rm cp-testnet >nul 2>&1

if not "%RC%"=="0" goto TESTS_FAIL
echo.
echo ВСЕ ТЕСТЫ ПРОЙДЕНЫ
goto END

:NO_DOCKER
echo [ОШИБКА] Docker не запущен. Запустите Docker Desktop для Windows и повторите.
exit /b 1

:PG_FAIL
echo [ОШИБКА] Тестовый PostgreSQL не поднялся за 60 секунд.
exit /b 1

:TESTS_FAIL
echo [ОШИБКА] Тесты завершились с кодом %RC% — см. вывод pytest выше.
exit /b %RC%

:FAIL
echo [ОШИБКА] Команда завершилась с ошибкой — см. сообщение Docker выше.
exit /b 1

:END
endlocal
exit /b 0
