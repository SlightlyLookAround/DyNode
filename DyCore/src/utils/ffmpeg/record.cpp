#include "record.h"

#include <cctype>
#include <charconv>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <string_view>
#include <system_error>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include "utils.h"

// Initialize static members for encoder pre-flight check
std::unordered_map<std::string, bool> Recorder::encoder_availability_cache;
std::mutex Recorder::cache_mutex;

#ifdef _WIN32
#define NOMINMAX
#include <Windows.h>
#include <fcntl.h>
#include <io.h>
#endif

// FFmpeg Encoders Availability Detection and process helpers
namespace {
Recorder* existingRecorder = nullptr;

#ifdef _WIN32
bool run_command_capture_output_utf8(const std::string& cmd,
                                     std::string& output) {
    SECURITY_ATTRIBUTES saAttr{};
    saAttr.nLength = sizeof(saAttr);
    saAttr.bInheritHandle = TRUE;
    saAttr.lpSecurityDescriptor = NULL;

    HANDLE hRead = NULL, hWrite = NULL;
    if (!CreatePipe(&hRead, &hWrite, &saAttr, 0)) {
        print_debug_message(
            "run_command_capture_output_utf8: CreatePipe failed.");
        return false;
    }
    if (!SetHandleInformation(hRead, HANDLE_FLAG_INHERIT, 0)) {
        print_debug_message(
            "run_command_capture_output_utf8: SetHandleInformation failed.");
        CloseHandle(hRead);
        CloseHandle(hWrite);
        return false;
    }

    STARTUPINFOW si{};
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;
    si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
    si.hStdOutput = hWrite;
    si.hStdError = hWrite;

    PROCESS_INFORMATION pi{};
    std::wstring wcmd = s2ws(cmd);
    std::wstring cmdline = wcmd;

    BOOL ok = CreateProcessW(NULL, cmdline.data(), NULL, NULL, TRUE,
                             CREATE_NO_WINDOW, NULL, NULL, &si, &pi);

    CloseHandle(hWrite);

    if (!ok) {
        print_debug_message(
            "run_command_capture_output_utf8: CreateProcessW failed.");
        CloseHandle(hRead);
        return false;
    }

    const DWORD BUF_SIZE = 4096;
    char buffer[BUF_SIZE];
    DWORD bytes = 0;
    for (;;) {
        BOOL success = ReadFile(hRead, buffer, BUF_SIZE, &bytes, NULL);
        if (!success || bytes == 0)
            break;
        output.append(buffer, buffer + bytes);
    }
    CloseHandle(hRead);

    WaitForSingleObject(pi.hProcess, INFINITE);
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    return true;
}
#else
bool run_command_capture_output_utf8(const std::string& cmd,
                                     std::string& output) {
    (void)cmd;
    (void)output;
    print_debug_message(
        "Not Implemented: POSIX process APIs are not supported in this build.");
    return false;
}
#endif

bool has_token_word(const std::string& haystack, const std::string& needle) {
    size_t pos = haystack.find(needle);
    while (pos != std::string::npos) {
        bool left_ok =
            (pos == 0) ||
            std::isspace(static_cast<unsigned char>(haystack[pos - 1]));
        size_t end = pos + needle.size();
        bool right_ok = (end >= haystack.size()) ||
                        std::isspace(static_cast<unsigned char>(haystack[end]));
        if (left_ok && right_ok)
            return true;
        pos = haystack.find(needle, pos + 1);
    }
    return false;
}

// std::to_string(double) is locale-dependent and can emit "1,000000", which
// FFmpeg's -itsoffset parser rejects or misreads.
std::string format_seconds_locale_independent(double seconds) {
    char buf[64];
    auto result = std::to_chars(buf, buf + sizeof(buf), seconds,
                                std::chars_format::fixed, 6);
    if (result.ec != std::errc())
        return "0.000000";
    return std::string(buf, result.ptr);
}

}  // namespace

// Return available encoders: "h264", "h265", "nvenc", "intel", "amd"
std::unordered_set<std::string> ffmpeg_detect_available_encoders() {
    std::unordered_set<std::string> result;

    std::string out;
    if (!run_command_capture_output_utf8("ffmpeg -hide_banner -encoders",
                                         out)) {
        print_debug_message(
            "ffmpeg_detect_available_encoders: failed to run ffmpeg -encoders");
        return result;
    }

    std::string lower = out;
    for (char& c : lower) {
        c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    }

    enum Flags {
        F_H264 = 1 << 0,
        F_H265 = 1 << 1,
        F_NVENC = 1 << 2,
        F_INTEL = 1 << 3,
        F_AMD = 1 << 4
    };
    int flags = 0;

    struct Tok {
        const char* token;
        int set;
    };
    const Tok toks[] = {
        {"libx264", F_H264},
        {"libx265", F_H265},
        {"h264_nvenc", F_H264 | F_NVENC},
        {"hevc_nvenc", F_H265 | F_NVENC},
        {"h265_nvenc", F_H265 | F_NVENC},
        {"h264_qsv", F_H264 | F_INTEL},
        {"hevc_qsv", F_H265 | F_INTEL},
        {"h265_qsv", F_H265 | F_INTEL},
        {"h264_amf", F_H264 | F_AMD},
        {"hevc_amf", F_H265 | F_AMD},
        {"h265_amf", F_H265 | F_AMD},
    };

    for (const auto& t : toks) {
        if (has_token_word(lower, t.token)) {
            flags |= t.set;
        }
    }

    if (flags & F_H264)
        result.insert("h264");
    if (flags & F_H265)
        result.insert("h265");
    if (flags & F_NVENC)
        result.insert("nvenc");
    if (flags & F_INTEL)
        result.insert("intel");
    if (flags & F_AMD)
        result.insert("amd");

    return result;
}

std::string Recorder::build_ffmpeg_cmd_utf8(std::string_view pixel_fmt,
                                            std::string_view filename_utf8,
                                            std::string_view musicPath,
                                            int width, int height, int fps,
                                            double musicOffset) {
#ifdef _WIN32
    // Windows: surround with double quotes and escape any embedded quotes.
    auto quote_arg = [](std::string_view s) {
        std::string out;
        out.reserve(s.size() + 2);
        out.push_back('"');
        for (char ch : s) {
            if (ch == '"') {
                out.push_back('\\');
                out.push_back('"');
            } else {
                out.push_back(ch);
            }
        }
        out.push_back('"');
        return out;
    };

    const std::string quoted_filename = quote_arg(filename_utf8);

    std::string cmd, usingEncoder = get_default_encoder();
    this->usingDecoder = usingEncoder;

    print_debug_message("Using Encoder: " + usingEncoder);

    cmd.reserve(256 + quoted_filename.size());
    cmd.append("ffmpeg -f rawvideo -pix_fmt ");
    cmd.append(pixel_fmt);
    cmd.append(" -s ");
    cmd.append(std::to_string(width));
    cmd.append("x");
    cmd.append(std::to_string(height));
    cmd.append(" -r ");
    cmd.append(std::to_string(fps));
    cmd.append(" -i - ");
    if (!musicPath.empty()) {
        cmd.append("-itsoffset ");
        cmd.append(format_seconds_locale_independent(musicOffset));
        cmd.append(" ");
        cmd.append("-i ");
        cmd.append(quote_arg(musicPath));
        cmd.append(" -map 0:v -map 1:a -c:a aac -b:a 192k ");
    }
    cmd.append(" -c:v " + usingEncoder + " ");
    cmd.append(ffmpegEncoderOptions.at(usingEncoder));
    cmd.append("-y ");
    cmd.append(quoted_filename);
    return cmd;
#else
    (void)pixel_fmt;
    (void)filename_utf8;
    (void)musicPath;
    (void)width;
    (void)height;
    (void)fps;
    (void)musicOffset;
    print_debug_message(
        "Not Implemented: recording command construction is only supported on "
        "Windows.");
    return std::string();
#endif
}

#ifdef _WIN32
PROCESS_INFORMATION g_ffmpeg_pi{};
#endif

static bool open_ffmpeg_pipe_utf8(FILE*& out, const std::string& cmdUtf8) {
#ifdef _WIN32
    // Create a hidden FFmpeg process with its stdin connected to a pipe.
    SECURITY_ATTRIBUTES saAttr{};
    saAttr.nLength = sizeof(saAttr);
    saAttr.bInheritHandle = TRUE;
    saAttr.lpSecurityDescriptor = NULL;

    HANDLE hChildStdinRd = NULL;
    HANDLE hChildStdinWr = NULL;

    if (!CreatePipe(&hChildStdinRd, &hChildStdinWr, &saAttr, 0)) {
        print_debug_message("Error: CreatePipe failed.");
        return false;
    }

    // Ensure the write end is NOT inherited by the child process.
    if (!SetHandleInformation(hChildStdinWr, HANDLE_FLAG_INHERIT, 0)) {
        print_debug_message("Error: SetHandleInformation failed.");
        CloseHandle(hChildStdinRd);
        CloseHandle(hChildStdinWr);
        return false;
    }

    STARTUPINFOW si{};
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;
    si.hStdInput = hChildStdinRd;
    si.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
    si.hStdError = GetStdHandle(STD_ERROR_HANDLE);

    PROCESS_INFORMATION pi{};
    std::wstring wcmd = s2ws(cmdUtf8);
    std::wstring cmdline = wcmd;  // CreateProcessW may modify the buffer.

    BOOL ok =
        CreateProcessW(NULL, cmdline.data(), NULL, NULL,
                       TRUE,              // inherit stdin/stdout/stderr handles
                       CREATE_NO_WINDOW,  // do not create a console window
                       NULL, NULL, &si, &pi);

    // Parent is done with these.
    CloseHandle(hChildStdinRd);

    if (!ok) {
        print_debug_message("Error: CreateProcessW for FFmpeg failed.");
        CloseHandle(hChildStdinWr);
        return false;
    }

    // Convert the write-end HANDLE to a FILE* for fwrite.
    int fd =
        _open_osfhandle(reinterpret_cast<intptr_t>(hChildStdinWr), _O_BINARY);
    if (fd == -1) {
        print_debug_message("Error: _open_osfhandle failed.");
        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
        CloseHandle(hChildStdinWr);
        return false;
    }

    FILE* f = _fdopen(fd, "wb");
    if (!f) {
        print_debug_message("Error: _fdopen failed.");
        _close(fd);  // closes underlying handle
        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
        return false;
    }

    out = f;

    // Save process info for graceful teardown in finish_recording.
    g_ffmpeg_pi = pi;

    return true;
#else
    (void)cmdUtf8;
    out = nullptr;
    print_debug_message(
        "Not Implemented: starting FFmpeg process is only supported on "
        "Windows.");
    return false;
#endif
}

void Recorder::writer_worker() {
    while (true) {
        std::unique_lock<std::mutex> lock(queue_mutex);
        queue_cond.wait(
            lock, [this] { return frame_queue_count > 0 || !recording_active; });

        if (frame_queue_count == 0)
            break;

        // Reserve the head slot until fwrite completes so push_frame cannot
        // overwrite in-flight frame data.
        const size_t head = frame_queue_head;
        lock.unlock();

        if (ffmpeg_pipe && head < frame_queue.size()) {
            std::vector<char>& frame_data = frame_queue[head];
            size_t written = fwrite(frame_data.data(), 1, frame_data.size(),
                                    ffmpeg_pipe);
            if (written != frame_data.size()) {
                print_debug_message(
                    "Warning: Incomplete frame write to FFmpeg.");
            }
        }

        lock.lock();
        ++frame_queue_head;
        if (frame_queue_head >= kFrameQueueCapacity)
            frame_queue_head = 0;
        if (frame_queue_count > 0)
            --frame_queue_count;
        lock.unlock();
        queue_cond.notify_all();
    }
}

int Recorder::start_recording(const std::string& filename,
                              const std::string& musicPath, int width,
                              int height, int fps, double musicOffset) {
#ifdef _WIN32
    // Abort paths on the GM side may skip finish_recording; never leak the
    // previous writer thread or FFmpeg process into a new session.
    finish_recording();

    std::string cmd = build_ffmpeg_cmd_utf8(pixelFormat, filename, musicPath,
                                            width, height, fps, musicOffset);
    if (!open_ffmpeg_pipe_utf8(ffmpeg_pipe, cmd)) {
        print_debug_message("Error: Failed to open pipe to FFmpeg.");
        return -1;
    }
    {
        std::lock_guard<std::mutex> lock(queue_mutex);
        frame_queue.clear();
        frame_queue.resize(kFrameQueueCapacity);
        frame_queue_head = 0;
        frame_queue_count = 0;
        recording_active = true;
    }
    writer_thread = std::thread(&Recorder::writer_worker, this);
    print_debug_message("FFmpeg instantiated successfully. Start recording.");
    return 0;
#else
    (void)filename;
    (void)musicPath;
    (void)width;
    (void)height;
    (void)fps;
    (void)musicOffset;
    print_debug_message(
        "Not Implemented: recording is only supported on Windows.");
    return -1;
#endif
}

int Recorder::start_recording(const std::wstring& filename,
                              const std::wstring& musicPath, int width,
                              int height, int fps, double musicOffset) {
#ifdef _WIN32
    finish_recording();

    std::string utf8name = wstringToUtf8(filename);
    std::string utf8musicPath = wstringToUtf8(musicPath);
    std::string cmd = build_ffmpeg_cmd_utf8(
        pixelFormat, utf8name, utf8musicPath, width, height, fps, musicOffset);
    if (!open_ffmpeg_pipe_utf8(ffmpeg_pipe, cmd)) {
        print_debug_message("Error: Failed to open pipe to FFmpeg.");
        return -1;
    }
    {
        std::lock_guard<std::mutex> lock(queue_mutex);
        frame_queue.clear();
        frame_queue.resize(kFrameQueueCapacity);
        frame_queue_head = 0;
        frame_queue_count = 0;
        recording_active = true;
    }
    writer_thread = std::thread(&Recorder::writer_worker, this);
    print_debug_message("FFmpeg instantiated successfully. Start recording.");
    return 0;
#else
    (void)filename;
    (void)musicPath;
    (void)width;
    (void)height;
    (void)fps;
    (void)musicOffset;
    print_debug_message(
        "Not Implemented: recording is only supported on Windows.");
    return -1;
#endif
}

int Recorder::push_frame(const void* frameData, int frameSize) {
#ifdef _WIN32
    auto fail = [&](int code, const std::string& msg) -> int {
        print_debug_message("Error: " + msg + " Code: " + std::to_string(code));
        finish_recording();
        return code;
    };

    if (!frameData || frameSize <= 0) {
        return fail(FFMPEG_PUSH_FRAME_INVALID_ARGUMENT,
                    "push_frame called with invalid parameters.");
    }
    if (!recording_active) {
        return fail(FFMPEG_PUSH_FRAME_NOT_RECORDING,
                    "push_frame called when recording is not active.");
    }
    if (!ffmpeg_pipe) {
        return fail(FFMPEG_PUSH_FRAME_PIPE_UNAVAILABLE,
                    "FFmpeg pipe is not available.");
    }
    if (g_ffmpeg_pi.hProcess == NULL) {
        return fail(FFMPEG_PUSH_FRAME_PROCESS_HANDLE_INVALID,
                    "FFmpeg process handle is invalid.");
    }

    DWORD wait = WaitForSingleObject(g_ffmpeg_pi.hProcess, 0);
    if (wait == WAIT_OBJECT_0) {
        DWORD exit_code = 0;
        GetExitCodeProcess(g_ffmpeg_pi.hProcess, &exit_code);
        return fail(FFMPEG_PUSH_FRAME_PROCESS_EXITED,
                    "FFmpeg process has exited. Exit code: " +
                        std::to_string(exit_code));
    } else if (wait == WAIT_FAILED) {
        return fail(FFMPEG_PUSH_FRAME_PROCESS_WAIT_FAILED,
                    "WaitForSingleObject on FFmpeg process failed.");
    }

    try {
        std::unique_lock<std::mutex> lock(queue_mutex);
        if (frame_queue.size() < kFrameQueueCapacity)
            frame_queue.resize(kFrameQueueCapacity);

        // Never drop frames: each push is one fixed-fps slot on the video
        // timeline. Dropping compresses the stream and desyncs muxed audio.
        // Block until the writer frees a slot, with periodic FFmpeg health
        // checks so a dead encoder cannot hang the game thread forever.
        while (frame_queue_count >= kFrameQueueCapacity && recording_active) {
            lock.unlock();
            if (g_ffmpeg_pi.hProcess != NULL) {
                DWORD health = WaitForSingleObject(g_ffmpeg_pi.hProcess, 0);
                if (health == WAIT_OBJECT_0) {
                    DWORD exit_code = 0;
                    GetExitCodeProcess(g_ffmpeg_pi.hProcess, &exit_code);
                    return fail(
                        FFMPEG_PUSH_FRAME_PROCESS_EXITED,
                        "FFmpeg process exited while waiting for queue space. "
                        "Exit code: " +
                            std::to_string(exit_code));
                }
            }
            lock.lock();
            if (frame_queue_count < kFrameQueueCapacity || !recording_active)
                break;
            queue_cond.wait_for(lock, std::chrono::milliseconds(50));
        }

        if (!recording_active) {
            lock.unlock();
            return fail(FFMPEG_PUSH_FRAME_NOT_RECORDING,
                        "Recording stopped while waiting to enqueue a frame.");
        }

        const size_t frame_bytes = static_cast<size_t>(frameSize);
        const size_t tail =
            (frame_queue_head + frame_queue_count) % kFrameQueueCapacity;
        std::vector<char>& slot = frame_queue[tail];
        if (slot.size() != frame_bytes)
            slot.resize(frame_bytes);
        std::memcpy(slot.data(), frameData, frame_bytes);
        ++frame_queue_count;
        lock.unlock();
        queue_cond.notify_one();
        return FFMPEG_PUSH_FRAME_OK;
    } catch (const std::exception& e) {
        return fail(
            FFMPEG_PUSH_FRAME_ENQUEUE_FAILED,
            std::string("Exception while enqueuing frame: ") + e.what());
    }
#else
    (void)frameData;
    (void)frameSize;
    print_debug_message(
        "Error: push_frame is not supported on non-Windows builds. Code: " +
        std::to_string(FFMPEG_PUSH_FRAME_UNSUPPORTED_PLATFORM));
    finish_recording();
    return FFMPEG_PUSH_FRAME_UNSUPPORTED_PLATFORM;
#endif
}

Recorder::~Recorder() {
    finish_recording();
}

void Recorder::finish_recording() {
    {
        std::lock_guard lock(queue_mutex);
        recording_active = false;
    }
    // Wake both the writer (drain remaining frames) and any push_frame
    // blocked on a full queue.
    queue_cond.notify_all();
    if (writer_thread.joinable())
        writer_thread.join();
#ifdef _WIN32

    if (!ffmpeg_pipe) {
        // Even if ffmpeg_pipe is null, ensure process handles are cleaned up.
        if (g_ffmpeg_pi.hProcess) {
            WaitForSingleObject(g_ffmpeg_pi.hProcess, INFINITE);
            CloseHandle(g_ffmpeg_pi.hThread);
            CloseHandle(g_ffmpeg_pi.hProcess);
            g_ffmpeg_pi.hThread = NULL;
            g_ffmpeg_pi.hProcess = NULL;
        }
        return;
    }

    fflush(ffmpeg_pipe);
    fclose(ffmpeg_pipe);
    ffmpeg_pipe = nullptr;

    if (g_ffmpeg_pi.hProcess) {
        WaitForSingleObject(g_ffmpeg_pi.hProcess, INFINITE);
        CloseHandle(g_ffmpeg_pi.hThread);
        CloseHandle(g_ffmpeg_pi.hProcess);
        g_ffmpeg_pi.hThread = NULL;
        g_ffmpeg_pi.hProcess = NULL;
    }
#else
    if (ffmpeg_pipe) {
        fflush(ffmpeg_pipe);
        fclose(ffmpeg_pipe);
        ffmpeg_pipe = nullptr;
    }
    print_debug_message(
        "Not Implemented: finish_recording on non-Windows does not manage "
        "FFmpeg process.");
#endif
}

bool Recorder::is_encoder_available(const std::string& encoder_name) {
#ifdef _WIN32
    // This command attempts to encode a single frame and discard it.
    // It's a low-overhead way to check if an encoder can be initialized.
    // Some hardware encoders have minimum resolution requirements (e.g.,
    // 256x256), so we use a safe resolution for the test. The "-loglevel error"
    // flag ensures that only critical errors are printed, which helps in
    // determining failure.
    std::string cmd =
        "ffmpeg -f lavfi -i nullsrc=s=256x256:r=1 -frames:v 1 -c:v ";
    cmd += encoder_name;
    cmd += " -f null - -loglevel error";

    std::string output;
    run_command_capture_output_utf8(cmd, output);

    if (output.empty()) {
        return true;
    }
    std::string lower_output = output;
    for (char& c : lower_output) {
        c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    }
    if (lower_output.find("error") != std::string::npos ||
        lower_output.find("failed") != std::string::npos ||
        lower_output.find("invalid") != std::string::npos) {
        print_debug_message("Encoder check for '" + encoder_name +
                            "' failed with output:\n" + output);
        return false;
    }
    // Some builds might print non-fatal info. If no explicit error keywords
    // are found, we cautiously treat the encoder as available.
    return true;
#else
    // On non-Windows platforms, we can assume false for now.
    (void)encoder_name;
    return false;
#endif
}

std::string Recorder::get_default_encoder() {
    // Define the encoder priority list
    const std::vector<std::string> encoders_to_check = {
        // 1) H.264
        "h264_nvenc", "h264_qsv", "h264_amf", "libx264", "libopenh264",
        // 2) AV1
        "av1_nvenc", "av1_qsv", "av1_amf", "libsvtav1", "libaom-av1",
        // 3) H.265/HEVC
        "hevc_nvenc", "hevc_qsv", "hevc_amf", "libx265",
        // Final fallback
        "mpeg4"};

    for (const auto& encoder : encoders_to_check) {
        // Check cache first
        {
            std::lock_guard<std::mutex> lock(cache_mutex);
            if (encoder_availability_cache.count(encoder)) {
                if (encoder_availability_cache.at(encoder)) {
                    print_debug_message("Using cached available encoder: " +
                                        encoder);
                    return encoder;  // Found a valid encoder in cache
                }
                continue;  // Encoder is cached as unavailable, try next
            }
        }

        // If not in cache, perform the check
        if (is_encoder_available(encoder)) {
            print_debug_message("Encoder " + encoder + " is available.");
            std::lock_guard<std::mutex> lock(cache_mutex);
            encoder_availability_cache[encoder] = true;
            return encoder;
        } else {
            print_debug_message("Encoder " + encoder + " is not available.");
            std::lock_guard<std::mutex> lock(cache_mutex);
            encoder_availability_cache[encoder] = false;
        }
    }

    print_debug_message(
        "Warning: No suitable FFmpeg encoder found. Defaulting to mpeg4.");
    return "mpeg4";  // Fallback
}

Recorder& get_recorder() {
    static Recorder recorder;
    static const bool registered = (existingRecorder = &recorder, true);
    (void)registered;
    return recorder;
}

void shutdown_recorder() {
    if (existingRecorder)
        existingRecorder->finish_recording();
}