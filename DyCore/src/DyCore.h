#pragma once
#include <windows.h>

#include <filesystem>

#include "api.h"

HWND get_hwnd_handle();
HMODULE get_hmodule();

std::filesystem::path get_program_path();

DYCORE_API double DyCore_shutdown();
