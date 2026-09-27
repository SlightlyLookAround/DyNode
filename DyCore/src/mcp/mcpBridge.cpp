#include "mcpBridge.h"

namespace mcp {

McpBridge& McpBridge::inst() {
    static McpBridge inst;
    return inst;
}

bool McpBridge::submit(const std::string& kind, const nlohmann::json& payload,
                       nlohmann::json& outResult, std::string& outError,
                       std::chrono::milliseconds timeout) {
    std::shared_ptr<Pending> pending;
    {
        std::lock_guard<std::mutex> lock(mtx);
        pending = std::make_shared<Pending>();
        pending->job.requestId = nextRequestId++;
        pending->job.kind = kind;
        pending->job.payload = payload;
        waiters.emplace(pending->job.requestId, pending);
        outbound.push_back(pending->job);
    }

    std::unique_lock<std::mutex> lock(mtx);
    const bool got = cv.wait_for(lock, timeout, [&] { return pending->done; });
    if (!got) {
        waiters.erase(pending->job.requestId);
        // Drop the outbound job so a late main-thread take will not execute it.
        std::deque<BridgeJob> kept;
        while (!outbound.empty()) {
            if (outbound.front().requestId != pending->job.requestId) {
                kept.push_back(outbound.front());
            }
            outbound.pop_front();
        }
        outbound = std::move(kept);
        outError = "main thread did not respond";
        return false;
    }
    waiters.erase(pending->job.requestId);
    if (!pending->ok) {
        outError = pending->error.empty() ? "bridge job failed" : pending->error;
        return false;
    }
    outResult = pending->result;
    return true;
}

std::vector<BridgeJob> McpBridge::take_jobs(size_t maxCount) {
    std::lock_guard<std::mutex> lock(mtx);
    std::vector<BridgeJob> jobs;
    while (!outbound.empty() && jobs.size() < maxCount) {
        jobs.push_back(outbound.front());
        outbound.pop_front();
    }
    return jobs;
}

void McpBridge::complete(uint64_t requestId, bool ok, const nlohmann::json& result,
                         const std::string& error) {
    {
        std::lock_guard<std::mutex> lock(mtx);
        auto it = waiters.find(requestId);
        if (it == waiters.end()) {
            return;
        }
        it->second->done = true;
        it->second->ok = ok;
        it->second->result = result;
        it->second->error = error;
        waiters.erase(it);
    }
    cv.notify_all();
}

void McpBridge::cancel_all(const std::string& reason) {
    {
        std::lock_guard<std::mutex> lock(mtx);
        for (auto& [id, pending] : waiters) {
            pending->done = true;
            pending->ok = false;
            pending->error = reason;
        }
        waiters.clear();
        outbound.clear();
    }
    cv.notify_all();
}

size_t McpBridge::pending_count() const {
    std::lock_guard<std::mutex> lock(mtx);
    return outbound.size();
}

size_t McpBridge::waiter_count() const {
    std::lock_guard<std::mutex> lock(mtx);
    return waiters.size();
}

}  // namespace mcp
