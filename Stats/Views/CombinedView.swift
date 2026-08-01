//
//  CombinedView.swift
//  Stats
//
//  Created by Serhiy Mytrovtsiy on 09/01/2023
//  Using Swift 5.0
//  Running on macOS 13.1
//
//  Copyright © 2023 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

internal class CombinedView: NSObject, NSGestureRecognizerDelegate {
    private var menuBarItem: NSStatusItem? = nil
    private var view: NSView = NSView(frame: NSRect(x: 0, y: 0, width: 0, height: Constants.Widget.height))
    private var popup: PopupWindow? = nil
    
    private var status: Bool {
        Store.shared.bool(key: "CombinedModules", defaultValue: false)
    }
    private var spacing: CGFloat {
        CGFloat(Int(Store.shared.string(key: "CombinedModules_spacing", defaultValue: "")) ?? 0)
    }
    private var separator: Bool {
        Store.shared.bool(key: "CombinedModules_separator", defaultValue: false)
    }
    
    private var activeModules: [Module] {
        modules.filter({ $0.enabled }).sorted(by: { $0.combinedPosition < $1.combinedPosition })
    }
    
    private var combinedModulesPopup: Bool {
        get { Store.shared.bool(key: "CombinedModules_popup", defaultValue: true) }
        set { Store.shared.set(key: "CombinedModules_popup", value: newValue) }
    }
    
    override init() {
        super.init()
        
        modules.forEach { (m: Module) in
            m.menuBar.callback = { [weak self] in
                if let s = self?.status, s {
                    DispatchQueue.main.async(execute: {
                        self?.recalculate()
                    })
                }
            }
        }
        
        self.popup = PopupWindow(title: "Combined modules", module: .combined, view: Popup()) { _ in }
        
        if self.status {
            self.enable()
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(listenForOneView), name: .toggleOneView, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(listenForModuleRearrrange), name: .moduleRearrange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(listenCombinedModulesPopup), name: .combinedModulesPopup, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(listenForModule), name: .toggleModule, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: .toggleOneView, object: nil)
        NotificationCenter.default.removeObserver(self, name: .moduleRearrange, object: nil)
        NotificationCenter.default.removeObserver(self, name: .combinedModulesPopup, object: nil)
        NotificationCenter.default.removeObserver(self, name: .toggleModule, object: nil)
    }
    
    public func enable() {
        self.menuBarItem = NSStatusBar.system.statusItem(withLength: 0)
        DispatchQueue.main.async(execute: {
            self.menuBarItem?.autosaveName = "CombinedModules"
        })
        self.menuBarItem?.button?.addSubview(self.view)
        self.menuBarItem?.button?.image = NSImage()
        self.menuBarItem?.button?.toolTip = localizedString("Combined modules")
        
        if !self.combinedModulesPopup {
            self.activeModules.forEach { (m: Module) in
                m.menuBar.widgets.forEach { w in
                    w.item.onClick = {
                        if let window = w.item.window {
                            NotificationCenter.default.post(name: .togglePopup, object: nil, userInfo: [
                                "module": m.name,
                                "widget": w.type,
                                "origin": window.frame.origin,
                                "center": window.frame.width/2
                            ])
                        }
                    }
                }
            }
        } else {
            self.menuBarItem?.button?.target = self
            self.menuBarItem?.button?.action = #selector(self.togglePopup)
            self.menuBarItem?.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
        
        DispatchQueue.main.async(execute: {
            self.recalculate()
        })
    }
    
    public func disable() {
        self.activeModules.forEach { (m: Module) in
            m.menuBar.widgets.forEach { w in
                w.item.onClick = nil
            }
        }
        if let item = self.menuBarItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        self.menuBarItem = nil
    }
    
    private func recalculate() {
        self.view.subviews.forEach({ $0.removeFromSuperview() })

        let visibleModules = self.activeModules.filter({ !$0.menuBar.activeWidgets.isEmpty })
        var w: CGFloat = 0
        visibleModules.enumerated().forEach { (i, m) in
            if i != 0 {
                w += self.spacing
                if self.separator {
                    let separator = NSView(frame: NSRect(x: w, y: 3, width: 1, height: Constants.Widget.height-6))
                    separator.wantsLayer = true
                    separator.layer?.backgroundColor = (separator.isDarkMode ? NSColor.white : NSColor.black).cgColor
                    self.view.addSubview(separator)
                    w += 3 + self.spacing
                }
            }
            self.view.addSubview(m.menuBar.view)
            m.menuBar.view.setFrameOrigin(NSPoint(x: w, y: 0))
            w += m.menuBar.view.frame.width
        }
        self.view.setFrameSize(NSSize(width: w, height: self.view.frame.height))
        self.menuBarItem?.length = w
    }
    
    // call when popup appear/disappear
    private func visibilityCallback(_ state: Bool) {}
    
    @objc private func togglePopup(_ sender: NSButton) {
        guard let popup = self.popup, let item = self.menuBarItem, let window = item.button?.window else { return }
        let openedWindows = NSApplication.shared.windows.filter{ $0 is NSPanel }
        openedWindows.forEach{ $0.setIsVisible(false) }
        
        if popup.occlusionState.rawValue == 8192 {
            NSApplication.shared.activate(ignoringOtherApps: true)
            
            popup.contentView?.invalidateIntrinsicContentSize()
            
            let windowCenter = popup.contentView!.intrinsicContentSize.width / 2
            var x = window.frame.origin.x - windowCenter + window.frame.width/2
            let y = window.frame.origin.y - popup.contentView!.intrinsicContentSize.height - 3
            
            let buttonPoint = NSPoint(x: window.frame.midX, y: window.frame.midY)
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(buttonPoint) }) ?? NSScreen.main {
                if x + popup.contentView!.intrinsicContentSize.width > screen.frame.maxX {
                    x = screen.frame.maxX - popup.contentView!.intrinsicContentSize.width - 3
                }
                if x < screen.frame.minX {
                    x = screen.frame.minX + 3
                }
            }
            
            popup.setFrameOrigin(NSPoint(x: x, y: y))
            popup.setIsVisible(true)
        } else {
            popup.setIsVisible(false)
        }
    }
    
    @objc private func listenForOneView(_ notification: Notification) {
        guard notification.userInfo?["module"] == nil else { return }
        
        if self.status {
            self.enable()
        } else {
            self.disable()
        }
    }
    
    @objc private func listenForModuleRearrrange() {
        self.recalculate()
    }
    
    @objc private func listenCombinedModulesPopup() {
        if !self.combinedModulesPopup {
            self.activeModules.forEach { (m: Module) in
                m.menuBar.widgets.forEach { w in
                    w.item.onClick = {
                        if let window = w.item.window {
                            NotificationCenter.default.post(name: .togglePopup, object: nil, userInfo: [
                                "module": m.name,
                                "widget": w.type,
                                "origin": window.frame.origin,
                                "center": window.frame.width/2
                            ])
                        }
                    }
                }
            }
            self.menuBarItem?.button?.action = nil
        } else {
            self.activeModules.forEach { (m: Module) in
                m.menuBar.widgets.forEach { w in
                    w.item.onClick = nil
                }
            }
            
            self.menuBarItem?.button?.target = self
            self.menuBarItem?.button?.action = #selector(self.togglePopup)
            self.menuBarItem?.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
    }
    
    @objc private func listenForModule(_ notification: Notification) {
        guard let name = notification.userInfo?["module"] as? String,
              let state = notification.userInfo?["state"] as? Bool,
              state,
              let module = self.activeModules.first(where: { $0.name == name }) else { return }
        
        module.menuBar.widgets.forEach { w in
            w.item.onClick = {
                if let window = w.item.window {
                    NotificationCenter.default.post(name: .togglePopup, object: nil, userInfo: [
                        "module": module.name,
                        "widget": w.type,
                        "origin": window.frame.origin,
                        "center": window.frame.width/2
                    ])
                }
            }
        }
    }
}

private class Popup: NSStackView, Popup_p {
    fileprivate var keyboardShortcut: [UInt16] = []
    fileprivate var sizeCallback: ((NSSize) -> Void)? = nil
    
    init() {
        self.keyboardShortcut = Store.shared.array(key: "CombinedModules_popup_keyboardShortcut", defaultValue: []) as? [UInt16] ?? []
        
        super.init(frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 0))
        
        self.orientation = .vertical
        self.distribution = .fill
        self.alignment = .width
        self.spacing = Constants.Popup.spacing*3
        
        self.reinit()
        
        NotificationCenter.default.addObserver(self, selector: #selector(reinit), name: .toggleModule, object: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: .toggleOneView, object: nil)
    }
    
    fileprivate func settings() -> NSView? { return nil }
    fileprivate func appear() {}
    fileprivate func disappear() {}
    fileprivate func setKeyboardShortcut(_ binding: [UInt16]) {
        self.keyboardShortcut = binding
        Store.shared.set(key: "CombinedModules_popup_keyboardShortcut", value: binding)
    }
    
    @objc private func reinit() {
        self.subviews.forEach({ $0.removeFromSuperview() })
        
        let availableModules = modules.filter({ $0.enabled && $0.portal != nil })
        var modulesHeight: CGFloat = 0
        availableModules.forEach { (m: Module) in
            if let p = m.portal {
                modulesHeight += p.height
                self.addArrangedSubview(p)
            }
        }
        
        let h = modulesHeight + (CGFloat(availableModules.count-1)*self.spacing)
        if h > 0 {
            self.setFrameSize(NSSize(width: self.frame.width, height: h))
            self.sizeCallback?(self.frame.size)
        }
    }
}

internal final class TabbedPopup: NSObject {
    private let content: TabbedPopupContent
    private let popup: PopupWindow

    override init() {
        self.content = TabbedPopupContent()
        self.popup = PopupWindow(title: "Dashboard", module: .combined, view: self.content) { _ in }
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(togglePopup),
            name: .togglePopup,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadTabs),
            name: .toggleModule,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func reloadTabs() {
        DispatchQueue.main.async { [weak self] in
            self?.content.reloadModules()
        }
    }

    @objc private func togglePopup(_ notification: Notification) {
        guard let name = notification.userInfo?["module"] as? String,
              let buttonOrigin = notification.userInfo?["origin"] as? CGPoint,
              let buttonCenter = notification.userInfo?["center"] as? CGFloat else {
            return
        }

        self.content.reloadModules()

        let module: Module?
        if name == "Dashboard" || name == "Combined modules" {
            module = self.content.defaultModule
        } else {
            module = modules.first(where: { $0.name == name && $0.enabled && $0.popupContent != nil })
        }
        guard let module else { return }

        if self.popup.isVisible && self.content.selectedModule === module {
            self.popup.setIsVisible(false)
            return
        }

        self.content.select(module)
        self.popup.setPopupTitle(module.name)
        self.showPopup(origin: buttonOrigin, center: buttonCenter)
    }

    private func showPopup(origin: CGPoint, center: CGFloat) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        self.popup.contentView?.invalidateIntrinsicContentSize()
        self.popup.contentView?.layoutSubtreeIfNeeded()

        let size = self.popup.frame.size
        var x = origin.x - size.width/2 + center
        let y = origin.y - size.height - 3

        let buttonPoint = NSPoint(x: origin.x + center, y: origin.y)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(buttonPoint) }) ?? NSScreen.main {
            if x + size.width > screen.frame.maxX {
                x = screen.frame.maxX - size.width - 3
            }
            if x < screen.frame.minX {
                x = screen.frame.minX + 3
            }
        }

        self.popup.setFrameOrigin(NSPoint(x: x, y: y))
        self.popup.setIsVisible(true)
    }
}

private final class TabbedPopupContent: NSStackView, Popup_p {
    fileprivate var keyboardShortcut: [UInt16] = []
    fileprivate var sizeCallback: ((NSSize) -> Void)? = nil

    private let tabs: NSSegmentedControl
    private let contentView: NSView
    private let contentHeight: NSLayoutConstraint
    private var availableModules: [Module] = []
    fileprivate var selectedModule: Module?
    private var isAppeared: Bool = false

    fileprivate var defaultModule: Module? {
        self.availableModules.first
    }

    init() {
        self.tabs = NSSegmentedControl(frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 28))
        self.contentView = NSView(frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 0))
        self.contentHeight = self.contentView.heightAnchor.constraint(equalToConstant: 0)

        super.init(frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 0))

        self.orientation = .vertical
        self.alignment = .width
        self.distribution = .fill
        self.spacing = Constants.Popup.spacing

        self.tabs.trackingMode = .selectOne
        self.tabs.segmentStyle = .rounded
        self.tabs.segmentDistribution = .fillEqually
        self.tabs.controlSize = .small
        self.tabs.target = self
        self.tabs.action = #selector(tabChanged)
        self.tabs.heightAnchor.constraint(equalToConstant: 28).isActive = true

        self.contentView.translatesAutoresizingMaskIntoConstraints = false
        self.contentHeight.isActive = true

        self.addArrangedSubview(self.tabs)
        self.addArrangedSubview(self.contentView)
        self.reloadModules()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    fileprivate func reloadModules() {
        self.availableModules = modules.filter { $0.enabled && $0.popupContent != nil }
        self.tabs.segmentCount = self.availableModules.count
        for (index, module) in self.availableModules.enumerated() {
            if let icon = module.config.icon?.copy() as? NSImage {
                icon.isTemplate = true
                self.tabs.setImage(icon, forSegment: index)
                self.tabs.setToolTip(localizedString(module.name), forSegment: index)
            } else {
                self.tabs.setLabel(localizedString(module.name), forSegment: index)
            }
        }

        if let selected = self.selectedModule,
           let replacement = self.availableModules.first(where: { $0 === selected }) {
            self.select(replacement)
        } else if let first = self.availableModules.first {
            self.select(first)
        } else {
            self.selectedModule = nil
            self.updateContentSize(0)
        }
    }

    fileprivate func select(_ module: Module) {
        guard self.availableModules.contains(where: { $0 === module }),
              let index = self.availableModules.firstIndex(where: { $0 === module }),
              let view = module.popupContent else {
            return
        }

        if let previous = self.selectedModule, previous !== module, self.isAppeared {
            previous.popupContent?.disappear()
        }

        self.selectedModule = module
        self.tabs.selectedSegment = index
        self.contentView.subviews.forEach { $0.removeFromSuperview() }
        view.sizeCallback = { [weak self] size in
            self?.updateContentSize(size.height)
        }
        self.contentView.addSubview(view)
        view.setFrameOrigin(.zero)
        view.setFrameSize(NSSize(width: self.frame.width, height: view.frame.height))
        self.updateContentSize(view.frame.height)

        if self.isAppeared {
            view.appear()
        }
    }

    @objc private func tabChanged() {
        let index = self.tabs.selectedSegment
        guard index >= 0, index < self.availableModules.count else { return }
        self.select(self.availableModules[index])
    }

    private func updateContentSize(_ height: CGFloat) {
        let contentHeight = max(0, height)
        self.contentHeight.constant = contentHeight
        self.contentView.setFrameSize(NSSize(width: self.frame.width, height: contentHeight))
        self.setFrameSize(NSSize(
            width: self.frame.width,
            height: 28 + Constants.Popup.spacing + contentHeight
        ))
        self.sizeCallback?(self.frame.size)
    }

    fileprivate func settings() -> NSView? { nil }

    fileprivate func appear() {
        self.isAppeared = true
        self.selectedModule?.popupContent?.appear()
    }

    fileprivate func disappear() {
        self.isAppeared = false
        self.selectedModule?.popupContent?.disappear()
    }

    fileprivate func setKeyboardShortcut(_ binding: [UInt16]) {
        self.keyboardShortcut = binding
        Store.shared.set(key: "UnifiedPopupTabs_popup_keyboardShortcut", value: binding)
    }
}
