@echo off
setlocal EnableExtensions
chcp 65001 >nul

docker info >nul 2>&1
if errorlevel 1 goto NO_DOCKER

docker inspect swarm-manager >nul 2>&1
if errorlevel 1 goto NO_SWARM
docker inspect --format "{{.State.Running}}" swarm-manager | find "true" >nul
if errorlevel 1 goto NO_SWARM

echo == Узлы Swarm: manager и два worker-узла ==
docker exec swarm-manager docker node ls
echo.

echo == Сервисы стека: колонка REPLICAS должна показывать x/x ==
docker exec swarm-manager docker service ls
echo.

echo == Задачи стека: колонка NODE показывает узел каждой задачи ==
docker exec swarm-manager docker stack ps cloudproject --format "table {{.Name}}\t{{.Node}}\t{{.CurrentState}}\t{{.Error}}"
echo.

echo == Доступность приложения: nginx -- app -- PostgreSQL и Redis ==
set /a TRIES=0
:WAIT_HTTP
curl -fsS -o NUL http://localhost:8080/health 2>nul
if not errorlevel 1 goto HTTP_OK
set /a TRIES=TRIES+1
if %TRIES% GEQ 60 goto HTTP_FAIL
ping -n 4 127.0.0.1 >nul
goto WAIT_HTTP

:HTTP_OK
curl -fsS http://localhost:8080/health
echo.
echo.
echo == Главная страница ==
curl -fsS http://localhost:8080/ | findstr /i "<title>"
echo.
echo Откройте в браузере: http://localhost:8080
echo.

echo == Очередь событий Redis: воркер должен её опустошать ==
call :REDIS_Q swarm-manager
call :REDIS_Q swarm-worker1
call :REDIS_Q swarm-worker2
goto END

:REDIS_Q
set NODE=%~1
set RCID=
for /f "delims=" %%R in ('docker exec %NODE% docker ps --filter name=cloudproject_redis --format "{{.ID}}" 2^>nul') do set RCID=%%R
if "%RCID%"=="" goto :EOF
echo Контейнер redis работает на узле %NODE%:
docker exec %NODE% docker exec %RCID% redis-cli llen task_events
goto :EOF

:NO_DOCKER
echo [ОШИБКА] Docker не запущен. Запустите Docker Desktop для Windows и повторите.
exit /b 1

:NO_SWARM
echo [ОШИБКА] Кластер не поднят. Сначала выполните: scripts\init-swarm.bat
exit /b 1

:HTTP_FAIL
echo [ОШИБКА] Приложение не ответило за 3 минуты.
echo Состояние сервисов: docker exec swarm-manager docker service ls
echo Логи приложения:    docker exec swarm-manager docker service logs cloudproject_app
exit /b 1

:END
endlocal
exit /b 0
