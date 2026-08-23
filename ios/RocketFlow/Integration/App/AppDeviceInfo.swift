import UIKit

enum AppDeviceInfo {
    @MainActor
    static var name: String { UIDevice.current.name }
}
