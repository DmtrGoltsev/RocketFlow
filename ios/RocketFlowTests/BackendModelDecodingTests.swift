import Foundation
import XCTest
@testable import RocketFlow

final class BackendModelDecodingTests: XCTestCase {
    func testDecodesBackendUserFixture() throws {
        let data = Data(
            """
            {
              "id":"11111111-1111-1111-1111-111111111111",
              "email":"user@example.com",
              "displayName":"User",
              "timezone":"Europe/Moscow",
              "language":"ru",
              "createdAt":"2026-08-22T10:11:12.123456Z"
            }
            """.utf8
        )

        let user = try WireJSON.decoder().decode(UserDTO.self, from: data)

        XCTAssertEqual(user.language, .ru)
        XCTAssertEqual(user.timezone, "Europe/Moscow")
    }

    func testTaskMissingPriorityNormalizesToCompatibilityShadow() throws {
        let task = try decodeTask(priorityJSON: "null")

        XCTAssertEqual(task.priorityShadow, 5)
        XCTAssertNil(task.plannedTime)
        XCTAssertEqual(task.tags, [])
    }

    func testTaskUpdatePreservesHistoricalPriorityShadow() throws {
        let task = try decodeTask(priorityJSON: "2")
        let request = UpdateTaskRequestDTO(task: task, tagIds: [], checklistItems: [])
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: WireJSON.encoder().encode(request)) as? [String: Any]
        )

        XCTAssertEqual(object["priority"] as? Int, 2)
    }

    func testTaskCreateAlwaysSendsCanonicalPriorityShadow() throws {
        let request = CreateTaskRequestDTO(
            title: "Task",
            description: nil,
            type: .green,
            effort: 3,
            status: .todo,
            plannedTime: nil,
            dueTime: nil,
            checklistItems: nil,
            tagIds: nil
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: WireJSON.encoder().encode(request)) as? [String: Any]
        )

        XCTAssertEqual(object["priority"] as? Int, 5)
    }

    func testDecodesCalendarFocusSettingsAndDeviceFixtures() throws {
        let calendar = try WireJSON.decoder().decode(
            CalendarMarkersResponseDTO.self,
            from: Data(
                """
                {"timezone":"Europe/Moscow","from":"2026-08-18","toExclusive":"2026-08-25","markers":[{
                  "markerId":"20000000-0000-0000-0000-000000000001",
                  "occurrenceId":"20000000-0000-0000-0000-000000000002",
                  "taskId":"20000000-0000-0000-0000-000000000003",
                  "goalId":null,"title":"Task","status":"todo","effort":2,
                  "kind":"future_kind","at":"2026-08-22T10:00:00Z","localDate":"2026-08-22","recurring":false
                }]}
                """.utf8
            )
        )
        let settings = try WireJSON.decoder().decode(
            UserSettingsDTO.self,
            from: Data(
                """
                {"language":"ru","greenPriorityDecayPolicy":{"taskType":"green","enabled":false,"thresholdPreset":"day","decayAmount":1},"redPriorityDecayPolicy":null,"notificationsEnabled":true,"version":7}
                """.utf8
            )
        )
        let device = try WireJSON.decoder().decode(
            DeviceRegistrationDTO.self,
            from: Data(
                """
                {"id":"30000000-0000-0000-0000-000000000001","platform":"ios","deviceName":null,"active":true,"createdAt":"2026-08-22T10:00:00Z"}
                """.utf8
            )
        )

        XCTAssertEqual(calendar.markers.first?.kind, .planned)
        XCTAssertEqual(settings.greenPriorityDecayPolicy?.enabled, false)
        XCTAssertEqual(device.platform, .ios)
    }

    func testDecodesFocusAndRedactedRelationFixtures() throws {
        let focus = try WireJSON.decoder().decode(
            FocusPeriodDTO.self,
            from: Data(
                """
                {
                  "id":"40000000-0000-0000-0000-000000000001",
                  "weekStart":"2026-08-17","weekEndExclusive":"2026-08-24",
                  "startsAt":"2026-08-16T21:00:00Z","endsAt":"2026-08-23T21:00:00Z",
                  "timezone":"Europe/Moscow","status":"active","version":3,
                  "progress":{"completedWeight":2,"totalWeight":5,"percent":40,"completedCount":1,"totalCount":2},
                  "items":[],"rolloverOffer":null
                }
                """.utf8
            )
        )
        let links = try WireJSON.decoder().decode(
            EntityLinkListResponseDTO.self,
            from: Data(
                """
                {"items":[{
                  "id":"50000000-0000-0000-0000-000000000001",
                  "source":{"type":"task","id":"50000000-0000-0000-0000-000000000002","title":"Task","subtitle":null,"status":"todo","path":"Folder / Goal","archived":false,"accessible":true,"redacted":false},
                  "target":{"type":"note","id":"50000000-0000-0000-0000-000000000003","title":"Unavailable","subtitle":null,"status":null,"path":null,"archived":null,"accessible":false,"redacted":true},
                  "relationType":"related","createdByUserId":null,"createdByName":null,
                  "createdAt":"2026-08-20T10:00:00Z","updatedAt":"2026-08-21T10:00:00Z","version":2
                }]}
                """.utf8
            )
        )

        XCTAssertEqual(focus.progress.percent, 40)
        XCTAssertEqual(links.items.first?.target.redacted, true)
        XCTAssertNil(links.items.first?.target.path)
    }

    func testSettingsMutationUsesBackendRequestPolicyShape() throws {
        let request = UpdateUserSettingsRequestDTO(
            language: .ru,
            greenPriorityDecayPolicy: .init(
                enabled: false,
                thresholdPreset: "day",
                decayAmount: 1
            ),
            redPriorityDecayPolicy: nil,
            notificationsEnabled: true,
            version: 8
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: WireJSON.encoder().encode(request)) as? [String: Any]
        )
        let policy = try XCTUnwrap(object["greenPriorityDecayPolicy"] as? [String: Any])

        XCTAssertEqual(policy["enabled"] as? Bool, false)
        XCTAssertNil(policy["taskType"])
        XCTAssertEqual(object["version"] as? Int, 8)
    }

    private func decodeTask(priorityJSON: String) throws -> TaskDTO {
        try WireJSON.decoder().decode(
            TaskDTO.self,
            from: Data(
                """
                {
                  "id":"10000000-0000-0000-0000-000000000001",
                  "goalId":"10000000-0000-0000-0000-000000000002",
                  "title":"Task","description":"","type":"green","priority":\(priorityJSON),
                  "effort":3,"status":"todo","plannedTime":null,"dueTime":"2026-08-22T10:00:00Z",
                  "archived":false,"shared":false,"fullAccess":true,
                  "creatorUserId":null,"creatorEmail":null,"creatorName":null,"version":4,
                  "tags":[],"checklistItems":[],"recurrence":null,
                  "createdAt":"2026-08-20T10:00:00.123Z","updatedAt":"2026-08-21T10:00:00Z"
                }
                """.utf8
            )
        )
    }
}
