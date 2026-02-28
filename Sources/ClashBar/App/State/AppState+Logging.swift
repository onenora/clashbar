import Foundation

@MainActor
extension AppState {
    func ensureLogFileExists() {
        appLogStore?.ensureLogFileExists()
    }

    func persistLogToFile(level: String, message: String) {
        appLogStore?.append(level: level, message: message)
    }

    func appendLog(level: String, message: String) {
        let safeMessage = LogSanitizer.redact(message)
        errorLogs.insert(AppErrorLogEntry(level: level, message: safeMessage), at: 0)
        persistLogToFile(level: level, message: safeMessage)
        let maxEntries = isPanelPresented ? maxLogEntries : hiddenPanelMaxInMemoryLogEntries
        if errorLogs.count > maxEntries {
            errorLogs.removeLast(errorLogs.count - maxEntries)
        }
    }

    func trimInMemoryLogsForCurrentVisibility() {
        let maxEntries = isPanelPresented ? maxLogEntries : hiddenPanelMaxInMemoryLogEntries
        guard errorLogs.count > maxEntries else { return }
        errorLogs.removeLast(errorLogs.count - maxEntries)
    }

    func tr(_ key: String) -> String {
        L10n.t(key, language: uiLanguage)
    }

    func tr(_ key: String, _ args: CVarArg...) -> String {
        L10n.t(key, language: uiLanguage, args: args)
    }

}
