#pragma once

#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include "json.hpp"

// Bridge between MCP worker threads and the GameMaker main thread.
// Producers submit jobs and wait; the GM Step loop drains jobs via take_jobs
// and fulfills them via complete.
namespace mcp {

struct BridgeJob {
    uint64_t requestId = 0;
    std::string kind;
    nlohmann::json payload = nlohmann::json::object();
};

struct BridgeResult {
    bool ok = false;
    nlohmann::json result = nlohmann::json::object();
    std::string error;
};

class McpBridge {
   public:
    static McpBridge& inst();

    // Enqueue a job and wait for the main thread. Returns false on timeout or
    // cancellation; fills outError.
    bool submit(const std::string& kind, const nlohmann::json& payload,
                nlohmann::json& outResult, std::string& outError,
                std::chrono::milliseconds timeout = std::chrono::milliseconds(30000));

    // Non-blocking drain for the GameMaker main thread (Step).
    std::vector<BridgeJob> take_jobs(size_t maxCount = 32);

    // Fulfill a pending job. Unknown / already-completed requestIds are ignored
    // so late GML completions after timeout remain safe.
    void complete(uint64_t requestId, bool ok, const nlohmann::json& result,
                  const std::string& error);

    void cancel_all(const std::string& reason);
    size_t pending_count() const;
    size_t waiter_count() const;

   private:
    struct Pending {
        BridgeJob job;
        bool done = false;
        bool ok = false;
        nlohmann::json result;
        std::string error;
    };

    McpBridge() = default;

    mutable std::mutex mtx;
    std::condition_variable cv;
    std::deque<BridgeJob> outbound;
    std::unordered_map<uint64_t, std::shared_ptr<Pending>> waiters;
    uint64_t nextRequestId = 1;
};

}  // namespace mcp
