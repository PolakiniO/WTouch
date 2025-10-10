# WTouch

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
3. Configure and build:

   ```powershell
   cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
   cmake --build build --config Release
   ```

The resulting executable will be written to `build/Release/wtouch.exe`.

## Installation

### Using CMake install

Run the standard install target to copy the binary to `CMAKE_INSTALL_PREFIX` (defaults to `C:\Program Files\wtouch`):

```powershell
cmake --install build --config Release
```

### Using the prebuilt binary

A prebuilt binary is optionally published at [https://github.com/your-org/wtouch/releases/latest/download/wtouch.exe](https://github.com/your-org/wtouch/releases/latest/download/wtouch.exe).

You can install it directly with PowerShell:

```powershell
$destination = "$env:ProgramFiles\wtouch"
New-Item -ItemType Directory -Path $destination -Force | Out-Null
Invoke-WebRequest -Uri "https://github.com/your-org/wtouch/releases/latest/download/wtouch.exe" -OutFile (Join-Path $destination 'wtouch.exe')
```

After installation, add `$destination` to your `PATH` if it is not already present.

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
