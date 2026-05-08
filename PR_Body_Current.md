## Description
This PR addresses several critical issues affecting Windows environments and subagent reliability by following the "What happened, Why, and How fixed" structure.

**Fixes #26393**

### 1. Windows Startup Hang
- **What happened**: The CLI would hang for several minutes during startup on some Windows systems.
- **Why**: The WMI-based process scanning (\Get-CimInstance\) to detect the parent IDE was extremely slow or blocked in certain configurations.
- **How fixed**: Implemented a 5-second timeout for the PowerShell command and provided an empty map fallback too ensure the CLI remains responsive.

### 2. Zombie Processes & Persistent "Thinking" State
- **What happened**: After cancelling a request (Esc/Ctrl+C), the "Thinking" state remained, and background processes continued to run.
- **Why**: The UNIX-specific process group kill (\process.kill(-pid)\) does not work on Windows, leaving child processes (like MCP servers) alive as orphans.
- **How fixed**: Implemented physical tree-kill using \taskkill /F /T\ for Windows environments, ensuring immediate termination of all descendant processes.

### 3. Broken Slash Command Recognition
- **What happened**: Inputting \/help\ or \/quit\ would sometimes be sent to the LLM as a regular prompt instead of executing the command.
- **Why**: Trailing newlines in user input caused the \isSlashCommand\ check to fail. Furthermore, the CLI incorrectly defaulted to LLM submission when a command returned no content.
- **How fixed**: Added \.trim()\ to the command detection logic and enforced a "handled" state to block unintended LLM submissions.

### 4. Memory Bloat from Log Accumulation
- **What happened**: The CLI became progressively slower during long sessions.
- **Why**: Large volumes of console and network logs were stored indefinitely in in-memory arrays.
- **How fixed**: Implemented log externalization to \~/.gemini/logs/latest.log\ with a 500-line rolling buffer, drastically reducing memory footprint. Log flushing is now synchronous to ensure reliability.

### 5. Infinite Subagent Error Loops
- **What happened**: Subagents would sometimes continue to retry failing tools indefinitely, consuming tokens without progress.
- **Why**: The parent agent didn't receive a formal error status when a subagent tool failed, and the subagent loop lacked a failure-based exit condition.
- **How fixed**: Modified \LocalSubagentInvocation\ to return explicit error objects and added a circuit breaker to the main subagent loop (stops after 3 consecutive tool failures).

### 6. Robustness of WriteFile Tool
- **What happened**: The \write_file\ tool would occasionally report success without actually writing any content.
- **Why**: If the LLM-based "edit-corrector" phase returned an empty or malformed string, the write process was silently skipped.
- **How fixed**: Added a robust fallback mechanism that uses the original proposed content if the AI correction phase fails.

### 7. Main Agent Hang Post-Subagent Completion
- **What happened**: The main agent would sometimes hang (become unresponsive) immediately after a subagent reported completion.
- **Why**: Race conditions in the \Scheduler\ could leave the execution Promise pending indefinitely, especially when multiple tools were queued or when the UI state didn't sync correctly with the completion event.
- **How fixed**: Strengthened the \Scheduler\ with a 60-second safety timeout, a 1000-iteration loop limit, and explicit exception guards to ensure control is always returned to the main agent.

### 8. 429 Errors & Log Visibility (Addendum)
- **What happened**: Subagents would stop prematurely when hitting API rate limits (429), and execution traces would disappear from the TUI after completion.
- **Why**: 429 errors were incorrectly counted as "fatal tool failures" by the circuit breaker, and the TUI rendering logic was coercing complex log objects into plain strings.
- **How fixed**: Added a 429 error bypass to the circuit breaker logic, enabled retries for streaming API requests, and updated the rendering logic to preserve trace objects.

## Testing
- **Environment**: Windows 11
- **Validation**:
  - Confirmed startup time is now <2s.
  - Verified process tree termination via Task Manager.
  - Verified log rotation and file persistence.
  - Confirmed slash commands work reliably.
  - Verified subagent circuit breaker functionality and 429 resilience.
  - Confirmed subagent traces remain visible in TUI after completion.
  - Confirmed main agent responsiveness after complex subagent tasks.
