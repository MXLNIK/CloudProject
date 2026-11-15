@echo off
setlocal EnableExtensions
chcp 65001 >nul

cd /d "%~dp0.."

docker info >nul 2>&1
if errorlevel 1 goto NO_DOCKER

docker inspect swarm-manager >nul 2>&1
if errorlevel 1 goto NO_SWARM
docker inspect --format "{{.State.Running}}" swarm-manager | find "true" >nul
if errorlevel 1 goto NO_SWARM

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

echo Вхожу в Docker Hub...
docker info 2>nul | find "Username" >nul
if not errorlevel 1 goto LOGIN_OK
if not defined DOCKERHUB_TOKEN goto LOGIN_INTERACTIVE
echo %DOCKERHUB_TOKEN%| docker login -u %DOCKERHUB_USERNAME% --password-stdin
if errorlevel 1 goto FAIL
goto LOGIN_OK
:LOGIN_INTERACTIVE
docker login
if errorlevel 1 goto FAIL
:LOGIN_OK

echo Сборка образа приложения: %IMAGE%
docker build -t "%IMAGE%" ./app
if errorlevel 1 goto FAIL

echo Сборка образа nginx: %IMAGE_NGINX%
docker build -t "%IMAGE_NGINX%" ./nginx
if errorlevel 1 goto FAIL

echo Публикация образов в Docker Hub...
docker push "%IMAGE%"
if errorlevel 1 goto FAIL
docker push "%IMAGE_NGINX%"
if errorlevel 1 goto FAIL

if not defined DOCKERHUB_TOKEN goto SKIP_M_LOGIN
echo Передаю логин Docker Hub внутрь узла swarm-manager...
echo %DOCKERHUB_TOKEN%| docker exec -i swarm-manager docker login -u %DOCKERHUB_USERNAME% --password-stdin
if errorlevel 1 goto FAIL
:SKIP_M_LOGIN

echo Копирую файлы стека внутрь swarm-manager...
docker exec swarm-manager mkdir -p /stack
docker cp docker-stack.yml swarm-manager:/stack/docker-stack.yml
if errorlevel 1 goto FAIL
docker cp db swarm-manager:/stack
if errorlevel 1 goto FAIL

echo Развёртывание стека cloudproject в кластере...
docker exec -e DOCKERHUB_USERNAME=%DOCKERHUB_USERNAME% swarm-manager docker stack deploy --with-registry-auth -c /stack/docker-stack.yml cloudproject
if errorlevel 1 goto FAIL

echo.
echo Узлы скачивают образы из Docker Hub — подождите 1-3 минуты.
echo Сервисы стека:
docker exec swarm-manager docker service ls
echo.
echo Проверка стенда:   scripts\verify.bat
echo Сайт:              http://localhost:8080
echo PgAdmin:           http://localhost:5050 — admin@cloudproject.local / admin
goto END

:NO_DOCKER
echo [ОШИБКА] Docker не запущен. Запустите Docker Desktop для Windows и повторите.
exit /b 1

:NO_SWARM
echo [ОШИБКА] Кластер не поднят. Сначала выполните: scripts\init-swarm.bat
exit /b 1

:NO_USER
echo [ОШИБКА] Логин Docker Hub не задан.
exit /b 1

:FAIL
echo [ОШИБКА] Команда завершилась с ошибкой — см. сообщение Docker выше.
exit /b 1

:END
endlocal
exit /b 0
