## Problem Description

Current Gemini CLI (v0.40.1) has several critical issues specifically affecting Windows environments, general reliability, and API rate limits:

1. **Windows Startup Hang**: Startup takes several minutes due to slow WMI process scanning.
2. **Zombie Processes**: Cancellation (Esc/Ctrl+C) fails to kill child processes on Windows, leaving "Thinking" state active.
3. **Slash Command Recognition**: Input with trailing newlines is not recognized as a command and sent to the LLM.
4. **Memory Bloat**: In-memory log accumulation causes performance degradation over time.
5. **Subagent Error Loops**: Subagents retry failing tools indefinitely without a circuit breaker.
6. **WriteFile Reliability**: AI-based content correction can lead to empty files if the correction phase fails.
7. **429 Reliability Issues**: Subagents prematurely terminate due to 429 Errors being counted as tool failures.
8. **Subagent Log Visibility**: Traces/logs of subagents disappear from TUI after completion due to incorrect string coercion.
9. **Log Persistence Failure**: Subagent logs are not written to `latest.log` for short-lived tasks because they stay in the memory buffer, and there is no exit hook to flush them.
10. **API Capacity Crashes**: Subagents crash immediately on API-level 429 or "No capacity available" errors because the model call execution lacks an internal retry mechanism.
11. **Premature Rate Limiting & Flash Fallback**: The model router runs a pre-flight request sending up to 20 turns of history (`HISTORY_SEARCH_WINDOW = 20`), bloating token usage and unnecessarily accelerating 429 rate limits.
12. **Broken Routing Threshold**: The default `getResolvedClassifierThreshold` is 90, causing the router to inappropriately downgrade almost all standard requests to the `flash` model instead of `pro` because routine tasks rarely score >=90.
13. **Missing POST Retries**: The `ky` network client configuration explicitly omits `POST` from `retryMethods`, disabling automatic retries for model generation endpoints when encountering standard 429 or 503 errors.

## Proposed Solution

A comprehensive set of fixes including:

- **Windows Reliability**: 5s timeout and fallback for process scanning; physical process tree-kill using `taskkill`.
- **Parsing & Logging**: String trimming for command parsing; log externalization to file with immediate flushing (buffer limit 1) and a `process.on('exit')` cleanup hook.
- **Subagent Stability**: Circuit breaker for subagents (stops after 3 consecutive failures); correct object preservation in TUI rendering; robust fallback for `write_file` tool using original content.
- **Network Resilience**: Integrated exponential backoff retry loop (10 attempts) for model API calls; add `post` to the `retryMethods` array in `ky` client options to enable automatic recovery from transient 429 errors.
- **Router Optimization**: Lower `HISTORY_SEARCH_WINDOW` from 20 to 10 and adjust the default classifier threshold from 90 to 50 for accurate `pro` model selection without excessive token usage.

## Related Pull Request

This issue is addressed in PR #26392.
