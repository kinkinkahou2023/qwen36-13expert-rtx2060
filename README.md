# Qwen3.6-35B-A3B Heretic Q4_K_M on RTX 2060 6GB — 13-expert sweet spot

Verified 2026-11-26. This is a reproducible recipe for running
`Qwen3.6-35B-A3B-uncensored-heretic-Native-MTP-Preserved-Q4_K_M.gguf` at
**13 experts/layer in VRAM** and **30-40 tok/s decode** on a 6 GB RTX 2060
with a CPU lacking AVX2 (Xeon E5-2697 v2).

## Hardware

| | |
|---|---|
| GPU | NVIDIA GeForce RTX 2060, 6144 MiB, driver 576.02 |
| CPU | Xeon E5-2697 v2 (no AVX2), 12 physical cores used for expert pool |
| RAM | 64 GiB |
| Strata | 0.2.22 Control + strata.exe 0.1.69 (qwen35moe path) |

## The winning configuration (profile JSON)

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

## Why these four arguments matter

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

## Verified engine log lines

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

## The conversation-cache limitation (important)

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
first 512, which is why the first-token latency stays high. This is an
engine limitation, not a configuration error.

## What did NOT work (avoid these)

| Change | Result |
|---|---|
| `--prefill 512` + 64K context + fp4 | 7 experts, 22 tok/s |
| `--kv fp32` + 32K | 0 experts, 19.9 tok/s |
| `--kv int8` + 32K | 11 experts, 21 tok/s |
| `--batch 2` at 64K | engine refuses: not enough VRAM for 2 slots |
| `--conversation-cache-*` / `--prompt-cache-*` flags | all ignored by q36 |

## Serving / client notes

- Server: `strata serve --profile qwen36-heretic-13exp.json --host 0.0.0.0 --port 8080`
- API base: `http://10.0.0.14:8080/v1`, model id `qwen3.6-35b-a3b-heretic-q4_k_m`
- Codex: `wire_api = "responses"`, `stream_idle_timeout_ms = 600000`,
  `model_context_window = 32768`, catalog slug must match the model id.
- Keep the model id in sync: the server refuses a request whose model is not loaded
  ("The model 'X' is not loaded; currently serving 'Y'").
- `codex_thread_titles = true` makes Codex send a short side request between turns;
  harmless for this engine, just do not expect the 512-token prefix cache to cover it.

## License / sharing

Free to use and share. If you improve the expert count or get the q36
conversation cache working, please publish your engine log lines too —
the `hybrid experts: N of 256 per layer` and `ignoring ...` lines are the
only reliable evidence of what the engine actually did.
