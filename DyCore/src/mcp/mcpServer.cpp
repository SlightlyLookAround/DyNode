#include "mcpServer.h"

#include <httplib/httplib.h>

#include <atomic>
#include <fstream>
#include <iomanip>
#include <random>
#include <sstream>
#include <thread>

#include "mcpBridge.h"
#include "mcpProtocol.h"
#include "mcpTools.h"

namespace mcp {
namespace {

std::string generate_token() {
    static std::mt19937_64 rng{std::random_device{}()};
    std::uniform_int_distribution<uint64_t> dist;
    std::ostringstream os;
    os << std::hex << std::setfill('0')
       << std::setw(16) << dist(rng) << std::setw(16) << dist(rng);
    return os.str();
}

}  // namespace

struct McpServer::Impl {
    std::unique_ptr<httplib::Server> server;
    std::thread thread;
    std::atomic<bool> running{false};
    std::string host = "127.0.0.1";
    int port = 0;
    std::string token;
    bool requireToken = true;
};

McpServer& McpServer::inst() {
    static McpServer instance;
    return instance;
}

McpServer::~McpServer() {
    stop();
}

bool McpServer::is_running() const {
    std::lock_guard<std::recursive_mutex> lock(mtx);
    return impl && impl->running.load();
}

nlohmann::json McpServer::info() const {
    std::lock_guard<std::recursive_mutex> lock(mtx);
    if (!impl) {
        return nlohmann::json{{"running", false},
                              {"url", ""},
                              {"host", "127.0.0.1"},
                              {"port", 0},
                              {"token", ""}};
    }
    return nlohmann::json{
        {"running", impl->running.load()},
        {"url", "http://" + impl->host + ":" + std::to_string(impl->port) + "/mcp"},
        {"host", impl->host},
        {"port", impl->port},
        {"token", impl->token},
        {"sessions", mcp_session_count()},
    };
}

nlohmann::json McpServer::start() {
    return start(Config{});
}

nlohmann::json McpServer::start(const Config& config) {
    register_default_tools();
    std::lock_guard<std::recursive_mutex> lock(mtx);
    if (impl && impl->running.load()) {
        auto runningInfo = info();
        runningInfo["ok"] = true;
        return runningInfo;
    }

    auto next = std::make_unique<Impl>();
    next->requireToken = config.requireToken;
    next->token = (!config.token.empty() || !config.requireToken)
                      ? config.token
                      : generate_token();
    next->server = std::make_unique<httplib::Server>();

    Impl* raw = next.get();
    auto& srv = *next->server;
    const std::string expectedAuth =
        next->requireToken ? ("Bearer " + next->token) : std::string{};

    srv.Post("/mcp", [raw, expectedAuth](const httplib::Request& req,
                                         httplib::Response& res) {
        if (raw->requireToken) {
            const auto auth = req.get_header_value("Authorization");
            if (auth != expectedAuth) {
                res.status = 401;
                res.set_content(R"({"ok":false,"error":"unauthorized"})",
                                "application/json");
                return;
            }
        }
        std::optional<std::string> sessionId;
        const auto sid = req.get_header_value("Mcp-Session-Id");
        if (!sid.empty()) {
            sessionId = sid;
        }
        auto result = handle_message(req.body, sessionId);
        if (result.hasSessionHeader && !result.sessionId.empty()) {
            res.set_header("Mcp-Session-Id", result.sessionId);
        }
        res.status = result.httpStatus;
        res.set_content(result.body, "application/json");
    });

    srv.Get("/health", [raw, expectedAuth](const httplib::Request& req,
                                           httplib::Response& res) {
        if (raw->requireToken) {
            const auto auth = req.get_header_value("Authorization");
            if (auth != expectedAuth) {
                res.status = 401;
                res.set_content(R"({"ok":false,"error":"unauthorized"})",
                                "application/json");
                return;
            }
        }
        res.set_content(R"({"ok":true,"service":"dynode-mcp"})", "application/json");
    });

    const int maxPort =
        config.preferredPort + std::max(0, config.portFallbackCount) - 1;
    int bound = 0;
    for (int port = config.preferredPort; port <= maxPort; ++port) {
        if (srv.bind_to_port("127.0.0.1", port)) {
            bound = port;
            break;
        }
    }
    if (bound == 0) {
        return nlohmann::json{{"ok", false},
                              {"error", "failed to bind 127.0.0.1 in port range"},
                              {"preferredPort", config.preferredPort}};
    }

    next->port = bound;
    next->running = true;
    next->thread = std::thread([raw]() {
        raw->server->listen_after_bind();
        raw->running = false;
    });

    impl = std::move(next);
    auto started = info();
    started["ok"] = true;
    // Persist connection info for external tooling / debugging.
    try {
        std::ofstream out(std::filesystem::current_path() / "mcp_info.json", std::ios::trunc);
        out << started.dump(2);
    } catch (...) {
    }
    return started;
}

nlohmann::json McpServer::stop() {
    std::unique_ptr<Impl> local;
    {
        std::lock_guard<std::recursive_mutex> lock(mtx);
        if (!impl) {
            return nlohmann::json{{"ok", true}, {"running", false}};
        }
        local = std::move(impl);
    }

    if (local->server) {
        local->server->stop();
    }
    if (local->thread.joinable()) {
        local->thread.join();
    }
    McpBridge::inst().cancel_all("mcp server stopped");
    return nlohmann::json{{"ok", true}, {"running", false}};
}

}  // namespace mcp
