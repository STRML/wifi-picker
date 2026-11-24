import AppKit
import WifiPickerCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusItemController?
    private var model: PickerModel?
    private var dumper: FrameDumper?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let options = LaunchOptions(arguments: CommandLine.arguments)
        let environment: any PickerEnvironment = options.demo ? DemoEnvironment() : MacWiFiEnvironment()
        let model = PickerModel(environment: environment)
        let dumper = options.dumpFramesPath.map { path -> FrameDumper in
            let dumper = FrameDumper(path: path)
            model.onScanFinished = { dumper.scanFinished() }
            return dumper
        }
        let controller = StatusItemController(model: model, frameDumper: dumper)
        self.model = model
        self.dumper = dumper
        self.controller = controller
        environment.start()
        guard options.openPanel else { return }
        Task {
            try? await Task.sleep(for: .seconds(1))
            controller.open()
        }
    }
}
