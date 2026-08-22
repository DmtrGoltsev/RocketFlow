import Foundation

enum AuthEndpoints {
    static func login(_ request: LoginRequestDTO) throws -> Endpoint<AuthResponseDTO> {
        try Endpoint(method: .post, path: ["auth", "login"], body: request, requiresAuthorization: false)
    }

    static func register(_ request: RegisterRequestDTO) throws -> Endpoint<AuthResponseDTO> {
        try Endpoint(method: .post, path: ["auth", "register"], body: request, requiresAuthorization: false)
    }

    static func refresh(_ request: RefreshRequestDTO) throws -> Endpoint<RefreshResponseDTO> {
        try Endpoint(method: .post, path: ["auth", "refresh"], body: request, requiresAuthorization: false)
    }

    static func logout(_ request: LogoutRequestDTO) throws -> Endpoint<EmptyResponse> {
        try Endpoint(method: .post, path: ["auth", "logout"], body: request, requiresAuthorization: false)
    }

    static let me = Endpoint<UserDTO>(method: .get, path: ["me"])
}

enum PlanningEndpoints {
    static let folders = Endpoint<FolderListResponseDTO>(method: .get, path: ["folders"])

    static func goals(folderID: UUID) -> Endpoint<GoalListResponseDTO> {
        Endpoint(method: .get, path: ["folders", folderID.uuidString.lowercased(), "goals"])
    }

    static func tasks(goalID: UUID) -> Endpoint<TaskListResponseDTO> {
        Endpoint(method: .get, path: ["goals", goalID.uuidString.lowercased(), "tasks"])
    }

    static func ideas(folderID: UUID) -> Endpoint<IdeaListResponseDTO> {
        Endpoint(method: .get, path: ["folders", folderID.uuidString.lowercased(), "ideas"])
    }

    static func notes(folderID: UUID) -> Endpoint<NoteListResponseDTO> {
        Endpoint(method: .get, path: ["folders", folderID.uuidString.lowercased(), "notes"])
    }

    static func links(type: LinkedEntityType, id: UUID) -> Endpoint<EntityLinkListResponseDTO> {
        Endpoint(
            method: .get,
            path: ["entity-links"],
            queryItems: [
                URLQueryItem(name: "entityType", value: type.rawValue),
                URLQueryItem(name: "entityId", value: id.uuidString.lowercased())
            ]
        )
    }
}

enum CalendarEndpoints {
    static func markers(from: LocalDate, toExclusive: LocalDate) -> Endpoint<CalendarMarkersResponseDTO> {
        Endpoint(
            method: .get,
            path: ["calendar"],
            queryItems: [
                URLQueryItem(name: "from", value: from.rawValue),
                URLQueryItem(name: "toExclusive", value: toExclusive.rawValue)
            ]
        )
    }
}

enum FocusEndpoints {
    static let current = Endpoint<FocusPeriodDTO>(method: .get, path: ["focus", "current"])
    static let settings = Endpoint<FocusNotificationSettingsDTO>(
        method: .get,
        path: ["focus", "notification-settings"]
    )

    static func candidates(
        query: String?,
        folderID: UUID?,
        goalID: UUID?,
        cursor: String?,
        limit: Int
    ) -> Endpoint<FocusCandidateListResponseDTO> {
        let values: [(String, String?)] = [
            ("q", query),
            ("folderId", folderID?.uuidString.lowercased()),
            ("goalId", goalID?.uuidString.lowercased()),
            ("cursor", cursor),
            ("limit", String(limit))
        ]
        return Endpoint(
            method: .get,
            path: ["focus", "candidates"],
            queryItems: values.compactMap { name, value in
                value.map { URLQueryItem(name: name, value: $0) }
            }
        )
    }
}

enum SettingsEndpoints {
    static let current = Endpoint<UserSettingsDTO>(method: .get, path: ["me", "settings"])
}
