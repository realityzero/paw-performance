import SwiftUI

struct RunnerPickerView: View {
    let packs: [RunnerPack]
    @Binding var selectedID: String

    var body: some View {
        Picker("Runner", selection: $selectedID) {
            ForEach(packs) { pack in
                Text(pack.name).tag(pack.id)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
    }
}
