#if DEBUG
import SwiftUI
import Foundation

/// Pure UI fixture: no host, credentials, networking, or persisted drafts.
struct RemoteChatFixture: View {
    static let prompt = "Help me turn these release notes into a clear checklist."
    @State private var draft = ""
    @State private var sent: [String] = []
    @State private var running = ProcessInfo.processInfo.environment["VAMP_REMOTE_FIXTURE"] == "streaming"
    private var detail: RemoteSessionDetail {
        var messages: [[String: Any]] = [
            ["id": "chat-user", "role": "user", "content": Self.prompt, "timestamp": 1],
            ["id": "chat-answer", "role": "assistant", "content": "## A focused release\n\nStart with the changes people will notice.\n\n**1. Check the essentials**\nVerify pairing, models, and the new homepage.\n\n```swift\nlet release = \"Ready for review\"\nprint(release)\n```\n\n**2. Keep it clear**\nDescribe what changed, then test on your iPhone.", "timestamp": 2]
        ]
        if ProcessInfo.processInfo.environment["VAMP_REMOTE_FIXTURE"] == "rich" {
            messages = [
                ["id": "rich-1", "role": "user", "content": "Hey", "timestamp": 1],
                ["id": "rich-2", "role": "assistant", "content": "Hey! How can I help you today?", "timestamp": 2],
                ["id": "rich-3", "role": "user", "content": "Describe this image.  ·  1 image", "timestamp": 3],
                ["id": "rich-4", "role": "notice", "content": "Image sent to LFM3-Omni-2B-Q8_0 as native image input.", "timestamp": 4],
                ["id": "rich-5", "role": "assistant", "content": "This is a **Validation Notes** card with context, blockers, and next steps. The key points are:\n\n- **Keyless sources are bot-blocked.** Reddit answers 403 and DuckDuckGo serves a challenge page.\n- **Collections is the working path.** It reads curated READMEs directly; its first run is the 21:00 scan.\n- **Google still needs setup.** `GOOGLE_API_KEY` and `GOOGLE_CX` are not set.\n  - The key is connected but never verified.\n- **Directory is live** with 200 listings.\n\n> Rechecks run independently of the scanner.\n\n1. Add the search engine ID\n2. Verify one query end to end", "timestamp": 5],
            ]
        }
        if ProcessInfo.processInfo.environment["VAMP_REMOTE_FIXTURE"] == "tools" {
            messages.append(["id": "chat-tool", "role": "toolResult", "toolName": "read_file", "content": "Read the current release notes.\nNo files were changed.", "timestamp": 3])
            messages.append(["id": "chat-reasoning", "role": "reasoning", "content": "I’ll organize the checks around the changes that affect daily use.", "timestamp": 4])
        }
        for (index, text) in sent.enumerated() {
            messages.append(["id": "chat-sent-\(index)", "role": "user", "content": text, "timestamp": index + 10])
        }
        let payload: [String: Any] = ["id": "11111111-1111-1111-1111-111111111111", "title": "Release ideas", "workspace": "Chat", "mode": "chat", "modelID": "Qwen3.5 9B", "messages": messages, "isRunning": running, "phase": running ? "thinking" : "idle", "streamingText": running ? "Let’s check the experience from your iPhone, one step at a time." : ""]
        return try! JSONDecoder().decode(RemoteSessionDetail.self, from: JSONSerialization.data(withJSONObject: payload))
    }

    var body: some View {
        NavigationStack {
            MessageTranscript(detail: detail, onReuseUserMessage: { text in
                if draft.isEmpty { draft = text } else if draft != text { draft += "\n\n" + text }
            })
            .background { RemoteBackdrop(strength: 0.45) }
            .navigationBarTitleDisplayMode(.inline).remoteNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    RemoteConversationTitle(title: ProcessInfo.processInfo.environment["VAMP_REMOTE_FIXTURE"] == "rich" ? "Hey" : "Release ideas") {
                        ConversationStatus(detail: detail, computerName: "Studio Mac")
                    }
                }
            }
            .keyboardDismissToolbar()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                RemoteComposer(draft: $draft, isRunning: running,
                    onSend: send, onQueue: send, onSteer: send, onStop: { running = false },
                    modelName: "Qwen3.5 9B", modeName: "Chat")
            }
        }
    }

    private func send() {
        guard !draft.isEmpty else { return }
        sent.append(draft)
        draft = ""
    }
}
#endif
