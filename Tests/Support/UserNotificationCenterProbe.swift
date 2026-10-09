import Foundation
import UserNotifications

@testable import CodexPill

final class UserNotificationCenterProbe: @unchecked Sendable, UserNotificationCenterClient {
    var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var requestAuthorizationCallCount = 0
    private(set) var addedRequests: [UNNotificationRequest] = []
    private(set) var notificationCategories: Set<UNNotificationCategory> = []

    func authorizationStatus() async -> UNAuthorizationStatus {
        authorizationStatus
    }

    func requestAuthorization(options _: UNAuthorizationOptions) async throws -> Bool {
        requestAuthorizationCallCount += 1
        authorizationStatus = .authorized
        return true
    }

    func add(_ request: UNNotificationRequest) async throws {
        addedRequests.append(request)
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        notificationCategories = categories
    }
}
