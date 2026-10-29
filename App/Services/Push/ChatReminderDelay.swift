import Foundation

enum ChatReminderDelay: TimeInterval, CaseIterable {
    case oneHour = 3600
    case threeHours = 10800
    case sixHours = 21600
    case oneDay = 86400

    var title: LocalizedStringResource {
        switch self {
        case .oneHour: "1 Hour"
        case .threeHours: "3 Hours"
        case .sixHours: "6 Hours"
        case .oneDay: "1 Day"
        }
    }
}
