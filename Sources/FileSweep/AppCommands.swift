import SwiftUI

private struct WorkspaceFocusKey: FocusedValueKey {
    typealias Value = Workspace
}

extension FocusedValues {
    var workspace: Workspace? {
        get { self[WorkspaceFocusKey.self] }
        set { self[WorkspaceFocusKey.self] = newValue }
    }
}

struct FileSweepCommands: Commands {
    @FocusedValue(\.workspace) private var model
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("扫描文件夹…") { model?.chooseFolder() }.keyboardShortcut("o")
                .disabled(model == nil || model?.isBusy == true)
            Button("打开扫描记录…") { model?.openArchive() }.keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(model == nil || model?.isBusy == true)
            Button("保存当前扫描…") { model?.saveArchive() }.keyboardShortcut("s")
                .disabled(model?.snapshot?.entries.isEmpty != false || model?.isBusy == true)
        }
    }
}
