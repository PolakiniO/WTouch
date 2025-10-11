# WTouch

```
 _       ________                 __
| |     / /_  __/___  __  _______/ /_
| | /| / / / / / __ \\ / / / / ___/ __ \
| |/ |/ / / / / /_/ / /_/ / /__/ / / /
|__/|__/ /_/  \\____/\\__,_/\\___/_/ /_/
```

`wtouch` is a Windows-native recreation of the GNU `touch` utility. It creates files on demand and updates access or modification timestamps without altering file contents. The implementation uses Win32 APIs so it works seamlessly with Unicode paths, files, and directories.

## Features

* Create files when they do not yet exist (unless `--no-create` is provided).
* Update access times (`-a`) and/or modification times (`-m`).
* Copy timestamps from another file with `-r`.
* Apply explicit timestamps via `-d` (ISO-like strings) or `-t` (`[[CC]YY]MMDDhhmm[.ss]`).
* Accept multiple paths and expand Windows wildcards internally via `FindFirstFileW`.
* Works with both files and directories, honoring Unicode paths.

## Building from source

1. Install your preferred build tools:
   * **Windows (Visual Studio Code workflow)** – install the latest [Visual Studio Build Tools](https://visualstudio.microsoft.com/downloads/) with the “Desktop development with C++” workload, [CMake](https://cmake.org/download/), and [Ninja](https://ninja-build.org/). Inside Visual Studio Code, add the official [CMake Tools extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode.cmake-tools). Launch **Developer PowerShell for VS** (installed alongside the build tools) before opening VS Code so that the MSVC environment is available to both PowerShell and the editor.
   * **Windows (command-line only)** – install the Visual Studio Build Tools (or a full Visual Studio installation) and CMake. Run the commands shown below from **Developer PowerShell for VS** so that `cl.exe` is available to CMake.
   * **Linux/macOS** – install a recent C++17 compiler, CMake, and Ninja.
2. Open a terminal or Developer PowerShell and clone this repository.
3. Configure and build using the bundled CMake presets. They automatically pick
   the right generator for your platform and also work seamlessly inside
   Visual Studio Code via the CMake Tools extension:

   ```powershell
   # Windows
   cmake --preset windows-release
   cmake --build --preset windows-release

   # Linux/macOS
   cmake --preset ninja-release
   cmake --build --preset ninja-release
   ```

   If you prefer to invoke CMake manually, make sure to specify a generator
   that matches your toolchain, for example:

   ```powershell
   cmake -S . -B build -G "Visual Studio 17 2022" -A x64
   cmake --build build --config Release

   # or use Ninja (single-config, works on Windows, Linux, and macOS)
   cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
   cmake --build build
   ```

The resulting executable will be written to
`build/Release/wtouch.exe` (or `build/windows-release/Release/wtouch.exe` when
using the preset).

## Installation

### Using CMake install

Run the standard install target to copy the binary to `CMAKE_INSTALL_PREFIX`
(defaults to `C:\Program Files\wtouch`). On Windows, the installer also appends
the chosen install directory to your user `PATH` automatically unless you opt
out during configuration. When using Visual Studio Code, pick the `windows-release`
configure preset from the CMake Tools status bar, build it, and then run the
**CMake: Install** command from the palette. From a standalone terminal the
equivalent is:

```powershell
cmake --install build --config Release
```

To skip the automatic `PATH` update, configure the project with
`-DWTOUCH_INSTALL_ADD_TO_PATH=OFF` before running the install step.

### Using the prebuilt binary

A prebuilt binary is optionally published at [https://github.com/your-org/wtouch/releases/latest/download/wtouch.exe](https://github.com/your-org/wtouch/releases/latest/download/wtouch.exe).

You can install it directly with PowerShell:

```powershell
$destination = "$env:ProgramFiles\wtouch"
New-Item -ItemType Directory -Path $destination -Force | Out-Null
Invoke-WebRequest -Uri "https://github.com/your-org/wtouch/releases/latest/download/wtouch.exe" -OutFile (Join-Path $destination 'wtouch.exe')
```

After installation, add `$destination` to your `PATH` if it is not already present.

### Installing from a PowerShell prompt (any build)

The helper script works with both the native C++ binary and the portable C
implementation. Run it from Developer PowerShell or another prompt with the
compiler environment initialised:

```powershell
.\scripts\install-wtouch.ps1                 # installs the native build
.\scripts\install-wtouch.ps1 -Variant c      # installs the portable C build

# Common flags
.\scripts\install-wtouch.ps1 -SkipCopy         # only update PATH
.\scripts\install-wtouch.ps1 -SkipPathUpdate   # only copy binaries
.\scripts\install-wtouch.ps1 -Destination "C:\Tools\wtouch"
```

When invoked without `-SkipPathUpdate`, the script ensures the destination is
present on the user `PATH`, which is ideal for PowerShell- and VS Code-based
workflows.

### Uninstalling

To remove a previously installed binary, run the companion uninstall script.
It deletes the selected implementation from the destination directory and
removes the folder from your user `PATH` when present:

```powershell
.\scripts\uninstall-wtouch.ps1                  # removes the native build
.\scripts\uninstall-wtouch.ps1 -Variant c       # removes the portable C build
```

The uninstall script only deletes empty directories, so if you placed other
files in the installation folder they will be preserved.

### Available implementations

`wtouch` now ships four standalone implementations that can live side by side.
Each one resides in its own subdirectory (or the original `src` tree for the
native build) so that installing one will not interfere with the others:

* **Native C++ binary** – `src/touch.cpp`, built with CMake as described above.
* **Bash script** – `bash/wtouch.sh`, a wrapper around the host `touch`.
* **Portable C utility** – `c/wtouch.c`, a cross-platform reimplementation.
* **Python script** – `python/wtouch.py`, relying only on the standard library.

The sections below outline how to install each flavour individually.

#### Native C++ version

The Windows-native C++ implementation remains the primary build. Follow the
instructions in [Building from source](#building-from-source) to compile it with
CMake. To install the resulting executable alongside the other versions without
conflict, choose a unique destination filename when copying it onto your
`PATH`, for example:

```powershell
cmake --build build --config Release
Copy-Item build/Release/wtouch.exe "$env:ProgramFiles\\wtouch\\wtouch-cpp.exe"
```

The CMake installer handles copying the binary and appending the installation
directory to your user `PATH` by default. If you prefer to manage the process
yourself, the helper script remains available:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/install-wtouch.ps1 -Variant cpp
```

Add `-SkipCopy` to update your `PATH` without copying a new binary, or
`-SkipPathUpdate` if you would rather modify `PATH` manually.

#### Bash script version

The Bash implementation (`bash/wtouch.sh`) is a thin wrapper around the
platform's `touch` utility. It accepts the same flags as the native build and
passes them straight through, so behaviour depends on the underlying `touch`
command. To install it, copy the script somewhere on your `PATH` and make it
executable:

```bash
install -m 0755 bash/wtouch.sh /usr/local/bin/wtouch
```

#### Portable C version

The portable C implementation (`c/wtouch.c`) targets modern POSIX and Windows
compilers. A simple `Makefile` is provided for Unix-like systems:

```bash
cd c
make            # builds ./wtouch_c
sudo install -m 0755 wtouch_c /usr/local/bin/wtouch_c
```

On Windows, build the same source with a toolchain such as MSVC or MinGW, for
example:

```powershell
cl /std:c11 /W4 /EHsc wtouch.c
```

Run the helper script to copy the resulting executable to
`%ProgramFiles%\wtouch\wtouch-c.exe` and append that location to your user
`PATH`. You can suppress either action with `-SkipCopy` or `-SkipPathUpdate`:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/install-wtouch.ps1 -Variant c
```

The resulting executable mirrors the command-line flags exposed by the native
binary but relies on the host C runtime for timestamp handling.

#### Python version

The Python implementation (`python/wtouch.py`) is fully cross-platform and only
depends on the standard library. Install it by copying the script to a location
on your `PATH` or by invoking it directly with Python:

```bash
python3 python/wtouch.py [options] files...
```

To make it globally accessible:

```bash
install -m 0755 python/wtouch.py /usr/local/bin/wtouch.py
```

## Running tests

The project includes PowerShell-based integration tests that run under CTest. Tests currently target Windows and require PowerShell:

```powershell
cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build --config Debug
ctest --test-dir build --output-on-failure --config Debug
```

## Command-line usage

```
wtouch [OPTION]... FILE...

  -a                   Change the access time only
  -m                   Change the modification time only
  -c, --no-create      Do not create any files
  -d STRING            Parse STRING as an explicit timestamp (YYYY-MM-DD [HH:MM[:SS]])
  -t STAMP             Parse STAMP in [[CC]YY]MMDDhhmm[.ss] format
  -r FILE              Use FILE's access/modification times
      --               Treat all following arguments as literal paths
  -V, --version        Show version information
  -P, --path           Show the resolved executable/script path
```

If no `-a` or `-m` flag is specified, both access and modification times are updated to the current time by default.

## Potential future flags

Several quality-of-life flags are common across other `touch` variants and would be practical additions here:

* `--dry-run` – Print the operations that would be performed without mutating the filesystem. This helps with verifying wildcard expansions and timestamp sources.
* `--utc` – Force all explicit timestamps to be interpreted as UTC instead of local time, matching GNU `touch --time=UTC` behaviour and making scripted usage predictable across time zones.
* `--no-dereference` – Update symlink metadata instead of the target where the host platform permits it. This mirrors the `-h` option on BSD systems and is useful for deployment scripts that manage symlinks.

These candidates provide clearer parity with platform utilities while remaining feasible for each maintained implementation.
