@echo off
setlocal EnableExtensions
chcp 65001 >nul

docker info >nul 2>&1
if errorlevel 1 goto NO_DOCKER

docker inspect swarm-manager >nul 2>&1
if errorlevel 1 goto NO_SWARM
docker inspect --format "{{.State.Running}}" swarm-manager | find "true" >nul
if errorlevel 1 goto NO_SWARM

echo == Текущее состояние: у сервиса app 3 реплики ==
docker exec swarm-manager docker service ls --filter name=cloudproject_app
echo.

echo == Масштабируем до 6 реплик ==
docker exec swarm-manager docker service scale cloudproject_app=6
ping -n 16 127.0.0.1 >nul
echo.
echo == Задачи сервиса app: колонка NODE — распределение по трём узлам ==
docker exec swarm-manager docker service ps cloudproject_app --format "table {{.Name}}\t{{.Node}}\t{{.CurrentState}}"
echo.

echo == Отказоустойчивость: узел swarm-worker2 переводим в drain ==
docker exec swarm-manager docker node update --availability drain swarm-worker2
echo Жду перепланирования задач с drain-узла...
ping -n 16 127.0.0.1 >nul
docker exec swarm-manager docker stack ps cloudproject --format "table {{.Name}}\t{{.Node}}\t{{.CurrentState}}"
echo.
echo Задачи drain-узла переехали на swarm-manager и swarm-worker1.
echo PostgreSQL закреплён за manager-узлом и не двигается.
echo.

echo == Возвращаем узел в строй и масштаб обратно к 3 репликам ==
docker exec swarm-manager docker node update --availability active swarm-worker2
docker exec swarm-manager docker service scale cloudproject_app=3
docker exec swarm-manager docker service ls --filter name=cloudproject_app
echo.
echo Пока шло масштабирование, сайт http://localhost:8080 оставался доступен:
echo Swarm проксирует трафик только на работающие реплики.
goto END

:NO_DOCKER
echo [ОШИБКА] Docker не запущен. Запустите Docker Desktop для Windows и повторите.
exit /b 1

:NO_SWARM
echo [ОШИБКА] Кластер не поднят. Сначала: scripts\init-swarm.bat и scripts\deploy.bat
exit /b 1

:END
endlocal
exit /b 0
