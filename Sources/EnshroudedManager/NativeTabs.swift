import SwiftUI

/// Native AppKit tab chrome, including nested tabs.
struct NativeTabs: NSViewRepresentable {
    let pages: [(String, AnyView)]
    func makeNSView(context: Context) -> NSTabView {
        let tabs = NSTabView()
        for (title, content) in pages {
            let item = NSTabViewItem(identifier: title)
            item.label = title
            item.view = NSHostingView(rootView: content)
            tabs.addTabViewItem(item)
        }
        return tabs
    }
    func updateNSView(_ tabs: NSTabView, context: Context) {
        for (item, page) in zip(tabs.tabViewItems, pages) {
            (item.view as? NSHostingView<AnyView>)?.rootView = page.1
        }
    }
}

struct ManagementWindowTitle: NSViewRepresentable {
    let name: String
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { view.window?.title = name + " — Server Management" }
    }
}
