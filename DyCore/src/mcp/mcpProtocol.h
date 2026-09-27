#pragma once

#include <optional>
#include <string>

#include "json.hpp"

namespace mcp {

// MCP Streamable HTTP JSON-RPC protocol (single message or batch array).
// Methods: initialize, notifications/*, ping, tools/list, tools/call.

struct ProtocolResult {
    int httpStatus = 200;
    // Empty body means 202 Accepted (notification only).
    std::string body;
    std::string sessionId;
    bool hasSessionHeader = false;
};

// sessionIdHeader: Mcp-Session-Id if the client sent one.
ProtocolResult handle_message(const std::string& body,
                              const std::optional<std::string>& sessionIdHeader);

size_t mcp_session_count();
void reset_protocol_state_for_tests();

}  // namespace mcp
