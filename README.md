# Qwen3.6-35B-A3B Heretic Q4_K_M on RTX 2060 6GB — 13-expert sweet spot + PolyStrata conversation cache

Verified 2026-11-26. Reproducible recipe for running
`Qwen3.6-35B-A3B-uncensored-heretic-Native-MTP-Preserved-Q4_K_M.gguf` on a
6 GB RTX 2060 with a CPU lacking AVX2 (Xeon E5-2697 v2).

**Two engine paths are documented:**
1. **Legacy Strata qwen35moe path** — 13 experts/layer, 30-40 tok/s decode, but only a 512-token prefix cache (Codex first-token latency stays high).
2. **PolyStrata `strata-poly` path (NEW, recommended)** — conversation cache up to 8192 MiB, 99.99% cached on repeated 15K token prompts, 30.9x speedup, 678 tok/s prefill, 50 tok/s decode, 4-second load.


---

## 一键安装包（小白专用）★

**6GB RTX 2060 竟能跑 35B 大模型，>50 tok/s —— 二手 2060 要涨价了！**

`installer/` 目录提供两个 Windows 一键 bat：

| 包 | 适合谁 |
|---|---|
| **`installer/install-2060.bat`** ★ 推荐 | RTX 2060 6GB / 纯小白 / 照抄我们验证过的配置（最少交互） |
| `installer/install-any-nvidia.bat` | 其他 NVIDIA 卡 / 自定义端口路径模型 / 现场检测 AVX2 |

两个包都会自动：检测 GPU/驱动/Python/7z → 选择我们验证过的 **Heretic Q4_K_M**（不下载官方 23GB） → 下载 PolyStrata 源码 → 7z 组装 CUDA 12.9 → 本地编译 `strata-poly.exe` → 配置 `0.0.0.0:8080` + API key → 开机自启计划任务 → `/v1/models` 验证。

前置：Python 3.12 (`Add Python to PATH`)、7-Zip、24GB 磁盘、16GB+ 内存。
详细步骤与常见问题见 [`installer/README.md`](installer/README.md)。

---

## Part 2 (NEW): PolyStrata — the conversation-cache solution

### Why this matters

The legacy q36 path **ignores every cache-tuning flag**. With Codex sending
28K token prompts that change a token after the first 512, the first-token
latency stays 25-60 seconds. PolyStrata's `strata-poly` engine has a real
conversation cache: parked conversations are kept in RAM and resumed
without re-reading the prompt.

### Verified numbers (this hardware, 15K token Codex-style prompt)

| | cold | same prompt again |
|---|---|---|
| Time to answer | 23.4 s | **0.8 s (30.9x faster)** |
| `cached_tokens` | 0 | **15,343 / 15,344 (99.99%)** |
| Prefill | 678.7 tok/s | 42 ms total |
| Decode | 45.8 tok/s | 50.8 tok/s |

Engine log evidence:
```
strata serve: prompt 15344 tokens = 0 reused + 15344 read in 22608 ms (678.7 tok/s), 32 generated in 698 ms (45.8 tok/s), drafts accepted 22 of 26
strata serve: prompt 15344 tokens = 15343 reused + 1 read in 42 ms, 32 generated in 629 ms (50.8 tok/s), drafts accepted 22 of 26
strata-poly: conversation cache: parked 2112 tokens in 40.7 ms; parked=1 bytes=245194752 evictions=0
strata-poly: loaded in 4.1 s; 1404 of 10496 routed experts in VRAM (2.5 GiB), 17 CPU threads
```

Streaming TTFT: **0.69 s cold / 0.26 s cached** (was 25-60 s with legacy q36).

### Install (Windows, no AVX2 CPU, driver 576 — CUDA 12 engine compiled locally)

PolyStrata's setup needs a CUDA 12 toolkit to compile the engine for sm_75
(the prebuilt engine is CUDA 13 and needs driver 580+, which does NOT support
Turing sm_75). The silent CUDA installer fails without admin rights; we
assembled nvcc from the installer with 7-Zip instead:

1. Download PolyStrata from GitHub (`PolyStrata-main`), and CUDA 12.9.1
   full installer (`cuda_12.9.1_576.57_windows.exe`).
2. Extract with 7-Zip into `E:\tools\cuda_fresh`: `cuda_nvcc`, `cuda_cudart`,
   `libcublas`, `cuda_cccl` components. Assemble `cuda_nvcc\nvcc\include`
   so that `cuda_runtime.h`, `crt/host_config.h`, `crt/host_defines.h`,
   `cublas_v2.h`, `cublas.lib`, `cublasLt.lib` all resolve.
   The `nv/target` include is missing from the 7z extraction — download
   `nv/target` and `nv/detail/{__preprocessor,__target_macros}` from
   NVIDIA/cccl (`libcudacxx/include/nv/`) and place them in the include dir.
3. Copy the runtime DLLs (`cudart64_12.dll`, `cublas64_12.dll`,
   `cublasLt64_12.dll`, `nvvm64_40_0.dll`) next to `strata-poly.exe`.
4. Run setup with the existing GGUF (no 23 GB re-download):
   ```
   python setup.py --setup --family qwen36 --custom-gguf <HERETIC GGUF PATH> \
     --context 32768 --vision no --host 0.0.0.0 --api-key <KEY> --port 8081 --yes --no-start
   ```
   with `STRATA_NVCC=E:\tools\cuda_fresh\cuda_nvcc\nvcc\bin\nvcc.exe`.
   Setup compiles the engine (~few minutes) and writes a start bat.
5. Start on port 8080 with a scheduled task (so the process survives SSH/logout):
   ```
   schtasks /create /tn poly_qwen36 /tr "E:\tools\start_poly8080.bat" /sc once /st 23:59 /ru SYSTEM /rl HIGHEST /f
   schtasks /run /tn poly_qwen36
   ```

The start bat:
```bat
@echo off
cd /d "E:\tools\PolyStrata-main\terminal"
"C:\Program Files\Python312\python.exe" "E:\tools\PolyStrata-main\terminal\serve\server.py" --engine strata --config "E:\tools\PolyStrata-main\terminal\strata-qwen36-qwen3.6-35b-a3b-uncensored-heretic-native-mtp-preserved-q4_k_m.json" --port 8080 --host 0.0.0.0
```

### Serving / client notes (PolyStrata)

- API base: `http://10.0.0.14:8080/v1`, model id:
  `qwen3.6-35b-a3b-uncensored-heretic-native-mtp-preserved-q4_k_m`
- Codex: `wire_api = "responses"`, `model_context_window = 32768`,
  `model_reasoning_effort = "high"`; catalog slug must match the model id.
- The Responses API works: `POST /v1/responses` with `input`, `instructions`,
  `max_output_tokens`. Do not send `temperature` / `top_p` / `top_k`
  (disables MTP drafts).
- Note: default reasoning runs with high effort; requests that set only 32
  max tokens will spend all of them on thinking (`reasoning_tokens: 32`).
  Give Codex enough output budget for the answer.

---

## Part 1: Legacy Strata qwen35moe path (13-expert sweet spot)

### Hardware

| | |
|---|---|
| GPU | NVIDIA GeForce RTX 2060, 6144 MiB, driver 576.02 |
| CPU | Xeon E5-2697 v2 (no AVX2), 12 physical cores used for expert pool |
| RAM | 64 GiB |
| Strata | 0.2.22 Control + strata.exe 0.1.69 (qwen35moe path) |

### The winning configuration (profile JSON)

`qwen36-heretic-13exp-clean.json` only keeps the four arguments that
actually matter:

```json
{
  "exe": "D:\\AI-Engines\\Strata-0.1.69\\strata.exe",
  "args": [
    "--native",
    "D:\\AI-Models\\Qwen3.6-35B-A3B-uncensored-heretic-MTP\\Qwen3.6-35B-A3B-uncensored-heretic-Native-MTP-Preserved-Q4_K_M.gguf",
    "--max-context", "32768",
    "--prefill", "auto",
    "--mtp", "2",
    "--kv", "fp4"
  ],
  "model_name": "qwen3.6-35b-a3b-heretic-q4_k_m",
  "arch": "qwen35moe",
  "port": 8080,
  "cuda": 12,
  "gpu": 0,
  "host": "0.0.0.0",
  "reasoning_budget_tokens": 1024
}
```

Note: the full working profile also lists `--prompt-cache-spread`,
`--expert-cache 256`, `--expert-cache-per-layer`, `--spec 4`,
`--prompt-cache 12`, `--conversation-cache-mib 16384`,
`--conversation-cache-slots 16`, `--conversation-cache-min-tokens 1024`.
**All of these are ignored by the q36 path** (see engine log). They are kept
only because Control re-adds some of them; removing them changes nothing.
The four arguments above are the ones that actually matter.

### Why these four arguments matter

The q36 engine decides how many routed experts stay in VRAM from the
**KV-cache size**. Every expert not in VRAM is computed by the CPU pool.
With 18.66 GiB of experts and only 6 GB of VRAM, the KV format is the
single most important knob:

| `--kv` | KV per token / attn layer | experts in VRAM | observed decode |
|---|---|---|---|
| fp32 (default) | 4.00 KiB | **0** | 19.9 tok/s |
| fp8 / int8 | 1.02 KiB | 11 | 21.0 tok/s |
| **fp4 (rotated q4_0)** | **0.56 KiB** | **13** | **30-40 tok/s (thinking), 33 tok/s overall** |

`--max-context 32768` is the second knob: at 64K the KV and the two extra
caches leave too little VRAM, which forced a small `--prefill 512` and only
7 experts. 32K lets `--prefill auto` settle at a 512-token chunk while
still fitting 13 experts.

`--mtp 2` enables the native MTP draft layer preserved in this GGUF.
It is what pushes the thinking phase past 40 tok/s
(`drafts accepted 92 of 120` in the log). Requests that set
`temperature` / `top_p` / `top_k` disable MTP — leave them unset for speed.

### Verified engine log lines (legacy)

```
strata-q36: context 32768 cells, prompt chunk 512, MTP block loaded,
            K / V cache --kv fp4 (q4_0, rotated) (0.56 KiB per token, per attention layer),
            1.71 GiB of VRAM free
strata-q36: hybrid experts: 13 of 256 per layer in VRAM (0.95 GiB),
            all 18.66 GiB in pinned host memory
```

Measured (greedy, no sampling, 300-token request):

```
[strata] thinking: 36 of 150, 40.4 tok/s
[strata] thinking: 77 of 150, 40.6 tok/s
[strata] answering: 294 of 300, 27.9 tok/s
[strata] done: 300 tokens in 12 s (33.1 tok/s)
```

### The conversation-cache limitation of the legacy engine

The q36 path **ignores every cache-tuning flag** (`--prompt-cache`,
`--prompt-cache-every`, `--prompt-cache-tail`, `--prompt-cache-spread`,
`--conversation-cache-mib`, `--conversation-cache-slots`, `--expert-cache`,
`--spec`, ...). Engine log:

```
strata-q36: ignoring --conversation-cache-mib 16384 (not an option of this engine)
strata-q36: ignoring --prompt-cache-tail (not an option of this engine)
```

What still works is the built-in prefix cache, aligned to the 512-token
prompt chunk:

```
prompt 3229 tokens = 0 reused + 3229 read in 58901 ms  (54.8 tok/s)  # cold
prompt 3245 tokens = 512 reused + 2733 read in 24754 ms (110.4 tok/s) # +512 reused
```

An unchanged 27K-token prompt was once observed as
`26,906 tokens = 26,888 reused + 18 read`. So the cache works when the
prefix is byte-identical; Codex/OpenCode usually change a token after the
first 512, which is why the first-token latency stays high. **Solution: use
PolyStrata's strata-poly engine (Part 2).**

### What did NOT work (avoid these)

| Change | Result |
|---|---|
| `--prefill 512` + 64K context + fp4 | 7 experts, 22 tok/s |
| `--kv fp32` + 32K | 0 experts, 19.9 tok/s |
| `--kv int8` + 32K | 11 experts, 21 tok/s |
| `--batch 2` at 64K | engine refuses: not enough VRAM for 2 slots |
| `--conversation-cache-*` / `--prompt-cache-*` flags | all ignored by legacy q36 |

## License / sharing

Free to use and share. If you improve the numbers, please publish your
engine log lines too — the `hybrid experts: N of 256 per layer`,
`ignoring ...`, `reused + read` and `drafts accepted` lines are the only
reliable evidence of what the engine actually did.

---

## Part 3 (NEW): Gemma 4 26B-A4B on the same 6 GB RTX 2060

`--family gemma4` runs Gemma 4 26B-A4B on the same engine. Tested on the exact
same 6 GB RTX 2060 + Xeon E5-2697 v2 (no AVX2), 32K context, default int8 KV,
MTP draft, `STRATA_POLY_MIRROR=1`, `--vram-reserve-mib 120`:

| File | Size | Experts in VRAM | Decode | Verdict |
|---|---|---|---|---|
| **UD-Q2_K_XL** ★ | 9.8 GB | 717/3840 (1.5 GiB) | **37.6-40.3 tok/s** | recommended Gemma |
| UD-Q4_K_M | 15.8 GB | 228/3840 (0.8 GiB) | 28-31 tok/s | works, slower |

Q2 wins because the 6 GB card holds only ~5.3 GB before experts: a smaller file
leaves room for 2.5x more experts in VRAM, so fewer take the slow CPU path.
(A community report on the same RTX 2060, QAT, 555 experts, also lands at 30
tok/s — this is the hardware ceiling.)

Engine log (Q2):
```
strata-poly: the 3123 experts outside VRAM in 6.8 GiB of pinned memory
strata-poly: loaded in 4.8 s; 717 of 3840 routed experts in VRAM (1.5 GiB), 17 CPU threads
strata serve: 200 generated in 4957 ms (40.3 tok/s), drafts accepted 108 of 148
```

Setup (adds the matching 0.46 GB MTP drafter automatically):
```
python setup.py --setup --family gemma4 --custom-gguf <GGUF> \
  --context 32768 --vision no --host 0.0.0.0 --api-key <KEY> --port <PORT> --yes --no-start
```
Start bat must set `STRATA_POLY_MIRROR=1` (pinned CPU experts; without it experts
are read from mapped files, much slower). Run config args add `--vram-reserve-mib 120`.

### Three models, fixed ports, one switcher
Only one model fits in VRAM at a time, but each has a fixed port so clients
never need reconfiguring. Desktop `切换模型.bat` (server: `switch_model.bat {qwen|q2|q4}`):

| Model | Port | Decode |
|---|---|---|
| Qwen3.6 golden (recommended) | 8080 | 50.8 tok/s |
| Gemma 4 UD-Q2_K_XL | 8081 | 40 tok/s |
| Gemma 4 UD-Q4_K_M | 8082 | 30 tok/s |

### What did NOT help on this 6 GB card (measured)
`--kv q4_0` (50→27 on Qwen), `--kv int8k` (slower), `--cpu-share 0/0.5/1.0`
(flat or slower), `--vram-pool` (flat), 64K+`--kv q8_0` (19 tok/s), 8K/16K
context (no gain, breaks agent system prompts), `STRATA_FDEC/FATTN` (only help
at 118K context on 12 GB+ cards), `--calibrate` (strata-poly has no tunables),
`--cache-bias`/`--attn-requant` (not supported by gemma4). int8 KV + 32K +
MTP + pinned experts is the sweet spot.

