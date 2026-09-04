import Cocoa

extension AppDelegate {
    func updateMenu(status: AppStatus) {
        let s = strings
        let menu = NSMenu()

        let statusMenuItem = NSMenuItem(title: s.label(for: status), action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        let modelName: String = AppSettings.shared.backend == .local
            ? LocalCorrectionProvider.modelName
            : AppSettings.shared.remoteModelName
        let modelItem = NSMenuItem(title: "\(s.modelPrefix): \(modelName)", action: nil, keyEquivalent: "")
        modelItem.isEnabled = false
        menu.addItem(modelItem)

        menu.addItem(.separator())

        let reviewItem = NSMenuItem(title: s.reviewBeforeApplying, action: #selector(toggleDiffPanel), keyEquivalent: "")
        reviewItem.state = showDiffPanel ? .on : .off
        reviewItem.target = self
        menu.addItem(reviewItem)

        let languageItem = NSMenuItem(title: s.language, action: nil, keyEquivalent: "")
        languageItem.submenu = buildLanguageSubmenu(strings: s)
        menu.addItem(languageItem)

        if !CorrectionHistory.shared.isEmpty {
            menu.addItem(.separator())
            let historyItem = NSMenuItem(title: s.clearHistory, action: #selector(clearCorrectionHistory), keyEquivalent: "")
            historyItem.target = self
            menu.addItem(historyItem)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: s.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        self.statusItem?.menu = menu
    }

    func buildLanguageSubmenu(strings s: Strings) -> NSMenu {
        let submenu = NSMenu(title: s.language)

        let autoItem = NSMenuItem(title: s.autoDetect, action: #selector(selectLanguage(_:)), keyEquivalent: "")
        autoItem.representedObject = nil
        autoItem.state = selectedLanguage == nil ? .on : .off
        autoItem.target = self
        submenu.addItem(autoItem)

        submenu.addItem(.separator())

        for lang in AppDelegate.languages {
            let item = NSMenuItem(title: lang, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.representedObject = lang
            item.state = selectedLanguage == lang ? .on : .off
            item.target = self
            submenu.addItem(item)
        }

        return submenu
    }

    @objc func selectLanguage(_ sender: NSMenuItem) {
        selectedLanguage = sender.representedObject as? String
        updateMenu(status: currentStatus)
    }

    @objc func toggleDiffPanel() {
        showDiffPanel.toggle()
        updateMenu(status: currentStatus)
    }

    @objc func clearCorrectionHistory() {
        CorrectionHistory.shared.clear()
        updateMenu(status: currentStatus)
    }
}
