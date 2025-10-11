# Repository Guidelines

- Always create, update, and run tests whenever creating, modifying, or writing code changes.
- When modifying the Windows install/uninstall scripts, preserve and extend the debug logging around PATH handling to aid troubleshooting.

## Platform expectations

- This is a Windows-first project. `wtouch` depends on Win32 APIs and the primary CMake presets target Visual Studio 2022 on Windows (`windows-release` / `windows-debug`). Prefer documenting and validating flows from **Developer PowerShell for VS** first; Visual Studio Code usage should build on top of that baseline. Work done from the Linux container should stay aligned with the Windows toolchain described in `CMakePresets.json` and the PowerShell scripts under `scripts/` that bootstrap Visual Studio Build Tools, CMake, and Ninja.
- We cannot execute the Windows binaries in this environment. When implementing or reviewing platform-specific logic, cross-check with Microsoft documentation (e.g., `SetFileTime`, `TzSpecificLocalTimeToSystemTime`, `winget`) or existing project scripts to validate assumptions.
- Prefer updating README/usage docs if behavior changes, especially when it impacts Windows command-line semantics (e.g., path quoting, Unicode handling).

## Debugging and logging guidance

- Add or maintain debug logging whenever behavior could be ambiguous. In C++ sources (e.g., `src/touch.cpp`), prefer `std::wcerr` / `std::cerr` or `OutputDebugStringW` for trace statements that explain decision points (parsing, file timestamp conversions, wildcard expansion, etc.).
- In PowerShell scripts (`scripts/*.ps1`), keep `Write-Host`, `Write-Verbose`, and existing helper logging functions consistent so users can follow installation state; do not strip diagnostic output.
- For Bash/Python helper scripts, emit informative status messages (e.g., `set -x` snippets, `echo` progress updates, or `logging` calls) that clarify invoked commands and environment adjustments.

## Helpful notes

- Use the Ninja presets when smoke-testing changes in this container (`cmake --preset ninja-debug` / `ninja-release`) even though the production flow uses MSVC; this keeps the CMake cache compatible while still compiling the shared logic.
- The PowerShell helper `ensure-windows-deps.ps1` assumes `winget` is available. When editing it, verify registry/path probing logic for `WinGet\Links` and common install directories remains intact.
- The installer scripts manage PATH updates—double-check PATH diff output whenever adjusting them to avoid breaking upgrades/uninstalls.

## Testing reminders

- Run the most appropriate preset available (e.g., `ctest --preset ninja-debug`) before submitting changes. Document in the PR description when Windows-only tests could not be executed and describe any reasoning or manual verification steps taken.
