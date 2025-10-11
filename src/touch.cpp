#ifndef _WIN32
#error "wtouch is only supported on Windows"
#endif

#include <windows.h>
#include <string>
#include <vector>
#include <optional>
#include <iostream>
#include <filesystem>
#include <cwctype>
#include <sstream>
#include <iomanip>
#include <ctime>

namespace fs = std::filesystem;

struct ParsedTime {
    FILETIME access;
    FILETIME modify;
};

struct Options {
    bool touchAccess = false;
    bool touchModify = false;
    bool noCreate = false;
    bool showVersion = false;
    bool showPath = false;
    bool showHelp = false;
    std::optional<FILETIME> explicitTime;
    std::optional<ParsedTime> referenceTimes;
    std::vector<std::wstring> paths;
};

constexpr const wchar_t *kVersionString = L"1.0.0";

void PrintUsage() {
    std::wcout << L"Usage: wtouch [OPTION]... FILE..." << std::endl;
    std::wcout << L"Update the access and modification times of each FILE." << std::endl;
    std::wcout << std::endl;
    std::wcout << L"Options:" << std::endl;
    std::wcout << L"  -a             change only the access time" << std::endl;
    std::wcout << L"  -m             change only the modification time" << std::endl;
    std::wcout << L"  -c             do not create any files" << std::endl;
    std::wcout << L"  -d DATE        parse DATE (YYYY-mm-dd[ HH:MM[:SS]])" << std::endl;
    std::wcout << L"  -t STAMP       parse [[CC]YY]mmddHHMM[.SS] timestamp" << std::endl;
    std::wcout << L"  -r FILE        use times from reference FILE" << std::endl;
    std::wcout << L"      --         treat all following arguments as literal paths" << std::endl;
    std::wcout << L"  -P             print the executable path" << std::endl;
    std::wcout << L"  -V             print the program version" << std::endl;
    std::wcout << L"  --help         display this help and exit" << std::endl;
    std::wcout << std::endl;
    std::wcout << L"By default, both access and modification times are updated." << std::endl;
}

std::optional<std::wstring> GetExecutablePath() {
    std::wstring buffer(MAX_PATH, L'\0');
    while (true) {
        DWORD copied = GetModuleFileNameW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
        if (copied == 0) {
            return std::nullopt;
        }
        if (copied < buffer.size() - 1) {
            buffer.resize(copied);
            return buffer;
        }
        buffer.resize(buffer.size() * 2, L'\0');
    }
}

bool ParseIntRange(const std::wstring &text, size_t start, size_t length, int &value) {
    if (start + length > text.size()) {
        return false;
    }
    int result = 0;
    for (size_t i = 0; i < length; ++i) {
        wchar_t ch = text[start + i];
        if (!std::iswdigit(ch)) {
            return false;
        }
        result = result * 10 + (ch - L'0');
    }
    value = result;
    return true;
}

bool HasWildcards(const std::wstring &path) {
    return path.find_first_of(L"*?") != std::wstring::npos;
}

bool SystemTimeToFileTimeLocal(const SYSTEMTIME &local, FILETIME &out) {
    SYSTEMTIME utc;
    if (!TzSpecificLocalTimeToSystemTime(nullptr, &local, &utc)) {
        return false;
    }
    return SystemTimeToFileTime(&utc, &out);
}

bool ParseDateTimeString(const std::wstring &value, FILETIME &out) {
    std::wstring normalized = value;
    for (auto &ch : normalized) {
        if (ch == L'T') {
            ch = L' ';
        }
    }
    std::wistringstream stream(normalized);
    std::tm tm = {};
    stream >> std::get_time(&tm, L"%Y-%m-%d %H:%M:%S");
    if (stream.fail()) {
        stream.clear();
        stream.str(normalized);
        tm = {};
        stream >> std::get_time(&tm, L"%Y-%m-%d %H:%M");
    }
    if (stream.fail()) {
        stream.clear();
        stream.str(normalized);
        tm = {};
        stream >> std::get_time(&tm, L"%Y-%m-%d");
    }
    if (stream.fail()) {
        return false;
    }

    SYSTEMTIME local = {};
    local.wYear = static_cast<WORD>(tm.tm_year + 1900);
    local.wMonth = static_cast<WORD>(tm.tm_mon + 1);
    local.wDay = static_cast<WORD>(tm.tm_mday);
    local.wHour = static_cast<WORD>(tm.tm_hour);
    local.wMinute = static_cast<WORD>(tm.tm_min);
    local.wSecond = static_cast<WORD>(tm.tm_sec);
    local.wMilliseconds = 0;

    return SystemTimeToFileTimeLocal(local, out);
}

bool ParseTimestampFormat(const std::wstring &value, FILETIME &out) {
    if (value.empty()) {
        return false;
    }

    std::wstring mainPart = value;
    int seconds = 0;
    size_t dot = value.find(L'.');
    if (dot != std::wstring::npos) {
        mainPart = value.substr(0, dot);
        std::wstring secPart = value.substr(dot + 1);
        if (secPart.size() != 2) {
            return false;
        }
        if (!ParseIntRange(secPart, 0, 2, seconds)) {
            return false;
        }
    }

    size_t len = mainPart.size();
    if (len != 8 && len != 10 && len != 12) {
        return false;
    }

    for (wchar_t ch : mainPart) {
        if (!std::iswdigit(ch)) {
            return false;
        }
    }

    SYSTEMTIME now;
    GetLocalTime(&now);
    SYSTEMTIME local = now;

    auto parseTwo = [&](int &index, int &valueOut) -> bool {
        if (index < 2) {
            return false;
        }
        int start = index - 2;
        int parsed = 0;
        if (!ParseIntRange(mainPart, static_cast<size_t>(start), 2, parsed)) {
            return false;
        }
        index -= 2;
        valueOut = parsed;
        return true;
    };

    int index = static_cast<int>(len);
    int minute = 0;
    int hour = 0;
    int day = 0;
    int month = 0;
    if (!parseTwo(index, minute) || !parseTwo(index, hour) || !parseTwo(index, day) || !parseTwo(index, month)) {
        return false;
    }

    int year = now.wYear;
    if (index == 2) {
        int twoDigitYear = 0;
        if (!ParseIntRange(mainPart, 0, 2, twoDigitYear)) {
            return false;
        }
        int century = (now.wYear / 100) * 100;
        year = century + twoDigitYear;
    } else if (index == 4) {
        int parsedYear = 0;
        if (!ParseIntRange(mainPart, 0, 4, parsedYear)) {
            return false;
        }
        year = parsedYear;
    } else if (index != 0) {
        return false;
    }

    local.wYear = static_cast<WORD>(year);
    local.wMonth = static_cast<WORD>(month);
    local.wDay = static_cast<WORD>(day);
    local.wHour = static_cast<WORD>(hour);
    local.wMinute = static_cast<WORD>(minute);
    local.wSecond = static_cast<WORD>(seconds);
    local.wMilliseconds = 0;

    if (month < 1 || month > 12 || day < 1 || day > 31 || hour < 0 || hour > 23 || minute < 0 || minute > 59 || seconds < 0 || seconds > 59) {
        return false;
    }

    return SystemTimeToFileTimeLocal(local, out);
}

std::optional<ParsedTime> LoadReferenceTimes(const std::wstring &path) {
    DWORD flags = FILE_ATTRIBUTE_NORMAL;
    DWORD access = FILE_READ_ATTRIBUTES;
    DWORD share = FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE;
    DWORD creation = OPEN_EXISTING;

    DWORD attributes = GetFileAttributesW(path.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES) {
        return std::nullopt;
    }
    if (attributes & FILE_ATTRIBUTE_DIRECTORY) {
        flags |= FILE_FLAG_BACKUP_SEMANTICS;
    }

    HANDLE handle = CreateFileW(path.c_str(), access, share, nullptr, creation, flags, nullptr);
    if (handle == INVALID_HANDLE_VALUE) {
        return std::nullopt;
    }

    FILETIME creationTime{};
    FILETIME accessTime{};
    FILETIME writeTime{};
    bool ok = GetFileTime(handle, &creationTime, &accessTime, &writeTime) != 0;
    CloseHandle(handle);
    if (!ok) {
        return std::nullopt;
    }

    ParsedTime parsed{};
    parsed.access = accessTime;
    parsed.modify = writeTime;
    return parsed;
}

bool ExpandPathPattern(const std::wstring &pattern, std::vector<std::wstring> &results) {
    WIN32_FIND_DATAW findData;
    HANDLE findHandle = FindFirstFileW(pattern.c_str(), &findData);
    if (findHandle == INVALID_HANDLE_VALUE) {
        return false;
    }

    fs::path base = fs::path(pattern).parent_path();

    do {
        std::wstring name(findData.cFileName);
        if (name == L"." || name == L"..") {
            continue;
        }
        fs::path resolved = base.empty() ? fs::path(name) : base / name;
        results.emplace_back(resolved.native());
    } while (FindNextFileW(findHandle, &findData));

    FindClose(findHandle);
    return true;
}

std::vector<std::wstring> ExpandTargets(const std::vector<std::wstring> &inputs) {
    std::vector<std::wstring> expanded;
    for (const auto &input : inputs) {
        if (HasWildcards(input)) {
            std::vector<std::wstring> matches;
            if (ExpandPathPattern(input, matches)) {
                expanded.insert(expanded.end(), matches.begin(), matches.end());
                continue;
            }
        }
        expanded.push_back(input);
    }
    return expanded;
}

bool SetFileTimesForHandle(HANDLE handle, const Options &options) {
    FILETIME creationTime{};
    FILETIME accessTime{};
    FILETIME writeTime{};
    if (!GetFileTime(handle, &creationTime, &accessTime, &writeTime)) {
        return false;
    }

    bool updateAccess = options.touchAccess;
    bool updateModify = options.touchModify;

    if (options.referenceTimes) {
        if (updateAccess) {
            accessTime = options.referenceTimes->access;
        }
        if (updateModify) {
            writeTime = options.referenceTimes->modify;
        }
    } else if (options.explicitTime.has_value()) {
        if (updateAccess) {
            accessTime = options.explicitTime.value();
        }
        if (updateModify) {
            writeTime = options.explicitTime.value();
        }
    } else {
        FILETIME currentTime{};
        GetSystemTimeAsFileTime(&currentTime);
        if (updateAccess) {
            accessTime = currentTime;
        }
        if (updateModify) {
            writeTime = currentTime;
        }
    }

    return SetFileTime(handle, &creationTime, updateAccess ? &accessTime : nullptr, updateModify ? &writeTime : nullptr) != 0;
}

bool EnsureTimesForPath(const std::wstring &path, const Options &options) {
    DWORD attributes = GetFileAttributesW(path.c_str());
    bool exists = attributes != INVALID_FILE_ATTRIBUTES;
    bool isDirectory = exists && (attributes & FILE_ATTRIBUTE_DIRECTORY);

    if (!exists && options.noCreate) {
        std::wcerr << L"wtouch: cannot touch '" << path << L"': No such file or directory" << std::endl;
        return false;
    }

    DWORD desiredAccess = FILE_WRITE_ATTRIBUTES | FILE_READ_ATTRIBUTES;
    DWORD shareMode = FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE;
    DWORD creationDisposition = exists ? OPEN_EXISTING : OPEN_ALWAYS;
    DWORD flags = isDirectory ? FILE_FLAG_BACKUP_SEMANTICS : FILE_ATTRIBUTE_NORMAL;

    HANDLE handle = CreateFileW(path.c_str(), desiredAccess, shareMode, nullptr, creationDisposition, flags, nullptr);
    if (handle == INVALID_HANDLE_VALUE) {
        DWORD error = GetLastError();
        if (!exists && error == ERROR_PATH_NOT_FOUND) {
            std::wcerr << L"wtouch: cannot touch '" << path << L"': Path not found" << std::endl;
        } else {
            std::wcerr << L"wtouch: failed to open '" << path << L"' (error " << error << L")" << std::endl;
        }
        return false;
    }

    bool success = SetFileTimesForHandle(handle, options);
    if (!success) {
        DWORD error = GetLastError();
        std::wcerr << L"wtouch: failed to update times for '" << path << L"' (error " << error << L")" << std::endl;
    }

    CloseHandle(handle);
    return success;
}

std::optional<Options> ParseArguments(int argc, wchar_t *argv[]) {
    Options options;

    for (int i = 1; i < argc; ++i) {
        std::wstring arg = argv[i];

        if (arg == L"--") {
            for (int j = i + 1; j < argc; ++j) {
                options.paths.emplace_back(argv[j]);
            }
            break;
        }

        if (!arg.empty() && arg[0] == L'-' && arg != L"-") {
            if (arg == L"--no-create") {
                options.noCreate = true;
                continue;
            }

            if (arg == L"--version") {
                options.showVersion = true;
                continue;
            }

            if (arg == L"--path") {
                options.showPath = true;
                continue;
            }

            if (arg == L"--help") {
                options.showHelp = true;
                continue;
            }

            if (arg.size() >= 2 && arg[1] == L'-') {
                std::wcerr << L"wtouch: unknown option '" << arg << L"'" << std::endl;
                return std::nullopt;
            }

            for (size_t j = 1; j < arg.size(); ++j) {
                wchar_t flag = arg[j];
                switch (flag) {
                    case L'a':
                        options.touchAccess = true;
                        break;
                    case L'm':
                        options.touchModify = true;
                        break;
                    case L'c':
                        options.noCreate = true;
                        break;
                    case L'V':
                        options.showVersion = true;
                        break;
                    case L'P':
                        options.showPath = true;
                        break;
                    case L'h':
                        options.showHelp = true;
                        break;
                    case L'd':
                    case L't':
                    case L'r': {
                        std::wstring value;
                        if (j + 1 < arg.size()) {
                            value = arg.substr(j + 1);
                            j = arg.size();
                        } else {
                            if (i + 1 >= argc) {
                                std::wcerr << L"wtouch: option '-" << flag << L"' requires an argument" << std::endl;
                                return std::nullopt;
                            }
                            value = argv[++i];
                        }

                        if (flag == L'd') {
                            FILETIME ft;
                            if (!ParseDateTimeString(value, ft)) {
                                std::wcerr << L"wtouch: invalid date format for -d" << std::endl;
                                return std::nullopt;
                            }
                            options.explicitTime = ft;
                            options.referenceTimes.reset();
                        } else if (flag == L't') {
                            FILETIME ft;
                            if (!ParseTimestampFormat(value, ft)) {
                                std::wcerr << L"wtouch: invalid timestamp for -t" << std::endl;
                                return std::nullopt;
                            }
                            options.explicitTime = ft;
                            options.referenceTimes.reset();
                        } else if (flag == L'r') {
                            auto refTimes = LoadReferenceTimes(value);
                            if (!refTimes) {
                                std::wcerr << L"wtouch: failed to read reference times from '" << value << L"'" << std::endl;
                                return std::nullopt;
                            }
                            options.referenceTimes = refTimes;
                            options.explicitTime.reset();
                        }
                        break;
                    }
                    default:
                        std::wcerr << L"wtouch: unknown option '-" << flag << L"'" << std::endl;
                        return std::nullopt;
                }
            }
        } else {
            options.paths.push_back(arg);
        }
    }

    if (options.paths.empty() && !options.showVersion && !options.showPath && !options.showHelp) {
        std::wcerr << L"wtouch: missing file operand" << std::endl;
        return std::nullopt;
    }

    if (!options.paths.empty() && !options.touchAccess && !options.touchModify) {
        options.touchAccess = true;
        options.touchModify = true;
    }

    return options;
}

int wmain(int argc, wchar_t *argv[]) {
    if (argc <= 1) {
        PrintUsage();
        return 0;
    }

    auto parsed = ParseArguments(argc, argv);
    if (!parsed) {
        return 1;
    }

    Options options = std::move(*parsed);

    if (options.showHelp) {
        PrintUsage();
        return 0;
    }

    bool infoOk = true;
    if (options.showVersion) {
        std::wcout << L"wtouch version " << kVersionString << std::endl;
    }

    if (options.showPath) {
        auto executablePath = GetExecutablePath();
        if (!executablePath) {
            std::wcerr << L"wtouch: failed to determine executable path" << std::endl;
            infoOk = false;
        } else {
            std::wcout << L"wtouch path " << *executablePath << std::endl;
        }
    }

    if ((options.showVersion || options.showPath) && options.paths.empty()) {
        return infoOk ? 0 : 1;
    }

    if (!infoOk) {
        return 1;
    }

    auto targets = ExpandTargets(options.paths);
    if (targets.empty()) {
        std::wcerr << L"wtouch: no files matched" << std::endl;
        return 1;
    }

    bool success = true;
    for (const auto &path : targets) {
        if (!EnsureTimesForPath(path, options)) {
            success = false;
        }
    }

    return success ? 0 : 1;
}
