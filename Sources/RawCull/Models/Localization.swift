import Foundation

enum Localization {
    static let bundle: Bundle = {
        #if SWIFT_PACKAGE
        .module
        #else
        .main
        #endif
    }()
}
