#include "mcpProtocol.h"

#include <memory>
#include <mutex>
#include <random>
#include <sstream>
#include <unordered_map>

#include "mcpTools.h"

namespace mcp {
namespace {

constexpr const char* kProtocolVersion = "2025-06-18";
constexpr const char* kProtocolVersionFallback = "2025-03-26";
constexpr const char* kServerName = "dynode";
constexpr const char* kServerVersion = "0.1.0";

struct SessionState {
    std::string id;
    bool initialized = false;
    std::string protocolVersion;
    std::string clientName;
};

std::mutex g_sessionMtx;
std::unordered_map<std::string, std::shared_ptr<SessionState>> g_sessions;

std::string make_session_id() {
    static std::mt19937_64 rng{std::random_device{}()};
    std::uniform_int_distribution<uint64_t> dist;
    std::ostringstream os;
    os << std::hex << dist(rng) << dist(rng);
    return os.str();
}

std::string create_session(const std::string& clientName, const std::string& proto) {
    std::lock_guard<std::mutex> lock(g_sessionMtx);
    auto s = std::make_shared<SessionState>();
    s->id = make_session_id();
    s->clientName = clientName;
    s->protocolVersion = proto;
    g_sessions.emplace(s->id, s);
    return s->id;
}

std::shared_ptr<SessionState> get_session(const std::string& id) {
    std::lock_guard<std::mutex> lock(g_sessionMtx);
    auto it = g_sessions.find(id);
    return it == g_sessions.end() ? nullptr : it->second;
}

nlohmann::json rpc_error(const nlohmann::json& id, int code, const std::string& msg) {
    nlohmann::json j;
    j["jsonrpc"] = "2.0";
    j["id"] = id.is_null() ? nlohmann::json(nullptr) : id;
    j["error"] = {{"code", code}, {"message", msg}};
    return j;
}

nlohmann::json rpc_result(const nlohmann::json& id, nlohmann::json result) {
    return nlohmann::json{{"jsonrpc", "2.0"}, {"id", id}, {"result", std::move(result)}};
}

nlohmann::json tools_list_result() {
    nlohmann::json tools = nlohmann::json::array();
    for (const auto& spec : McpToolRegistry::inst().list_tools()) {
        tools.push_back({{"name", spec.name},
                         {"description", spec.description},
                         {"inputSchema", spec.inputSchema}});
    }
    return {{"tools", tools}};
}

// Returns response object, or nullptr for notifications.
nlohmann::json handle_one(const nlohmann::json& msg,
                          const std::optional<std::string>& sessionId,
                          std::string& assignedSession) {
    if (!msg.is_object() || !msg.contains("jsonrpc") || !msg["jsonrpc"].is_string()) {
        return rpc_error(nullptr, -32600, "invalid request");
    }
    const nlohmann::json id = msg.contains("id") ? msg["id"] : nlohmann::json(nullptr);
    const bool isNotification = msg["id"].is_null() || !msg.contains("id");
    const std::string method = msg.value("method", std::string{});

    if (isNotification) {
        if (method == "notifications/initialized") {
            if (sessionId) {
                if (auto s = get_session(*sessionId)) s->initialized = true;
            }
        }
        return nullptr;
    }

    if (method == "initialize") {
        const auto params = msg.value("params", nlohmann::json::object());
        const std::string proto =
            params.value("protocolVersion", std::string(kProtocolVersion));
        const std::string clientName =
            params.value("clientInfo", nlohmann::json::object())
                .value("name", std::string("unknown"));
        const bool fallback = (proto != kProtocolVersion);
        const std::string negotiated =
            fallback ? std::string(kProtocolVersionFallback)
                     : std::string(kProtocolVersion);
        assignedSession = create_session(clientName, negotiated);
        nlohmann::json result;
        result["protocolVersion"] = negotiated;
        result["capabilities"] = {{"tools", {{"listChanged", false}}}};
        result["serverInfo"] = {{"name", kServerName}, {"version", kServerVersion}};
        result["instructions"] =
            "DyNode charting tools. Prefer get_expression_reference before "
            "writing expressions. apply_expression supports dryRun.";
        return rpc_result(id, result);
    }

    if (!sessionId || !get_session(*sessionId)) {
        return rpc_error(id, -32000, "invalid session");
    }

    if (method == "ping") {
        return rpc_result(id, nlohmann::json::object());
    }
    if (method == "tools/list") {
        return rpc_result(id, tools_list_result());
    }
    if (method == "tools/call") {
        const auto params = msg.value("params", nlohmann::json::object());
        const std::string name = params.value("name", std::string{});
        if (name.empty()) {
            return rpc_error(id, -32602, "missing tool name");
        }
        nlohmann::json arguments =
            params.contains("arguments") && params["arguments"].is_object()
                ? params["arguments"]
                : nlohmann::json::object();
        const ToolOutcome outcome = McpToolRegistry::inst().call(name, arguments);
        nlohmann::json text;
        text["type"] = "text";
        text["text"] = outcome.payload.dump(
            -1, ' ', false, nlohmann::json::error_handler_t::replace);
        nlohmann::json content = nlohmann::json::array();
        content.push_back(text);
        nlohmann::json result;
        result["content"] = content;
        result["isError"] = outcome.isError;
        return rpc_result(id, result);
    }

    return rpc_error(id, -32601, "method not found: " + method);
}

}  // namespace

size_t mcp_session_count() {
    std::lock_guard<std::mutex> lock(g_sessionMtx);
    return g_sessions.size();
}

ProtocolResult handle_message(const std::string& body,
                              const std::optional<std::string>& sessionIdHeader) {
    ProtocolResult out;
    nlohmann::json parsed;
    try {
        parsed = nlohmann::json::parse(body.empty() ? "null" : body);
    } catch (...) {
        out.httpStatus = 200;
        out.body = rpc_error(nullptr, -32700, "parse error").dump();
        return out;
    }

    std::string assigned;

    if (parsed.is_array()) {
        nlohmann::json replies = nlohmann::json::array();
        for (const auto& msg : parsed) {
            std::string localAssigned;
            auto one = handle_one(msg, sessionIdHeader, localAssigned);
            if (!localAssigned.empty()) assigned = localAssigned;
            if (!one.is_null()) replies.push_back(one);
        }
        if (replies.empty()) {
            out.httpStatus = 202;
            out.body.clear();
        } else {
            out.httpStatus = 200;
            out.body = replies.dump();
        }
    } else if (parsed.is_object()) {
        auto one = handle_one(parsed, sessionIdHeader, assigned);
        if (one.is_null()) {
            out.httpStatus = 202;
            out.body.clear();
        } else {
            out.httpStatus = 200;
            out.body = one.dump();
        }
    } else {
        out.httpStatus = 200;
        out.body = rpc_error(nullptr, -32600, "invalid request").dump();
    }

    if (!assigned.empty()) {
        out.sessionId = assigned;
        out.hasSessionHeader = true;
    }
    return out;
}

void reset_protocol_state_for_tests() {
    {
        std::lock_guard<std::mutex> lock(g_sessionMtx);
        g_sessions.clear();
    }
    McpToolRegistry::inst().clear();
}

}  // namespace mcp
