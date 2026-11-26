# 一键安装包说明 / One-Click Installers

# 6GB RTX 2060 竟能跑 35B 大模型 (>50 tok/s)

本目录提供两个 Windows 一键 bat 安装包，让纯小白也能把 **Qwen3.6-35B-A3B Heretic Q4_K_M** 跑起来。

## 选哪个包？

| 包 | 适合谁 | 特点 |
|---|---|---|
| **`install-2060.bat`** ★ 推荐 | RTX 2060 6GB / 纯小白 / 照抄我们验证过的配置 | 最少交互、默认 21.8GB 模型、8080 端口、固定 key、开机自启 |
| `install-any-nvidia.bat` | 其他 NVIDIA 显卡 / 想自定义路径/端口/模型 / 有 AVX2 的新CPU | 现场检测 GPU/驱动/AVX2，手动选 Q4_K_M/Q3_K_M/自定义 GGUF |

两个包都会：
- 绑定 `0.0.0.0:8080`，局域网可访问，带 API key；
- 使用 **PolyStrata `strata-poly`** 引擎，带真正的会话缓存（重复 15K 提示词 30.9x 加速）；
- 用 CUDA 12.9 本地编译（避开 CUDA 13 预编译引擎在 Turing sm_75 + driver 576 上不能跑的问题）；
- 创建开机自启计划任务，服务不受 SSH 断开影响；
- 优先使用**我们验证过的 Heretic Q4_K_M**，而不是官方 23GB 模型。

## 开始前准备（只需一次）
1. 安装 **Python 3.12**：https://www.python.org/downloads/release/python-3129/ （安装时勾选 `Add Python to PATH`）
2. 安装 **7-Zip**：https://www.7-zip.org/
3. 安装 **Git**（可选，包 A 检测但不强制）：https://git-scm.com/download/win
4. 至少 **24GB 可用磁盘空间**，**16GB+ 内存**（推荐 64GB）
5. NVIDIA 驱动 **576.02 或更高**（Turing 卡不要升级到只支持 580+ 的引擎）

## 模型文件怎么来？
脚本会引导你三选一：
1. **从本机已有目录复制**（最快）——把 `Qwen3.6-35B-A3B-uncensored-heretic-Native-MTP-Preserved-Q4_K_M.gguf` 所在文件夹路径填进去；
2. **自动从 HuggingFace 下载 21.8GB**：https://huggingface.co/llmfan46/Qwen3.6-35B-A3B-uncensored-heretic-Native-MTP-Preserved-GGUF
3. 自己下载后放到 `C:\AI-Stack\Models\` 再重跑脚本。

> 不要下载官方 23GB 模型——我们验证过、能塞进 6GB 显存且 >50 tok/s 的是上面这个 Heretic Q4_K_M。

## 安装步骤
1. 下载本目录下任意一个 `.bat` 文件（右键 → 另存为）。
2. **右键 → 以管理员身份运行**（不管理员也能装，但计划任务可能要手动建）。
3. 按屏幕提示走完 8/9 步，看到 `/v1/models` 返回 JSON 即成功。
4. 浏览器打开 `http://localhost:8080/` 聊天；局域网用 `http://你的内网IP:8080/`。
5. API base: `http://localhost:8080/v1`，模型 ID: `qwen3.6-35b-a3b-uncensored-heretic-native-mtp-preserved-q4_k_m`，Key 见安装完成提示。

## 实测数据（RTX 2060 6GB + Xeon E5-2697 v2 无 AVX2）
| 场景 | 首字延迟 | 总耗时 | cached tokens | decode |
|---|---|---|---|---|
| 15K prompt 冷启动 | 0.69s | 23.4s | 0 | 45.8 tok/s |
| 同一 prompt 再问 | 0.26s | **0.8s (30.9x)** | **15343/15344 (99.99%)** | **50.8 tok/s** |

引擎日志：`1404 of 10496 routed experts in VRAM (2.5 GiB), 17 CPU threads`，`drafts accepted 22 of 26`。

## 常见问题
- **nvidia-smi 找不到** → 重装 NVIDIA 驱动。
- **setup.py 编译失败** → 确认 CUDA 12.9 组件被 7z 完整提取；CUDA 13 预编译引擎不支持 Turing sm_75 / driver 576。
- **服务没起来** → 手动运行 `C:\AI-Stack\start-2060.bat` 看报错；检查 8080 端口是否被占用。
- **首次生成很慢** → 模型/专家权重首次载入需 4s，之后会话缓存会让重复对话飞快。
- **想关掉服务** → `schtasks /end /tn poly_qwen36`。

## 许可证
安装脚本本身 MIT，可自由分享。模型与引擎遵循各自上游许可证。
