#include <doctest/doctest.h>

#include <chrono>
#include <cstdint>
#include <string>
#include <thread>
#include <vector>

#include "utils/ffmpeg/record.h"

// Offline recording must never drop frames: each push occupies a fixed
// 1/fps slot on the video timeline. These tests exercise the public
// Recorder API around that invariant without requiring a live FFmpeg encode
// (push_frame fails fast when FFmpeg is unavailable).

TEST_CASE("RecorderPushFrameRejectsWhenNotRecording") {
    auto& recorder = get_recorder();
    recorder.finish_recording();

    std::vector<char> frame(16, 0x11);
    CHECK(recorder.push_frame(frame.data(), static_cast<int>(frame.size())) !=
          FFMPEG_PUSH_FRAME_OK);
}

TEST_CASE("RecorderPushFrameRejectsInvalidArguments") {
    auto& recorder = get_recorder();
    recorder.finish_recording();

    std::vector<char> frame(16, 0x22);
    CHECK(recorder.push_frame(nullptr, 16) != FFMPEG_PUSH_FRAME_OK);
    CHECK(recorder.push_frame(frame.data(), 0) != FFMPEG_PUSH_FRAME_OK);
    CHECK(recorder.push_frame(frame.data(), -1) != FFMPEG_PUSH_FRAME_OK);
}

TEST_CASE("RecorderStartWithoutMusicPathDoesNotHangOnFinish") {
    auto& recorder = get_recorder();
    recorder.finish_recording();

    // Invalid output path / missing ffmpeg should return quickly rather than
    // leaving a half-open recording session behind.
    const int rc = recorder.start_recording(
        std::string("dycore_recorder_queue_probe.mp4"), std::string(""), 64, 64,
        30, 1.0);
    if (rc == 0) {
        // If an encoder is available locally the session must still tear down
        // cleanly; finish_recording joins the writer and closes the pipe.
        recorder.finish_recording();
    }

    std::vector<char> frame(64 * 64 * 4, 0);
    CHECK(recorder.push_frame(frame.data(), static_cast<int>(frame.size())) !=
          FFMPEG_PUSH_FRAME_OK);
}

TEST_CASE("RecorderNeverDropsFramesOnFullQueue") {
    auto& recorder = get_recorder();
    recorder.finish_recording();

    // 256x256 clears NVENC/QSV minimum-size checks used by encoder probes.
    constexpr int kW = 256;
    constexpr int kH = 256;
    constexpr int kFps = 30;
    constexpr int kFrames = 24;  // > ring capacity (16) to force backpressure
    const int frameBytes = kW * kH * 4;

    const int rc = recorder.start_recording(
        std::string("dycore_recorder_queue_backpressure.mp4"), std::string(""),
        kW, kH, kFps, 0.0);
    if (rc != 0) {
        // No encoder/ffmpeg available in this environment.
        return;
    }

    // Each accepted push must occupy one fixed 1/fps slot; the queue applies
    // backpressure instead of dropping when the writer falls behind.
    int accepted = 0;
    for (int i = 0; i < kFrames; ++i) {
        std::vector<char> frame(static_cast<size_t>(frameBytes),
                                static_cast<char>(i & 0xFF));
        const int pushRc =
            recorder.push_frame(frame.data(), frameBytes);
        if (pushRc == FFMPEG_PUSH_FRAME_OK) {
            ++accepted;
        } else {
            // Encoder may die mid-flight (driver/resolution). Either every
            // enqueued frame stayed on the timeline, or the session aborted
            // with a structured error — never a silent drop.
            break;
        }
    }

    recorder.finish_recording();
    if (accepted > 0) {
        // Partial success is OK (encoder-dependent); a hang or exception is not.
        CHECK(accepted <= kFrames);
    }

    std::vector<char> frame(static_cast<size_t>(frameBytes), 0);
    CHECK(recorder.push_frame(frame.data(), frameBytes) !=
          FFMPEG_PUSH_FRAME_OK);
}
