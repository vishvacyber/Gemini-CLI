## Problem Description
Current Gemini CLI (v0.40.1) has several critical issues specifically affecting Windows environments and general reliability:

1. **Windows Startup Hang**: Startup takes several minutes due to slow WMI process scanning.
2. **Zombie Processes**: Cancellation (Esc/Ctrl+C) fails to kill child processes on Windows, leaving "Thinking" state active.
3. **Slash Command Recognition**: Input with trailing newlines is not recognized as a command and sent to the LLM.
4. **Memory Bloat**: In-memory log accumulation causes performance degradation over time.
5. **Subagent Error Loops**: Subagents retry failing tools indefinitely without a circuit breaker.
6. **WriteFile Reliability**: AI-based content correction can lead to empty files if the correction phase fails.
7. **429 Reliability Issues**: Subagents prematurely terminate due to 429 Errors being counted as tool failures.
8. **Subagent Log Visibility**: Traces/logs of subagents disappear from TUI after completion due to incorrect string coercion.
9. **Log Persistence Failure (Added 2026-05-05)**: Subagent logs are not written to `latest.log` for short-lived tasks because they stay in the 50-item memory buffer, and there is no exit hook to flush them.
10. **API Capacity Crashes (Added 2026-05-05)**: Subagents crash immediately on API-level 429 or "No capacity available" errors because the model call execution lacks an internal retry mechanism.

## Proposed Solution
A comprehensive set of fixes including:
- 5s timeout and fallback for process scanning.
- Physical process tree-kill using `taskkill` on Windows.
- String trimming for command parsing and enforced "handled" state.
- Log externalization to file with **immediate flushing (buffer limit 1)** and a **`process.on('exit')` cleanup hook**.
- Circuit breaker for subagents (stops after 3 consecutive failures), with **429 Error bypass**.
- **Integrated exponential backoff retry loop (10 attempts)** for model API calls to handle 429 and Capacity errors.
- Correct object preservation in TUI rendering for subagent traces.
- Robust fallback for `write_file` tool using original content.

## Related Pull Request
This issue is addressed in PR #26392.
