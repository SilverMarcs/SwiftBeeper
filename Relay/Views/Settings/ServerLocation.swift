enum ServerLocation: String, CaseIterable, Identifiable {
    case onDevice
    case remote

    var id: Self { self }

    var title: String {
        switch self {
        case .onDevice:
            "On This Device"
        case .remote:
            "Remote Server"
        }
    }
}
