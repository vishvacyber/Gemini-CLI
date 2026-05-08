## Description
This PR addresses several critical issues specifically affecting Windows users and general reliability:

1. **Process Scanning Hang**: Replaced slow WMI-based process scanning with a more efficient approach (or bypass) during startup to prevent multi-minute hangs on some Windows systems.
2. **Zombie Processes**: Implemented physical tree-kill using \	askkill\ on Windows when a request is cancelled. This ensures that background processes (e.g., MCP servers) are properly terminated and the \"Thinking\" state stops immediately.
3. **Slash Command Parsing**: Fixed an issue where trailing newlines in user input caused slash commands to be misidentified and incorrectly sent to the LLM.
4. **Log Management**: Optimized memory usage by moving log storage from in-memory arrays to an external file (\~/.gemini/logs/latest.log\) with a rolling buffer of the latest 500 entries.
5. **Subagent Reliability**: Introduced a circuit breaker mechanism that automatically stops subagents after 3 consecutive tool failures, preventing infinite error loops.
6. **WriteFile Fallback**: Improved the robustness of the \write_file\ tool by ensuring it proceeds with the original content if the LLM-based correction phase fails or returns empty results.

## Testing
- Environment: Windows 11
- Verified that startup time is reduced from minutes to seconds by bypassing/timeout of process scanning.
- Confirmed that \	askkill\ correctly cleans up the process tree on cancellation.
- Validated log rotation and external file persistence.
- Verified subagent termination upon repeated tool failures.
