@echo off
chcp 65001 >nul
REM %1 = qwen | q2 | q4
set "WHICH=%1"
echo === SWITCH TO %WHICH% ===

REM stop all engine tasks
schtasks /end /tn poly_qwen36 >nul 2>&1
schtasks /end /tn gemma_q2 >nul 2>&1
schtasks /end /tn gemma_q4 >nul 2>&1
taskkill /f /im strata-poly.exe >nul 2>&1
ping -n 4 127.0.0.1 >nul

if "%WHICH%"=="qwen" (
  schtasks /run /tn poly_qwen36
  echo STARTED QWEN wait 90s
  ping -n 91 127.0.0.1 >nul
  netstat -ano | findstr ":8080" | findstr LISTENING
  goto :END
)
if "%WHICH%"=="q2" (
  schtasks /run /tn gemma_q2
  echo STARTED Q2 wait 45s
  ping -n 46 127.0.0.1 >nul
  netstat -ano | findstr ":8081" | findstr LISTENING
  goto :END
)
if "%WHICH%"=="q4" (
  schtasks /run /tn gemma_q4
  echo STARTED Q4 wait 45s
  ping -n 46 127.0.0.1 >nul
  netstat -ano | findstr ":8082" | findstr LISTENING
  goto :END
)
:END
