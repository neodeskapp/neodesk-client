// The receiver's install-time file (src/onboard/install_file.rs in the
// client): the MSI properties SERVER, KEY, API, TOKEN and GROUP as
// key=value lines with receiver=Y, in neodesk-install.txt in the install
// folder. lead/receiver-app/MSI-CONTRACT.md has the contract.
//
// - SetInstallConfigData (immediate) reads the properties and hands them
//   with the install folder to the deferred action as its CustomActionData:
//   the folder on the first line, then the file's lines.
// - WriteInstallConfig (deferred, as the system) writes the file. A folder
//   below Program Files is only the system's and the administrators' to
//   change, which the app checks before it takes the file.
// - RemoveInstallConfig (deferred, as the system, on removal) deletes the
//   file and what the app keeps next to it.
#include "pch.h"

#include <string>

#include <shlwapi.h>
#include <strutil.h>

static const wchar_t* INSTALL_CONFIG_NAME = L"neodesk-install.txt";

// A property's value without line breaks and surrounding blanks; empty when
// the property is not set.
static std::wstring PropertyLine(LPCWSTR name)
{
    LPWSTR value = NULL;
    std::wstring out;
    if (SUCCEEDED(WcaGetProperty(name, &value)) && value != NULL) {
        out = value;
    }
    ReleaseStr(value);
    std::wstring clean;
    for (wchar_t c : out) {
        if (c != L'\r' && c != L'\n' && c != L'\0') {
            clean.push_back(c);
        }
    }
    const wchar_t* blanks = L" \t";
    size_t start = clean.find_first_not_of(blanks);
    if (start == std::wstring::npos) {
        return L"";
    }
    size_t end = clean.find_last_not_of(blanks);
    return clean.substr(start, end - start + 1);
}

UINT __stdcall SetInstallConfigData(__in MSIHANDLE hInstall)
{
    HRESULT hr = WcaInitialize(hInstall, "SetInstallConfigData");
    ExitOnFailure(hr, "Failed to initialize");
    {
        std::wstring folder = PropertyLine(L"INSTALLFOLDER_INNER");
        std::wstring server = PropertyLine(L"SERVER");
        if (folder.empty() || server.empty()) {
            WcaLog(LOGMSG_STANDARD, "No SERVER: no install-time file.");
            goto LExit;
        }
        std::wstring data = folder + L"\n" + L"receiver=Y\n";
        const struct {
            LPCWSTR property;
            LPCWSTR key;
        } lines[] = {
            { L"SERVER", L"server" },
            { L"KEY", L"key" },
            { L"API", L"api" },
            { L"TOKEN", L"token" },
            { L"GROUP", L"group" },
        };
        for (const auto& line : lines) {
            std::wstring value = PropertyLine(line.property);
            if (!value.empty()) {
                data += std::wstring(line.key) + L"=" + value + L"\n";
            }
        }
        hr = WcaSetProperty(L"WriteInstallConfig", data.c_str());
        ExitOnFailure(hr, "Failed to hand over the install-time file");
        WcaLog(LOGMSG_STANDARD, "The install-time file will be written for %ls.", server.c_str());
    }

LExit:
    return WcaFinalize(SUCCEEDED(hr) ? ERROR_SUCCESS : ERROR_INSTALL_FAILURE);
}

UINT __stdcall WriteInstallConfig(__in MSIHANDLE hInstall)
{
    HRESULT hr = S_OK;
    LPWSTR pwzData = NULL;
    HANDLE file = INVALID_HANDLE_VALUE;

    hr = WcaInitialize(hInstall, "WriteInstallConfig");
    ExitOnFailure(hr, "Failed to initialize");

    hr = WcaGetProperty(L"CustomActionData", &pwzData);
    ExitOnFailure(hr, "failed to get CustomActionData");
    {
        std::wstring data = pwzData ? pwzData : L"";
        size_t newline = data.find(L'\n');
        if (newline == std::wstring::npos || newline == 0) {
            WcaLog(LOGMSG_STANDARD, "No install-time file to write.");
            goto LExit;
        }
        std::wstring folder = data.substr(0, newline);
        std::wstring text = data.substr(newline + 1);
        if (PathIsRootW(folder.c_str()) || !PathIsDirectoryW(folder.c_str())) {
            WcaLog(LOGMSG_STANDARD, "Refusing the install-time file in '%ls'.", folder.c_str());
            goto LExit;
        }
        if (folder.back() != L'\\') {
            folder.push_back(L'\\');
        }
        std::wstring path = folder + INSTALL_CONFIG_NAME;

        int bytes = WideCharToMultiByte(CP_UTF8, 0, text.c_str(), (int)text.size(), NULL, 0, NULL, NULL);
        std::string utf8(bytes > 0 ? bytes : 0, '\0');
        if (bytes > 0) {
            WideCharToMultiByte(CP_UTF8, 0, text.c_str(), (int)text.size(), &utf8[0], bytes, NULL, NULL);
        }
        file = CreateFileW(path.c_str(), GENERIC_WRITE, 0, NULL, CREATE_ALWAYS,
            FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT, NULL);
        if (file == INVALID_HANDLE_VALUE) {
            hr = HRESULT_FROM_WIN32(GetLastError());
            ExitOnFailure(hr, "Failed to create the install-time file");
        }
        DWORD written = 0;
        if (!WriteFile(file, utf8.data(), (DWORD)utf8.size(), &written, NULL) || written != utf8.size()) {
            hr = HRESULT_FROM_WIN32(GetLastError());
            ExitOnFailure(hr, "Failed to write the install-time file");
        }
        WcaLog(LOGMSG_STANDARD, "Wrote the install-time file in '%ls'.", folder.c_str());
    }

LExit:
    if (file != INVALID_HANDLE_VALUE) {
        CloseHandle(file);
    }
    ReleaseStr(pwzData);
    return WcaFinalize(SUCCEEDED(hr) ? ERROR_SUCCESS : ERROR_INSTALL_FAILURE);
}

UINT __stdcall RemoveInstallConfig(__in MSIHANDLE hInstall)
{
    HRESULT hr = S_OK;
    LPWSTR pwzData = NULL;

    hr = WcaInitialize(hInstall, "RemoveInstallConfig");
    ExitOnFailure(hr, "Failed to initialize");

    hr = WcaGetProperty(L"CustomActionData", &pwzData);
    ExitOnFailure(hr, "failed to get CustomActionData");
    {
        std::wstring folder = pwzData ? pwzData : L"";
        if (folder.empty() || PathIsRootW(folder.c_str())) {
            goto LExit;
        }
        if (folder.back() != L'\\') {
            folder.push_back(L'\\');
        }
        const wchar_t* names[] = {
            L"neodesk-install.txt",
            L"neodesk-install.txt.new",
            L"uninstall-shortcut.lnk.blocked",
        };
        for (const wchar_t* name : names) {
            std::wstring path = folder + name;
            if (DeleteFileW(path.c_str())) {
                WcaLog(LOGMSG_STANDARD, "Removed '%ls'.", path.c_str());
            }
        }
    }

LExit:
    ReleaseStr(pwzData);
    return WcaFinalize(SUCCEEDED(hr) ? ERROR_SUCCESS : ERROR_INSTALL_FAILURE);
}
