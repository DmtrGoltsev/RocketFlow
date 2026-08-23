import FirebaseCore
import FirebaseMessaging
import Foundation
import OSLog
import UIKit
import UserNotifications

actor AppFCMRegistrationTokenProvider: FCMRegistrationTokenProviding {
    private var configured = false
    private var configurationDiagnostic: String?
    private var token: String?
    private var continuations: [UUID: AsyncStream<String>.Continuation] = [:]

    func isConfigured() async -> Bool { configured }

    func diagnostic() -> String? { configurationDiagnostic }

    func currentToken() -> String? { token }

    func tokenChanges() -> AsyncStream<String> {
        let id = UUID()
        let stream = AsyncStream<String>.makeStream()
        continuations[id] = stream.continuation
        if let token { stream.continuation.yield(token) }
        stream.continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(id) }
        }
        return stream.stream
    }

    func setConfigured(_ configured: Bool, diagnostic: String? = nil) {
        self.configured = configured
        configurationDiagnostic = configured ? nil : diagnostic
        if !configured { token = nil }
    }

    func update(token: String?) {
        let normalized = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized, !normalized.isEmpty else { return }
        self.token = normalized
        continuations.values.forEach { $0.yield(normalized) }
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }
}

enum AppFirebaseMessagingRuntime {
    static let tokenProvider = AppFCMRegistrationTokenProvider()
    static let missingConfigurationDiagnostic =
        "Push notifications are unavailable: GoogleService-Info.plist is not installed."
}

final class RocketFlowAppDelegate: NSObject, UIApplicationDelegate,
    MessagingDelegate, UNUserNotificationCenterDelegate {

    private let logger = Logger(
        subsystem: "com.rocketflow.companion.ios",
        category: "PushConfiguration"
    )

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
#if DEBUG
        if AppLaunchConfiguration.current().isAuthenticatedUITest {
            Task {
                await AppFirebaseMessagingRuntime.tokenProvider.setConfigured(
                    false,
                    diagnostic: "Push notifications are disabled in UI test mode."
                )
            }
            return true
        }
#endif
        UNUserNotificationCenter.current().delegate = self

        guard
            let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
            let options = FirebaseOptions(contentsOfFile: path)
        else {
            logger.error("GoogleService-Info.plist is absent; push notifications are unavailable.")
            Task {
                await AppFirebaseMessagingRuntime.tokenProvider.setConfigured(
                    false,
                    diagnostic: AppFirebaseMessagingRuntime.missingConfigurationDiagnostic
                )
            }
            return true
        }

        if FirebaseApp.app() == nil { FirebaseApp.configure(options: options) }
        Messaging.messaging().delegate = self
        Task { await AppFirebaseMessagingRuntime.tokenProvider.setConfigured(true) }
        application.registerForRemoteNotifications()
        Messaging.messaging().token { [logger = self.logger] token, error in
            if let error {
                logger.error("FCM token acquisition failed: \(error.localizedDescription, privacy: .public)")
            }
            Task { await AppFirebaseMessagingRuntime.tokenProvider.update(token: token) }
        }
        _ = launchOptions
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
        _ = application
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        _ = application
        logger.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Task { await AppFirebaseMessagingRuntime.tokenProvider.update(token: fcmToken) }
        _ = messaging
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        let data = Self.stringPayload(userInfo)
        let hasNotificationPayload = Self.hasNotificationPayload(userInfo)
        Task { @MainActor in
            let result = await AppExternalEventHub.shared.receiveRemoteData(
                data,
                hasNotificationPayload: hasNotificationPayload
            )
            switch result {
            case .newData: completionHandler(.newData)
            case .noData: completionHandler(.noData)
            case .failed: completionHandler(.failed)
            }
        }
        _ = application
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
        _ = center
        _ = notification
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let explicitURL = (userInfo["deepLink"] as? String).flatMap(URL.init(string:))
        let payloadURL = RemoteNotificationPayloadParser.parse(
            data: Self.stringPayload(userInfo),
            hasNotificationPayload: false
        )?.deepLink
        Self.handOffNotificationTap(
            explicitURL ?? payloadURL,
            navigate: { url in await AppExternalEventHub.shared.receive(url) },
            completionHandler: completionHandler
        )
        _ = center
    }

    static func handOffNotificationTap(
        _ url: URL?,
        navigate: @escaping @MainActor (URL) async -> Void,
        completionHandler: () -> Void
    ) {
        if let url {
            Task { @MainActor in await navigate(url) }
        }
        completionHandler()
    }

    private static func stringPayload(_ userInfo: [AnyHashable: Any]) -> [String: String] {
        userInfo.reduce(into: [:]) { result, entry in
            guard let key = entry.key as? String else { return }
            if let value = entry.value as? String {
                result[key] = value
            } else if let value = entry.value as? NSNumber {
                result[key] = value.stringValue
            }
        }
    }

    private static func hasNotificationPayload(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard let aps = userInfo["aps"] as? [String: Any] else { return false }
        return aps["alert"] != nil
    }
}
