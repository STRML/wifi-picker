struct LaunchOptions: Equatable {
    var openPanel = false
    var dumpFramesPath: String?

    init(arguments: [String]) {
        openPanel = arguments.contains("--open-panel")
        guard let flag = arguments.firstIndex(of: "--dump-frames") else { return }
        let value = arguments.index(after: flag)
        dumpFramesPath = arguments.indices.contains(value) ? arguments[value] : nil
    }
}
