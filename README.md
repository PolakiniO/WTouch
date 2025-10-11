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

1. Install the [Visual Studio Build Tools](https://visualstudio.microsoft.com/downloads/) (or a full Visual Studio installation) and [CMake](https://cmake.org/download/).
2. Open a Developer PowerShell prompt and clone this repository.
3. Configure and build. The repository ships a CMake preset that selects the
   Visual Studio generator and x64 toolchain automatically, so the only thing
   you need to do is:

   ```powershell
   cmake --preset windows-release
   cmake --build --preset windows-release
   ```

   If you prefer to invoke CMake manually, make sure to specify an MSVC-based
   generator explicitly so that CMake does not fall back to `NMake Makefiles`
   (which requires `nmake.exe` to be installed separately):

   ```powershell
   cmake -S . -B build -G "Visual Studio 17 2022" -A x64
   cmake --build build --config Release
   ```

The resulting executable will be written to
`build/Release/wtouch.exe` (or `build/windows-release/Release/wtouch.exe` when
using the preset).

## Installation

### Using CMake install

Run the standard install target to copy the binary to `CMAKE_INSTALL_PREFIX`
(defaults to `C:\Program Files\wtouch`). On Windows, the installer also appends
the chosen install directory to your user `PATH` automatically unless you opt
out during configuration:

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
```

If no `-a` or `-m` flag is specified, both access and modification times are updated to the current time by default.
