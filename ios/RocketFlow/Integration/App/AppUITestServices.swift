import Foundation

actor AppUITestNotificationCenter: UserNotificationCenterServing {
    private var requests: [String: UserNotificationRequestValue] = [:]

    func authorizationState() -> NotificationAuthorizationState { .denied }
    func requestAuthorization() -> Bool { false }
    func pendingIdentifiers() -> Set<String> { Set(requests.keys) }

    func add(_ request: UserNotificationRequestValue) {
        requests[request.identifier] = request
    }

    func remove(identifiers: [String]) {
        for identifier in identifiers { requests.removeValue(forKey: identifier) }
    }
}
