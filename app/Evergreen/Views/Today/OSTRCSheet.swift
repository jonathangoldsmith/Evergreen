import SwiftUI

/// The four OSTRC questions after "A little" or "Yes" (business notes BN1),
/// then, after "Yes", where it hurts as a plain list (design decision 16).
/// Everything can be skipped; the one-tap answer is already saved.
struct OSTRCSheet: View {
    let week: Date

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var answers: [Int?] = Array(repeating: nil, count: OSTRC.questions.count)
    @State private var bodyPart: String?

    static let bodyParts = ["Foot or ankle", "Lower leg or shin", "Knee", "Thigh", "Hip or groin", "Lower back", "Somewhere else"]

    private var askedWhere: Bool { model.painRecord(for: week)?.answer == .yes }
    private var complete: Bool { answers.allSatisfy { $0 != nil } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("About the past week. Your answers help check that my suggestions fit runners like you.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textMuted)
                }
                ForEach(OSTRC.questions.indices, id: \.self) { index in
                    let question = OSTRC.questions[index]
                    Section {
                        ForEach(question.options.indices, id: \.self) { option in
                            choice(question.options[option], selected: answers[index] == option) { answers[index] = option }
                        }
                    } header: {
                        Text(question.text)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.text)
                            .textCase(nil)
                    }
                }
                if askedWhere {
                    Section {
                        ForEach(Self.bodyParts, id: \.self) { part in
                            choice(part, selected: bodyPart == part) { bodyPart = part }
                        }
                    } header: {
                        Text("Where is it? This stays on your phone.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.text)
                            .textCase(nil)
                    }
                }
                Section {
                    Text("Evergreen suggests training changes. It isn't medical advice; see a physio or doctor for pain or injury.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .navigationTitle("Your week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        model.skipOSTRC()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        model.saveOSTRC(complete ? answers.compactMap(\.self) : nil, bodyPart: bodyPart, week: week)
                        dismiss()
                    }
                    .disabled(!complete && bodyPart == nil)
                }
            }
        }
    }

    private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(Theme.text)
                Spacer()
                if selected {
                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                }
            }
            .contentShape(.rect)
        }
        .frame(minHeight: 44)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
