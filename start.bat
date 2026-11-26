@echo off
REM Qwen3.6 13-expert profile - start the Strata server with the tuned config.
REM Adjust the paths below to match your installation.

set PROFILE=C:\Users\G\AppData\Local\Strata\launch\qwen36-heretic-13exp-clean.json
set CONTROL=D:\StrataDeploy\control

cd /d "%CONTROL%"
python -m strata_control serve --profile "%PROFILE%"
pause
