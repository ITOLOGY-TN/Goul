import OSLog

enum Log {
    static let audio = Logger(subsystem: "app.goul.dictation", category: "audio")
    static let speech = Logger(subsystem: "app.goul.dictation", category: "speech")
    static let hotkey = Logger(subsystem: "app.goul.dictation", category: "hotkey")
    static let inject = Logger(subsystem: "app.goul.dictation", category: "inject")
    static let app = Logger(subsystem: "app.goul.dictation", category: "app")
}
