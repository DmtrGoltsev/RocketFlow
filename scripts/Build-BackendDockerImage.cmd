@echo off
setlocal

for %%I in ("%~dp0..") do set "REPO_ROOT=%%~fI"

pushd "%REPO_ROOT%" >nul
if errorlevel 1 (
    echo Failed to change directory to repository root.
    exit /b 1
)

where docker >nul 2>nul
if errorlevel 1 (
    echo Docker was not found in PATH. Please install Docker and make sure the docker command is available.
    popd >nul
    exit /b 1
)

docker build -t rocketflow-backend .\backend
set "DOCKER_EXIT_CODE=%ERRORLEVEL%"

popd >nul
exit /b %DOCKER_EXIT_CODE%
