@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
title 6GB 2060 跑 35B 大模型 - 通用 NVIDIA 安装包 (现场检测/编译)

echo.
echo  ╔══════════════════════════════════════════════════════════════╗
echo  ║  6GB NVIDIA 显卡跑 35B 大模型 ^> 50 tok/s                   ║
echo  ║  通用安装包 B：现场检测硬件 + 手动确认模型                  ║
echo  ║  适合：非 RTX2060 / 驱动较新 / AVX2 CPU / 自定义路径        ║
echo  ╚══════════════════════════════════════════════════════════════╝
echo.

echo [1/9] 检测硬件环境...
where python >nul 2>&1
if %errorlevel% neq 0 (
  echo [错误] 需要 Python 3.12: https://www.python.org/downloads/release/python-3129/
  goto :fail
)
python --version

where 7z >nul 2>&1
if %errorlevel% neq 0 (
  if exist "C:\Program Files\7-Zip\7z.exe" set "PATH=C:\Program Files\7-Zip;!PATH!"
)
if not exist "C:\Program Files\7-Zip\7z.exe" (
  echo [错误] 需要 7-Zip 解压 CUDA 安装包: https://www.7-zip.org/
  goto :fail
)

nvidia-smi --query-gpu=name,memory.total,driver_version,compute_cap --format=csv,noheader 2>nul
if %errorlevel% neq 0 (
  echo [错误] 未检测到 NVIDIA GPU / nvidia-smi 不可用。
  goto :fail
)
echo.
echo 如果你的显卡是 Turing 架构 (RTX 2060/2070/2080, GTX 16xx)，
echo 驱动版本低于 580，请务必走 CUDA 12 本地编译路线（本脚本默认）。
echo.

echo [2/9] 配置选项...
set /p "INSTALL_ROOT=安装目录 (回车用默认 C:\AI-Stack): "
if "!INSTALL_ROOT!"=="" set "INSTALL_ROOT=C:\AI-Stack"
set /p "PORT=服务端口 (回车用默认 8080): "
if "!PORT!"=="" set "PORT=8080"
set /p "API_KEY=API Key (回车用默认 sk-strata-2060-local): "
if "!API_KEY!"=="" set "API_KEY=sk-strata-2060-local"
set /p "CTX=上下文长度 (回车用默认 32768): "
if "!CTX!"=="" set "CTX=32768"

echo [3/9] 选择模型（我们验证过的配置）...
echo  [1] 使用 Heretic Q4_K_M（21.8GB，RTX2060 6GB 实测 >50 tok/s）★推荐
echo  [2] 使用 Heretic Q3_K_M（17.3GB，显存更紧张时用）
echo  [3] 使用我自己的 GGUF（高级）
choice /c 123 /n /m "请输入 1/2/3: "
set "MODEL_FILE=Qwen3.6-35B-A3B-uncensored-heretic-Native-MTP-Preserved-Q4_K_M.gguf"
if !errorlevel! equ 2 set "MODEL_FILE=Qwen3.6-35B-A3B-uncensored-heretic-Native-MTP-Preserved-Q3_K_M.gguf"
if !errorlevel! equ 3 (
  set /p "MODEL_FILE=请输入 GGUF 文件名（放在 Models 目录里）: "
)
set "MODEL_DIR=!INSTALL_ROOT!\Models"
if not exist "!MODEL_DIR!" mkdir "!MODEL_DIR!"

if not exist "!MODEL_DIR!\!MODEL_FILE!" (
  echo.
  echo  请选择模型来源：
  echo   [1] 从本机已有目录复制
  echo   [2] 自动从 HuggingFace 下载
  echo   [3] Exit - 自行放置后重跑
  choice /c 123 /n /m "请输入 1/2/3: "
  if !errorlevel! equ 1 (
    set /p "SRCDIR=请输入模型所在文件夹完整路径: "
    copy /Y "!SRCDIR!\!MODEL_FILE!" "!MODEL_DIR!\" >nul
    if !errorlevel! neq 0 ( echo [错误] 找不到模型文件 & goto :fail )
  ) else if !errorlevel! equ 2 (
    curl -L --retry 5 -C - "https://huggingface.co/llmfan46/Qwen3.6-35B-A3B-uncensored-heretic-Native-MTP-Preserved-GGUF/resolve/main/!MODEL_FILE!" -o "!MODEL_DIR!\!MODEL_FILE!"
    if !errorlevel! neq 0 ( echo [错误] 下载失败 & goto :fail )
  ) else (
    echo 请把模型放到 !MODEL_DIR! 后重新运行。
    goto :end
  )
)

echo [4/9] 下载 PolyStrata 源码...
set "POLY_DIR=!INSTALL_ROOT!\PolyStrata"
if not exist "!POLY_DIR!\setup.py" (
  curl -L "https://github.com/simplexai-labs/PolyStrata/archive/refs/heads/main.zip" -o "%TEMP%\polystrata.zip"
  if exist "!POLY_DIR!" rmdir /s /q "!POLY_DIR!"
  mkdir "!POLY_DIR!"
  7z x "%TEMP%\polystrata.zip" -o"%TEMP%\polyx" -y >nul
  xcopy /E /Y /Q "%TEMP%\polyx\PolyStrata-main\*" "!POLY_DIR!\" >nul
)
cd /d "!POLY_DIR!"
python -m pip install --quiet --disable-pip-version-check --no-warn-script-location -r requirements.txt 2>nul
python -m pip install --quiet requests

echo [5/9] 准备 CUDA 12.9 编译工具...
set "CUDA_DIR=!INSTALL_ROOT!\cuda"
if not exist "!CUDA_DIR!\nvcc\bin\nvcc.exe" (
  curl -L "https://developer.download.nvidia.com/compute/cuda/12.9.1/local_installers/cuda_12.9.1_576.57_windows.exe" -o "%TEMP%\cuda12.9.exe"
  7z x "%TEMP%\cuda12.9.exe" -o"%TEMP%\cuda_extract" -y >nul
  mkdir "!CUDA_DIR!" 2>nul
  xcopy /E /Y /Q "%TEMP%\cuda_extract\cuda_nvcc\nvcc\*" "!CUDA_DIR!\" >nul
  for %%D in (cudart cublas cccl) do (
    if exist "%TEMP%\cuda_extract\cuda_%%D" xcopy /E /Y /Q "%TEMP%\cuda_extract\cuda_%%D\*" "!CUDA_DIR!\" >nul
  )
)
set "STRATA_NVCC=!CUDA_DIR!\nvcc\bin\nvcc.exe"

echo [6/9] 检测 CPU AVX2...
powershell -NoProfile -Command "$n=(Get-CimInstance Win32_Processor).Name; if($n -match 'AVX2'){'AVX2: YES'}else{'AVX2: NO (Xeon E5 v2 等老CPU, 引擎会自动走兼容路径)'}" 2>nul

echo [7/9] 编译引擎...
python setup.py --setup --family qwen36 --custom-gguf "!MODEL_DIR!\!MODEL_FILE!" --context !CTX! --vision no --host 0.0.0.0 --api-key "!API_KEY!" --port !PORT! --yes --no-start
if %errorlevel% neq 0 (
  echo [错误] setup 失败。请检查 CUDA 工具完整性或联系 GitHub Issue。
  goto :fail
)

echo [8/9] 启动服务...
set "CONFIG=!POLY_DIR!\terminal\strata-qwen36-*.json"
for %%F in (!CONFIG!) do set "CONFIG=%%F"
(
  echo @echo off
  echo cd /d "!POLY_DIR!\terminal"
  echo python "!POLY_DIR!\terminal\serve\server.py" --engine strata --config "!CONFIG!" --port !PORT! --host 0.0.0.0
) > "!INSTALL_ROOT!\start-model.bat"
schtasks /create /tn poly_qwen36 /tr "\"!INSTALL_ROOT!\start-model.bat\"" /sc onstart /ru SYSTEM /rl HIGHEST /f >nul 2>&1
schtasks /run /tn poly_qwen36 >nul 2>&1

echo [9/9] 验证...
timeout /t 12 >nul
curl -s -H "Authorization: Bearer !API_KEY!" http://127.0.0.1:!PORT!/v1/models
echo.
echo  ╔══════════════════════════════════════════════════════════════╗
echo  ║  完成! 网页聊天: http://localhost:!PORT!/                   ║
echo  ║  API: http://localhost:!PORT!/v1   Key: !API_KEY!           ║
echo  ╚══════════════════════════════════════════════════════════════╝
goto :end

:fail
echo [安装失败] 请按上方提示处理。
:end
echo 按任意键退出...
pause >nul
endlocal
