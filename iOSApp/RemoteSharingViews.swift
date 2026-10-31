import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct RemoteShareSheet: View {
    let store: RemoteStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.remoteAppearance) private var appearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showFileImporter = false
    @State private var downloadedFile: DownloadedRemoteFile?
    @State private var confirmation: String?

    var body: some View {
        NavigationStack {
            RemotePageScroll {
                RemotePageHeading(title: "Clipboard & files", subtitle: "Move work directly between this device and your paired Mac.")
                if !store.isConnected { RemoteReconnectBanner(store: store).clipShape(RoundedRectangle(cornerRadius: 17)) }
                ClipboardSharingSection(store: store, confirmation: $confirmation)
                    .disabled(!store.isConnected)
                FileSharingSection(store: store, onChooseFile: { showFileImporter = true }, onDownload: download)
            }
            .navigationTitle("Share with Mac").navigationBarTitleDisplayMode(.inline)
            .remotePageChrome()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }.vampUtilityAction() }
            .task { await store.loadSharing() }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                Task {
                    if await store.uploadFile(url) { confirmation = "Sent \(url.lastPathComponent) to your Mac." }
                }
            }
            .sheet(item: $downloadedFile) { item in RemoteActivityView(items: [item.url]) }
            .overlay(alignment: .bottom) {
                if let confirmation {
                    Text(confirmation).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 15).padding(.vertical, 10)
                        .background(Color.black.opacity(0.82), in: Capsule())
                        .padding(.bottom, 18).transition(reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity))
                        .task(id: confirmation) {
                            do { try await Task.sleep(for: .seconds(3)) }
                            catch { return }
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { self.confirmation = nil }
                        }
                }
            }
            .refreshable { await store.loadSharing() }
        }
        .remotePageErrors(store: store)
    }

    private func download(_ file: RemoteSharedFileItem) {
        Task {
            if let url = await store.downloadFile(file) {
                downloadedFile = DownloadedRemoteFile(url: url)
            }
        }
    }
}

struct ShareSheetHeader: View {
    @Environment(\.remoteAppearance) private var appearance
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "arrow.left.arrow.right.circle.fill").font(.system(size: 24)).foregroundStyle(BeetTheme.accentBright)
            Text("Clipboard & files").font(RemoteInstrument.TypeStyle.title).tracking(-0.3)
            Text("Clipboard and files travel directly between this device and your paired Mac.")
                .font(.subheadline).foregroundStyle(BeetTheme.secondaryText(appearance)).lineSpacing(2)
        }
    }
}

struct ClipboardSharingSection: View {
    let store: RemoteStore
    @Binding var confirmation: String?
    @Environment(\.remoteAppearance) private var appearance

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        RemotePageSection(title: "Clipboard") {
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))) {
                ShareActionButton(title: "Paste from Mac", symbol: "arrow.down.doc", appearance: appearance) {
                    Task {
                        if let text = await store.copyMacClipboard() {
                            UIPasteboard.general.string = text
                            confirmation = text.isEmpty ? "The Mac clipboard is empty." : "Copied the Mac clipboard to this device."
                        }
                    }
                }
                ShareActionButton(title: "Send to Mac", symbol: "arrow.up.doc", appearance: appearance) {
                    let text = UIPasteboard.general.string ?? ""
                    Task {
                        if text.isEmpty { confirmation = "Copy some text on this device first." }
                        else if await store.sendClipboardToMac(text) { confirmation = "Sent this device’s clipboard to your Mac." }
                    }
                }
            }
        }
    }
}

struct ShareActionButton: View {
    let title: String
    let symbol: String
    let appearance: RemoteAppearance
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.title3.weight(.medium))
                Text(title).font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 8).frame(maxWidth: .infinity, minHeight: 72)
        }
        .buttonStyle(RemotePageButtonStyle())
    }

}

struct FileSharingSection: View {
    let store: RemoteStore
    let onChooseFile: () -> Void
    let onDownload: (RemoteSharedFileItem) -> Void
    @Environment(\.remoteAppearance) private var appearance

    var body: some View {
        RemotePageSection(title: "Shared files", spacing: 12) {
            if store.isSharing { ProgressView("Transferring file").font(.caption) }
            Button(action: onChooseFile) {
                Label("Send a file to Mac", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(RemotePageButtonStyle(primary: true)).disabled(!store.isConnected || store.isSharing)
            if store.sharedFiles.isEmpty {
                Text("Files shared with your Mac appear in Downloads › BeetCode Remote.")
                    .font(.caption).foregroundStyle(RemoteInstrument.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(store.sharedFiles) { file in
                        Button { onDownload(file) } label: { RemoteSharedFileRow(file: file) }
                            .buttonStyle(RemotePageRowButtonStyle()).disabled(!store.isConnected || store.isSharing)
                        if file.id != store.sharedFiles.last?.id { RemotePageDivider().padding(.leading, 52) }
                    }
                }
            }
        }
    }

}

struct RemoteSharedFileRow: View {
    let file: RemoteSharedFileItem
    @Environment(\.remoteAppearance) private var appearance
    var body: some View {
        HStack(spacing: 11) {
            RemotePageSymbol(symbol: "doc")
            VStack(alignment: .leading, spacing: 3) {
                Text(file.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file))
                    .font(.caption).foregroundStyle(BeetTheme.secondaryText(appearance))
            }
            Spacer()
            Image(systemName: "square.and.arrow.down").font(.subheadline.weight(.semibold)).foregroundStyle(BeetTheme.secondaryText(appearance))
        }
        .padding(.vertical, 10).frame(minHeight: 60).contentShape(Rectangle())
    }
}

struct RemoteSectionLabel: View {
    @Environment(\.remoteAppearance) private var appearance
    let title: String
    var body: some View { Text(title).font(.system(.caption2, design: .monospaced, weight: .medium)).tracking(0.9).foregroundStyle(BeetTheme.secondaryText(appearance)) }
}

struct DownloadedRemoteFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct RemoteActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
