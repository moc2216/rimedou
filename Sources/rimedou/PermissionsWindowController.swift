import AppKit
import RimeDouCore

@MainActor
protocol PermissionsWindowControllerDelegate: AnyObject {
    func permissionsWindowControllerDidBecomeReady(_ controller: PermissionsWindowController)
}

@MainActor
final class PermissionsWindowController: NSWindowController {
    weak var delegate: PermissionsWindowControllerDelegate?

    private let reportProvider: () -> PermissionReport
    private let onClose: () -> Void
    private var timer: Timer?

    private var accessibilityStatusLabel: NSTextField?
    private var inputMonitoringStatusLabel: NSTextField?
    private var enableButton: NSButton?

    init(reportProvider: @escaping () -> PermissionReport,
         onClose: @escaping () -> Void = {}) {
        self.reportProvider = reportProvider
        self.onClose = onClose
        super.init(window: nil)
        setupWindow()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 260),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "rimedou Permissions"
        window.contentView = buildContentView()
        self.window = window
    }

    private func buildContentView() -> NSView {
        let rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 16
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        let titleLabel = NSTextField(labelWithString: "rimedou needs permissions")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 16)
        rootStack.addArrangedSubview(titleLabel)

        let messageLabel = NSTextField(wrappingLabelWithString: PermissionReport(accessibilityGranted: false, inputMonitoringGranted: false).message)
        messageLabel.textColor = .secondaryLabelColor
        rootStack.addArrangedSubview(messageLabel)

        let rowsStack = NSStackView()
        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 12
        rootStack.addArrangedSubview(rowsStack)

        let accessibilityRow = makePermissionRow(
            kind: .accessibility,
            statusLabel: &accessibilityStatusLabel
        )
        rowsStack.addArrangedSubview(accessibilityRow)

        let inputMonitoringRow = makePermissionRow(
            kind: .inputMonitoring,
            statusLabel: &inputMonitoringStatusLabel
        )
        rowsStack.addArrangedSubview(inputMonitoringRow)

        let enableButton = NSButton(title: "Enable rimedou", target: self, action: #selector(enableTapped))
        enableButton.isHidden = true
        enableButton.bezelStyle = .rounded
        enableButton.setButtonType(.momentaryPushIn)
        enableButton.keyEquivalent = "\r"
        self.enableButton = enableButton
        rootStack.addArrangedSubview(enableButton)

        let noteLabel = NSTextField(wrappingLabelWithString: "After granting permissions in System Settings, return here and click Enable rimedou.")
        noteLabel.textColor = .secondaryLabelColor
        noteLabel.font = NSFont.systemFont(ofSize: 11)
        rootStack.addArrangedSubview(noteLabel)

        return rootStack
    }

    private func makePermissionRow(
        kind: PermissionKind,
        statusLabel: inout NSTextField?
    ) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12

        let nameLabel = NSTextField(labelWithString: kind.displayName)
        nameLabel.font = NSFont.systemFont(ofSize: 13)
        row.addArrangedSubview(nameLabel)

        let status = NSTextField(labelWithString: "Checking…")
        status.font = NSFont.systemFont(ofSize: 13)
        status.textColor = .secondaryLabelColor
        statusLabel = status
        row.addArrangedSubview(status)

        row.addArrangedSubview(NSView())

        let openButton = NSButton(title: "Open System Settings", target: self, action: #selector(openSettings(_:)))
        openButton.bezelStyle = .rounded
        openButton.setButtonType(.momentaryPushIn)
        openButton.tag = PermissionKind.allCases.firstIndex(of: kind) ?? 0
        row.addArrangedSubview(openButton)

        return row
    }

    func bringToFront() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        startPolling()
        updateStatus()
    }

    override func close() {
        timer?.invalidate()
        timer = nil
        onClose()
        super.close()
    }

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            timeInterval: 1.0,
            target: self,
            selector: #selector(updateStatus),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func updateStatus() {
        let report = reportProvider()
        accessibilityStatusLabel?.stringValue = report.accessibilityGranted ? "Granted" : "Not Granted"
        inputMonitoringStatusLabel?.stringValue = report.inputMonitoringGranted ? "Granted" : "Not Granted"

        let ready = report.isReady
        enableButton?.isHidden = !ready
    }

    @objc private func openSettings(_ sender: NSButton?) {
        let index = sender?.tag ?? 0
        let cases = PermissionKind.allCases
        guard index >= 0, index < cases.count else { return }
        NSWorkspace.shared.open(cases[index].settingsURL)
    }

    @objc private func enableTapped() {
        let report = reportProvider()
        guard report.isReady else { return }
        timer?.invalidate()
        timer = nil
        delegate?.permissionsWindowControllerDidBecomeReady(self)
    }
}
