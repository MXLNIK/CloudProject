@echo off
setlocal EnableExtensions
chcp 65001 >nul

docker info >nul 2>&1
if errorlevel 1 goto NO_DOCKER

docker inspect swarm-manager >nul 2>&1
if errorlevel 1 goto NO_SWARM
docker inspect --format "{{.State.Running}}" swarm-manager | find "true" >nul
if errorlevel 1 goto NO_SWARM

docker exec swarm-manager docker service ls --format "{{.Name}}" 2>nul | find "cloudproject_app" >nul
if errorlevel 1 goto NO_STACK

if not "%DOCKERHUB_USERNAME%"=="" goto HAVE_USER
if "%~1"=="" goto PROMPT_USER
set DOCKERHUB_USERNAME=%~1
goto HAVE_USER
:PROMPT_USER
set /p DOCKERHUB_USERNAME=Логин Docker Hub:
if "%DOCKERHUB_USERNAME%"=="" goto NO_USER
:HAVE_USER

set IMAGE=%DOCKERHUB_USERNAME%/cloudproject:latest
set IMAGE_NGINX=%DOCKERHUB_USERNAME%/cloudproject-nginx:latest

if not defined DOCKERHUB_TOKEN goto SKIP_LOGIN
echo Вхожу в Docker Hub внутри узла swarm-manager...
echo %DOCKERHUB_TOKEN%| docker exec -i swarm-manager docker login -u %DOCKERHUB_USERNAME% --password-stdin
if errorlevel 1 goto FAIL
:SKIP_LOGIN

echo Обновление сервисов: rolling update, без простоя сайта.
docker exec swarm-manager docker service update --with-registry-auth --image %IMAGE% cloudproject_app
if errorlevel 1 goto FAIL
docker exec swarm-manager docker service update --with-registry-auth --image %IMAGE% cloudproject_worker
if errorlevel 1 goto FAIL
docker exec swarm-manager docker service update --with-registry-auth --image %IMAGE_NGINX% cloudproject_nginx
if errorlevel 1 goto FAIL

echo Ожидание завершения обновления...
ping -n 26 127.0.0.1 >nul

echo.
echo Сервисы стека:
docker exec swarm-manager docker service ls
echo.
echo Задачи сервиса app:
docker exec swarm-manager docker service ps cloudproject_app
echo.

echo Проверка сайта:
set /a TRIES=0
:WAIT_HTTP
curl -fsS -o NUL http://localhost:8080/health 2>nul
if not errorlevel 1 goto HTTP_OK
set /a TRIES=TRIES+1
if %TRIES% GEQ 20 goto HTTP_FAIL
ping -n 4 127.0.0.1 >nul
goto WAIT_HTTP

:HTTP_OK
curl -fsS http://localhost:8080/health
echo.
curl -fsS http://localhost:8080/ | findstr /i "<title>"
echo.
echo ДЕПЛОЙ УСПЕШНО ЗАВЕРШЁН
goto END

:NO_DOCKER
echo [ОШИБКА] Docker не запущен. Запустите Docker Desktop для Windows и повторите.
exit /b 1

:NO_SWARM
echo [ОШИБКА] Кластер не поднят. Сначала выполните: scripts\init-swarm.bat
exit /b 1

:NO_STACK
echo [ОШИБКА] Стек cloudproject ещё не развёрнут на этой машине.
echo Выполните первичную установку: scripts\init-swarm.bat затем scripts\deploy.bat
exit /b 1

:NO_USER
echo [ОШИБКА] Логин Docker Hub не задан.
exit /b 1

:HTTP_FAIL
echo [ОШИБКА] Сайт не ответил — проверьте состояние сервисов:
echo   docker exec swarm-manager docker service ls
echo   docker exec swarm-manager docker service logs cloudproject_app
exit /b 1

:FAIL
echo [ОШИБКА] Команда завершилась с ошибкой — см. сообщение Docker выше.
exit /b 1

:END
endlocal
exit /b 0
