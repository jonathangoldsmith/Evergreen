import SwiftUI

extension View {
    /// Coach links and buddy pairing need uploads (BN2). With them off, the
    /// button asks first; only "Allow and share" turns them on and goes ahead.
    func uploadConsentAlert(for action: Binding<(() -> Void)?>, model: AppModel) -> some View {
        alert("Sharing needs uploads", isPresented: Binding(
            get: { action.wrappedValue != nil },
            set: { if !$0 { action.wrappedValue = nil } }
        )) {
            Button("Allow and share") {
                model.allowUploadsForSharing()
                action.wrappedValue?()
                action.wrappedValue = nil
            }
            Button("Cancel", role: .cancel) { action.wrappedValue = nil }
        } message: {
            Text("You chose to keep everything on your phone. To share, I send your changed runs and weeks in range to Evergreen's server under an anonymous ID. You can turn this off in Your data.")
        }
    }
}
