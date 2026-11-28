@echo off
chcp 65001 >nul
REM %1 = qwen | q2 | q4 | groot
set "WHICH=%1"
echo === SWITCH TO %WHICH% ===

schtasks /end /tn poly_qwen36 >nul 2>&1
schtasks /end /tn gemma_q2 >nul 2>&1
schtasks /end /tn gemma_q4 >nul 2>&1
schtasks /end /tn poly_groot >nul 2>&1
taskkill /f /im strata-poly.exe >nul 2>&1
ping -n 4 127.0.0.1 >nul

if "%WHICH%"=="qwen" (
  schtasks /run /tn poly_qwen36
  echo STARTED QWEN 8080
  ping -n 91 127.0.0.1 >nul
  netstat -ano | findstr ":8080" | findstr LISTENING
  goto :END
)
if "%WHICH%"=="q2" (
  schtasks /run /tn gemma_q2
  echo STARTED Q2 8081
  ping -n 46 127.0.0.1 >nul
  netstat -ano | findstr ":8081" | findstr LISTENING
  goto :END
)
if "%WHICH%"=="q4" (
  schtasks /run /tn gemma_q4
  echo STARTED Q4 8082
  ping -n 46 127.0.0.1 >nul
  netstat -ano | findstr ":8082" | findstr LISTENING
  goto :END
)
if "%WHICH%"=="groot" (
  schtasks /run /tn poly_groot
  echo STARTED GROOT 8083
  ping -n 46 127.0.0.1 >nul
  netstat -ano | findstr ":8083" | findstr LISTENING
  goto :END
)
:END
