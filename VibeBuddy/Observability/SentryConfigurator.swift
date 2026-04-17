import Foundation
import Sentry

enum SentryConfigurator {
    static func start() {
        let dsn = resolveDSN()

        guard let dsn, !dsn.isEmpty else {
            #if DEBUG
            print("[Sentry] DSN not configured — skipping initialization.")
            #endif
            return
        }

        SentrySDK.start { options in
            options.dsn = dsn
            options.debug = false
            options.attachStacktrace = true
            options.tracesSampleRate = 0.2
            options.releaseName = Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String
            #if DEBUG
            options.environment = "debug"
            #else
            options.environment = "release"
            #endif
        }
    }

    private static func resolveDSN() -> String? {
        if let env = ProcessInfo.processInfo.environment["SENTRY_DSN"], !env.isEmpty {
            return env
        }
        return Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String
    }
}
