@echo off
setlocal EnableExtensions
chcp 65001 >nul

docker info >nul 2>&1
if errorlevel 1 goto NO_DOCKER

docker inspect swarm-manager >nul 2>&1
if not errorlevel 1 goto ALREADY

echo [1/5] Создаю сеть swarmnet для узлов кластера...
docker network inspect swarmnet >nul 2>&1
if not errorlevel 1 goto NET_OK
docker network create swarmnet
if errorlevel 1 goto FAIL
:NET_OK

echo [2/5] Запускаю три узла кластера — контейнеры docker:27-dind...
echo        swarm-manager — manager-узел кластера
echo        swarm-worker1 и swarm-worker2 — worker-узлы
docker run -d --privileged -e DOCKER_TLS_CERTDIR= --name swarm-manager --hostname swarm-manager --network swarmnet -p 8080:80 -p 5050:5050 docker:27-dind
if errorlevel 1 goto FAIL
docker run -d --privileged -e DOCKER_TLS_CERTDIR= --name swarm-worker1 --hostname swarm-worker1 --network swarmnet docker:27-dind
if errorlevel 1 goto FAIL
docker run -d --privileged -e DOCKER_TLS_CERTDIR= --name swarm-worker2 --hostname swarm-worker2 --network swarmnet docker:27-dind
if errorlevel 1 goto FAIL

echo [3/5] Жду запуска Docker-демона внутри каждого узла...
call :WAIT_DAEMON swarm-manager
call :WAIT_DAEMON swarm-worker1
call :WAIT_DAEMON swarm-worker2

echo [4/5] Инициализирую Swarm на узле swarm-manager...
for /f "delims=" %%I in ('docker inspect --format "{{.NetworkSettings.Networks.swarmnet.IPAddress}}" swarm-manager') do set MANAGER_IP=%%I
if "%MANAGER_IP%"=="" goto FAIL
docker exec swarm-manager docker swarm init --advertise-addr %MANAGER_IP%
if errorlevel 1 goto FAIL

for /f "delims=" %%T in ('docker exec swarm-manager docker swarm join-token -q worker') do set WORKER_TOKEN=%%T
if "%WORKER_TOKEN%"=="" goto FAIL

echo        Подключаю worker-узлы к кластеру...
docker exec swarm-worker1 docker swarm join --token %WORKER_TOKEN% %MANAGER_IP%:2377
if errorlevel 1 goto FAIL
docker exec swarm-worker2 docker swarm join --token %WORKER_TOKEN% %MANAGER_IP%:2377
if errorlevel 1 goto FAIL

echo [5/5] Кластер готов. Узлы Swarm:
echo.
docker exec swarm-manager docker node ls
echo.
echo Следующий шаг:  scripts\deploy.bat логин_Docker_Hub
echo Сайт после деплоя: http://localhost:8080
goto END

:WAIT_DAEMON
set NODE=%~1
set /a TRIES=0
:WAIT_LOOP
docker exec %NODE% docker info >nul 2>&1
if not errorlevel 1 goto :EOF
set /a TRIES=TRIES+1
if %TRIES% GEQ 30 goto DAEMON_FAIL
ping -n 2 127.0.0.1 >nul
goto WAIT_LOOP

:NO_DOCKER
echo [ОШИБКА] Docker не запущен. Запустите Docker Desktop для Windows и повторите.
exit /b 1

:ALREADY
echo [ОШИБКА] Контейнер swarm-manager уже существует — кластер, видимо, поднят.
echo Чтобы пересоздать его с нуля, выполните: scripts\teardown.bat
exit /b 1

:DAEMON_FAIL
echo [ОШИБКА] Docker-демон внутри узла %NODE% не запустился за 60 секунд.
exit /b 1

:FAIL
echo [ОШИБКА] Команда завершилась с ошибкой — см. сообщение Docker выше.
exit /b 1

:END
endlocal
exit /b 0
