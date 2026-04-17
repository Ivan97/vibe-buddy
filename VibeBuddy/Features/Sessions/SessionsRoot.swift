import SwiftUI

struct SessionsRoot: View {
    @EnvironmentObject private var store: SessionStore

    var body: some View {
        SessionListDetailView(store: store)
    }
}
