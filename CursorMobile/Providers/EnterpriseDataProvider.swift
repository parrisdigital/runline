import Foundation

@MainActor
protocol EnterpriseDataProvider {
    var enterpriseEndpoints: [CursorAPIEndpoint] { get }

    func fetchEndpoint(_ endpoint: CursorAPIEndpoint) async throws -> CursorAPIEndpointResult
}

enum CursorAPIEndpointCatalog {
    static let endpoints: [CursorAPIEndpoint] = [
        CursorAPIEndpoint(
            area: .cloudAgents,
            title: "Account",
            subtitle: "Validate key and show user metadata.",
            method: .get,
            path: "/v1/me",
            access: .user
        ),
        CursorAPIEndpoint(
            area: .cloudAgents,
            title: "Repositories",
            subtitle: "Repositories from Cursor's GitHub installation.",
            method: .get,
            path: "/v1/repositories",
            access: .user
        ),
        CursorAPIEndpoint(
            area: .cloudAgents,
            title: "Models",
            subtitle: "Available Cloud Agent model IDs.",
            method: .get,
            path: "/v1/models",
            access: .user
        ),
        CursorAPIEndpoint(
            area: .cloudAgents,
            title: "Agents",
            subtitle: "Recent agents, including archived.",
            method: .get,
            path: "/v1/agents",
            queryItems: [
                URLQueryItem(name: "limit", value: "20")
            ],
            access: .user
        ),
        CursorAPIEndpoint(
            area: .admin,
            title: "Team Members",
            subtitle: "Enterprise team member roster.",
            method: .get,
            path: "/teams/members",
            access: .admin
        ),
        CursorAPIEndpoint(
            area: .admin,
            title: "Team Spend",
            subtitle: "Team spend and billing summary.",
            method: .get,
            path: "/teams/spend",
            access: .admin
        ),
        CursorAPIEndpoint(
            area: .admin,
            title: "Daily Usage",
            subtitle: "Hourly-aggregated team usage data.",
            method: .get,
            path: "/teams/daily-usage-data",
            access: .admin
        ),
        CursorAPIEndpoint(
            area: .admin,
            title: "Usage Events",
            subtitle: "Filtered team usage events.",
            method: .get,
            path: "/teams/filtered-usage-events",
            access: .admin
        ),
        CursorAPIEndpoint(
            area: .admin,
            title: "Audit Logs",
            subtitle: "Administrative and security event trail.",
            method: .get,
            path: "/teams/audit-logs",
            access: .admin
        ),
        CursorAPIEndpoint(
            area: .admin,
            title: "Repo Blocklist",
            subtitle: "Configured blocked repositories.",
            method: .get,
            path: "/settings/repo-blocklists/repos",
            access: .admin
        ),
        CursorAPIEndpoint(
            area: .analytics,
            title: "Daily Active Users",
            subtitle: "Team DAU for the last 14 days.",
            method: .get,
            path: "/analytics/team/dau",
            queryItems: [
                URLQueryItem(name: "startDate", value: "14d"),
                URLQueryItem(name: "endDate", value: "today")
            ],
            access: .enterprise
        ),
        CursorAPIEndpoint(
            area: .analytics,
            title: "Model Usage",
            subtitle: "Team model usage distribution.",
            method: .get,
            path: "/analytics/team/models",
            queryItems: [
                URLQueryItem(name: "startDate", value: "30d"),
                URLQueryItem(name: "endDate", value: "today")
            ],
            access: .enterprise
        ),
        CursorAPIEndpoint(
            area: .analytics,
            title: "Leaderboard",
            subtitle: "Team acceptance leaderboard.",
            method: .get,
            path: "/analytics/team/leaderboard",
            queryItems: [
                URLQueryItem(name: "page", value: "1"),
                URLQueryItem(name: "pageSize", value: "10")
            ],
            access: .enterprise
        ),
        CursorAPIEndpoint(
            area: .analytics,
            title: "Conversation Insights",
            subtitle: "Intent, complexity, category, guidance, and work type rollups.",
            method: .get,
            path: "/analytics/team/conversation-insights",
            queryItems: [
                URLQueryItem(name: "startDate", value: "14d"),
                URLQueryItem(name: "endDate", value: "today"),
                URLQueryItem(name: "include", value: "intents,complexity,categories,guidanceLevels,workTypes")
            ],
            access: .enterprise
        ),
        CursorAPIEndpoint(
            area: .analytics,
            title: "Agent Edits By User",
            subtitle: "Per-user Agent edit metrics.",
            method: .get,
            path: "/analytics/by-user/agent-edits",
            queryItems: [
                URLQueryItem(name: "page", value: "1"),
                URLQueryItem(name: "pageSize", value: "25")
            ],
            access: .enterprise
        ),
        CursorAPIEndpoint(
            area: .aiCode,
            title: "AI Code Changes",
            subtitle: "Tracked AI-generated code changes.",
            method: .get,
            path: "/analytics/ai-code/changes",
            queryItems: [
                URLQueryItem(name: "startDate", value: "14d"),
                URLQueryItem(name: "endDate", value: "now"),
                URLQueryItem(name: "page", value: "1"),
                URLQueryItem(name: "pageSize", value: "50")
            ],
            access: .enterprise
        ),
        CursorAPIEndpoint(
            area: .aiCode,
            title: "AI Code Commits",
            subtitle: "Commit-level AI code attribution.",
            method: .get,
            path: "/analytics/ai-code/commits",
            queryItems: [
                URLQueryItem(name: "startDate", value: "7d"),
                URLQueryItem(name: "endDate", value: "now"),
                URLQueryItem(name: "page", value: "1"),
                URLQueryItem(name: "pageSize", value: "50")
            ],
            access: .enterprise
        )
    ]
}
