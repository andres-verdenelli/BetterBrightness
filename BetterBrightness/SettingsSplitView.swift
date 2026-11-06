import AppKit
import SwiftUI

/// Own the native split's sizing so opening the sidebar resizes the detail,
/// rather than temporarily growing the whole SwiftUI navigation container.
struct SettingsSplitView<Sidebar: View, Detail: View>: NSViewControllerRepresentable {
    @Binding var isSidebarVisible: Bool
    let sidebar: Sidebar
    let detail: Detail

    init(
        isSidebarVisible: Binding<Bool>,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) {
        _isSidebarVisible = isSidebarVisible
        self.sidebar = sidebar()
        self.detail = detail()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isSidebarVisible: $isSidebarVisible)
    }

    func makeNSViewController(context: Context) -> Controller {
        let controller = Controller(sidebar: sidebar, detail: detail)
        controller.sidebarItem.isCollapsed = !isSidebarVisible
        context.coordinator.observe(controller.sidebarItem)
        return controller
    }

    func updateNSViewController(_ controller: Controller, context: Context) {
        context.coordinator.isSidebarVisible = $isSidebarVisible
        controller.sidebarHost.rootView = sidebar
        controller.detailHost.rootView = detail
        guard controller.sidebarItem.isCollapsed == isSidebarVisible else { return }

        let animate = context.transaction.animation != nil
            && !context.transaction.disablesAnimations
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if animate {
            NSAnimationContext.runAnimationGroup { animation in
                animation.duration = 0.25
                controller.sidebarItem.animator().isCollapsed = !isSidebarVisible
            }
        } else {
            controller.sidebarItem.isCollapsed = !isSidebarVisible
        }
    }

    static func dismantleNSViewController(_ controller: Controller, coordinator: Coordinator) {
        coordinator.observation = nil
    }

    final class Coordinator {
        var isSidebarVisible: Binding<Bool>
        var observation: NSKeyValueObservation?

        init(isSidebarVisible: Binding<Bool>) {
            self.isSidebarVisible = isSidebarVisible
        }

        func observe(_ item: NSSplitViewItem) {
            observation = item.observe(\.isCollapsed, options: [.new]) { [weak self] item, _ in
                // Native divider/window resizing can also collapse the sidebar.
                DispatchQueue.main.async { [weak self, weak item] in
                    guard let self, let item else { return }
                    let isVisible = !item.isCollapsed
                    guard self.isSidebarVisible.wrappedValue != isVisible else { return }
                    self.isSidebarVisible.wrappedValue = isVisible
                }
            }
        }
    }

    final class Controller: NSSplitViewController {
        let sidebarHost: NSHostingController<Sidebar>
        let detailHost: NSHostingController<Detail>
        let sidebarItem: NSSplitViewItem
        private var didSetInitialWidth = false

        init(sidebar: Sidebar, detail: Detail) {
            sidebarHost = NSHostingController(rootView: sidebar)
            detailHost = NSHostingController(rootView: detail)
            sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarHost)
            super.init(nibName: nil, bundle: nil)

            // Split items own their size; avoid competing hosting-view size constraints.
            sidebarHost.sizingOptions = []
            detailHost.sizingOptions = []
            sidebarItem.minimumThickness = 220
            sidebarItem.maximumThickness = 300
            sidebarItem.holdingPriority = .defaultHigh
            sidebarItem.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
            let detailItem = NSSplitViewItem(viewController: detailHost)
            detailItem.minimumThickness = 400
            addSplitViewItem(sidebarItem)
            addSplitViewItem(detailItem)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidAppear() {
            super.viewDidAppear()
            guard !didSetInitialWidth else { return }
            didSetInitialWidth = true
            if !sidebarItem.isCollapsed { splitView.setPosition(250, ofDividerAt: 0) }
        }
    }
}
