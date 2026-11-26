@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
title 6GB 2060 跑 35B 大模型 - 一键安装包 (RTX2060 验证配置)

echo.
echo  ╔══════════════════════════════════════════════════════════════╗
echo  ║  6GB RTX 2060 竟能跑 35B 大模型  ^> 50 tok/s               ║
echo  ║  PolyStrata 会话缓存 ^| 15K 提示词重复提问 30.9 倍加速       ║
echo  ║  一键安装包 A：RTX2060 验证配置（小白推荐）                 ║
echo  ╚══════════════════════════════════════════════════════════════╝
echo.

REM ===== 管理员检测 =====
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo [提示] 未以管理员运行，部分功能（计划任务/系统PATH）可能受限。
  echo        右键本文件 - 以管理员身份运行，可获得完整体验。
  timeout /t 3 >nul
)

REM ===== 基础配置（可改） =====
set "INSTALL_ROOT=C:\AI-Stack"
set "POLY_DIR=%INSTALL_ROOT%\PolyStrata"
set "MODEL_DIR=%INSTALL_ROOT%\Models"
set "MODEL_FILE=Qwen3.6-35B-A3B-uncensored-heretic-Native-MTP-Preserved-Q4_K_M.gguf"
set "MODEL_URL=https://huggingface.co/llmfan46/Qwen3.6-35B-A3B-uncensored-heretic-Native-MTP-Preserved-GGUF/resolve/main/Qwen3.6-35B-A3B-uncensored-heretic-Native-MTP-Preserved-Q4_K_M.gguf"
set "POLY_URL=https://github.com/simplexai-labs/PolyStrata/archive/refs/heads/main.zip"
set "CUDA_URL=https://developer.download.nvidia.com/compute/cuda/12.9.1/local_installers/cuda_12.9.1_576.57_windows.exe"
set "7Z_URL=https://www.7-zip.org/a/7z2409-x64.exe"
set "PORT=8080"
set "API_KEY=sk-strata-2060-local"
set "TASK_NAME=poly_qwen36"
set "MODEL_ID=qwen3.6-35b-a3b-uncensored-heretic-native-mtp-preserved-q4_k_m"

echo [1/8] 环境检测...
where python >nul 2>&1
if %errorlevel% neq 0 (
  echo [错误] 没有找到 Python。请先安装 Python 3.12 并勾选 Add Python to PATH。
  echo        下载地址: https://www.python.org/downloads/release/python-3129/
  echo        安装后重新双击本文件。
  goto :fail
)
python --version

where git >nul 2>&1
if %errorlevel% neq 0 (
  echo [错误] 没有找到 Git。请先安装 Git for Windows: https://git-scm.com/download/win
  goto :fail
)

where 7z >nul 2>&1
if %errorlevel% neq 0 (
  if exist "C:\Program Files\7-Zip\7z.exe" (
    set "PATH=C:\Program Files\7-Zip;!PATH!"
  ) else (
    echo [警告] 没有找到 7-Zip，CUDA 工具提取需要它。
    echo        可从 https://www.7-zip.org/ 安装，或留空由脚本下载便携版。
    choice /c YN /n /m "是否自动下载 7-Zip 便携版？[Y/N]: "
    if !errorlevel! equ 1 (
      curl -L "%7Z_URL%" -o "%TEMP%\7zip-installer.exe"
      "%TEMP%\7zip-installer.exe" /S /D="%INSTALL_ROOT%\7-Zip"
      set "PATH=%INSTALL_ROOT%\7-Zip;!PATH!"
    )
  )
)

echo [2/8] 检查 NVIDIA 显卡...
nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader > "%TEMP%\gpu_info.txt" 2>nul
if %errorlevel% neq 0 (
  echo [错误] 没有检测到 NVIDIA 显卡或驱动，nvidia-smi 不可用。
  goto :fail
)
type "%TEMP%\gpu_info.txt"

echo [3/8] 检查模型文件...
if not exist "%INSTALL_ROOT%" mkdir "%INSTALL_ROOT%"
if not exist "%MODEL_DIR%" mkdir "%MODEL_DIR%"
if exist "%MODEL_DIR%\%MODEL_FILE%" (
  echo [OK] 找到模型: %MODEL_DIR%\%MODEL_FILE%
) else (
  echo.
  echo  请选择模型来源：
  echo   [1] 从本机已有目录复制（推荐，最快）
  echo   [2] 自动从 HuggingFace 下载 21.8GB（需要耐心等待）
  echo   [3]  Exit - 自行放置模型到 %MODEL_DIR% 后重跑
  choice /c 123 /n /m "请输入 1/2/3: "
  if !errorlevel! equ 1 (
    set /p "SRCDIR=请输入模型所在文件夹完整路径: "
    if exist "!SRCDIR!\%MODEL_FILE%" (
      echo 正在复制...此过程可能需要几分钟。
      copy /Y "!SRCDIR!\%MODEL_FILE%" "%MODEL_DIR%\" >nul
      echo [OK] 复制完成。
    ) else (
      echo [错误] 路径下找不到 %MODEL_FILE%
      goto :fail
    )
  ) else if !errorlevel! equ 2 (
    echo 开始下载 21.8GB...建议使用支持断点续传的下载器。
    curl -L --retry 5 -C - "%MODEL_URL%" -o "%MODEL_DIR%\%MODEL_FILE%"
    if %errorlevel% neq 0 (
      echo [错误] 下载失败，请手动下载并放到 %MODEL_DIR%
      echo 手动下载页: https://huggingface.co/llmfan46/Qwen3.6-35B-A3B-uncensored-heretic-Native-MTP-Preserved-GGUF
      goto :fail
    )
  ) else (
    echo 请把模型放到 %MODEL_DIR% 后重新运行。
    goto :end
  )
)

echo [4/8] 下载 PolyStrata 源码...
if not exist "%POLY_DIR%\setup.py" (
  curl -L "%POLY_URL%" -o "%TEMP%\polystrata.zip"
  if %errorlevel% neq 0 ( echo [错误] 下载 PolyStrata 失败 & goto :fail )
  if exist "%POLY_DIR%" rmdir /s /q "%POLY_DIR%"
  mkdir "%POLY_DIR%"
  7z x "%TEMP%\polystrata.zip" -o"%TEMP%\polyx" -y >nul
  xcopy /E /Y /Q "%TEMP%\polyx\PolyStrata-main\*" "%POLY_DIR%\" >nul
)
cd /d "%POLY_DIR%"
python -m pip install --quiet --disable-pip-version-check --no-warn-script-location -r requirements.txt 2>nul
python -c "import requests; print('[OK] Python deps')" >nul 2>&1 || python -m pip install --quiet requests

echo [5/8] 准备 CUDA 12.9 编译工具（CUDA 13 预编译引擎不支持 2060）...
set "CUDA_DIR=%INSTALL_ROOT%\cuda"
if not exist "%CUDA_DIR%\nvcc\bin\nvcc.exe" (
  curl -L "%CUDA_URL%" -o "%TEMP%\cuda12.9.exe"
  7z x "%TEMP%\cuda12.9.exe" -o"%TEMP%\cuda_extract" -y >nul
  mkdir "%CUDA_DIR%" 2>nul
  xcopy /E /Y /Q "%TEMP%\cuda_extract\cuda_nvcc\nvcc\*" "%CUDA_DIR%\" >nul
  for %%D in (cudart cublas cccl) do (
    if exist "%TEMP%\cuda_extract\cuda_%%D" xcopy /E /Y /Q "%TEMP%\cuda_extract\cuda_%%D\*" "%CUDA_DIR%\" >nul
  )
)
set "STRATA_NVCC=%CUDA_DIR%\nvcc\bin\nvcc.exe"
if not exist "%STRATA_NVCC%" (
  echo [警告] 本机 CUDA nvcc 组装不完整，setup 可能失败。
)

echo [6/8] 生成配置并编译引擎...
set "GGUF=%MODEL_DIR%\%MODEL_FILE%"
set "API_KEY=sk-strata-2060-local"
python setup.py --setup --family qwen36 --custom-gguf "%GGUF%" --context 32768 --vision no --host 0.0.0.0 --api-key "%API_KEY%" --port %PORT% --yes --no-start
if %errorlevel% neq 0 (
  echo [错误] setup 失败。常见原因：CUDA 工具不完整 / 无 AVX2 CPU 未加参数。
  goto :fail
)

echo [7/8] 创建启动脚本和计划任务...
set "CONFIG=%POLY_DIR%\terminal\strata-qwen36-qwen3.6-35b-a3b-uncensored-heretic-native-mtp-preserved-q4_k_m.json"
if not exist "%CONFIG%" (
  for %%F in ("%POLY_DIR%\terminal\strata-qwen36-*.json") do set "CONFIG=%%F"
)
(
  echo @echo off
  echo cd /d "%POLY_DIR%\terminal"
  echo python "%POLY_DIR%\terminal\serve\server.py" --engine strata --config "!CONFIG!" --port %PORT% --host 0.0.0.0
) > "%INSTALL_ROOT%\start-2060.bat"
schtasks /create /tn "%TASK_NAME%" /tr "\"%INSTALL_ROOT%\start-2060.bat\"" /sc onstart /ru SYSTEM /rl HIGHEST /f >nul 2>&1
schtasks /run /tn "%TASK_NAME%" >nul 2>&1

echo [8/8] 验证服务...
timeout /t 12 >nul
curl -s -H "Authorization: Bearer %API_KEY%" http://127.0.0.1:%PORT%/v1/models > "%TEMP%\models.json"
if %errorlevel% neq 0 ( echo [警告] 服务尚未就绪，请检查 %INSTALL_ROOT%\start-2060.bat & goto :end )
type "%TEMP%\models.json"
echo.

echo  ╔══════════════════════════════════════════════════════════════╗
echo  ║  安装完成！                                                 ║
echo  ║  网页聊天: http://localhost:%PORT%/                          ║
echo  ║  API:      http://localhost:%PORT%/v1                        ║
echo  ║  Key:      %API_KEY%                                        ║
echo  ║  局域网:    http://你的内网IP:%PORT%/                        ║
echo  ╚══════════════════════════════════════════════════════════════╝
echo.
goto :end

:fail
echo.
echo  [安装失败] 请根据上方错误提示处理后重试。
echo  完整日志请查看安装窗口输出。
echo.

:end
echo 按任意键退出...
pause >nul
endlocal
