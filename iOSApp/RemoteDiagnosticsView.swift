import SwiftUI

struct RemoteDiagnosticsView: View {
    let store: RemoteStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            RemotePageScroll {
                RemotePageHeading(title: "Connection details", subtitle: "Check your Mac’s status and share a private diagnostic report.")
                RemotePageSection(title: "Connection", spacing: 14) {
                    LabeledContent("Status", value: store.isConnected ? "Connected" : "Disconnected")
                    LabeledContent("Mac version", value: store.hostStatus?.appVersion ?? "Not reported")
                    LabeledContent("Mac build", value: store.hostStatus?.appBuild ?? "Not reported")
                    LabeledContent("Protocol", value: store.hostStatus?.protocolVersion.map(String.init) ?? "Legacy")
                    if let last = store.lastConnectedAt {
                        LabeledContent("Last connected") { Text(last, style: .relative) }
                    }
                    Button("Check connection") { Task { await store.connectSaved() } }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(RemotePageButtonStyle())
                        .disabled(store.isConnecting || !store.hasSavedConnection)
                }
                RemotePageSection(title: "Report", spacing: 12) {
                    ShareLink(item: store.connectionDiagnostics) {
                        Label("Share diagnostics", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(RemotePageButtonStyle())
                    Text("The report excludes addresses, access tokens, computer names, files, and conversation text.")
                        .font(.caption).foregroundStyle(RemoteInstrument.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .navigationTitle("Diagnostics")
            .remotePageChrome()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }.vampUtilityAction() }
        }
    }
}
