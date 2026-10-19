import AppKit
import SwiftUI

struct KeyboardEventMonitor: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(onKeyDown: onKeyDown)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.start(in: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onKeyDown = onKeyDown
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator {
        var onKeyDown: (NSEvent) -> Bool
        private var monitor: Any?
        private weak var view: NSView?

        init(onKeyDown: @escaping (NSEvent) -> Bool) {
            self.onKeyDown = onKeyDown
        }

        func start(in view: NSView) {
            guard monitor == nil else { return }
            self.view = view
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                // AppKit delivers local event monitors on the main thread.
                let handled = MainActor.assumeIsolated {
                    guard let self, let window = self.view?.window,
                          window.isKeyWindow, event.window === window else { return false }
                    return self.onKeyDown(event)
                }
                return handled ? nil : event
            }
        }

        func stop() {
            guard let monitor else { return }
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
