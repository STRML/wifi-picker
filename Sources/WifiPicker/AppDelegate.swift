import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusItemController?
    private var model: PickerModel?
    private var dumper: FrameDumper?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let options = LaunchOptions(arguments: CommandLine.arguments)
        let service = WiFiService(demo: options.demo)
        let model = PickerModel(service: service, gate: LocationGate(demo: options.demo))
        if let path = options.dumpFramesPath {
            let dumper = FrameDumper(path: path)
            model.frameSink = { dumper.write(reason: $0, frames: $1) }
            self.dumper = dumper
        }
        let controller = StatusItemController(model: model)
        self.model = model
        self.controller = controller
        service.start()
        guard options.openPanel else { return }
        Task {
            try? await Task.sleep(for: .seconds(1))
            controller.open()
        }
    }
}
