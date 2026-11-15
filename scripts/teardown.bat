@echo off
setlocal EnableExtensions
chcp 65001 >nul

docker info >nul 2>&1
if errorlevel 1 goto NO_DOCKER

echo Удаляю стек cloudproject, если он развёрнут...
docker exec swarm-manager docker stack rm cloudproject >nul 2>&1
ping -n 6 127.0.0.1 >nul

echo Удаляю узлы кластера — контейнеры docker:27-dind...
docker rm -f swarm-manager swarm-worker1 swarm-worker2 >nul 2>&1

echo Удаляю сеть swarmnet...
docker network rm swarmnet >nul 2>&1

echo.
echo Кластер полностью удалён. Новое поднятие: scripts\init-swarm.bat
goto END

:NO_DOCKER
echo [ОШИБКА] Docker не запущен. Запустите Docker Desktop для Windows и повторите.
exit /b 1

:END
endlocal
exit /b 0
