import SwiftUI

enum TextViewerType { case text, note }

struct TextViewerView: View {
    let file: TextFile
    let type: TextViewerType
    @Environment(\.dismiss) var dismiss
    @State private var showMenu = false
    @State private var showPrompts = false

    var accentColor: Color { type == .text ? .stageText : .stageNotes }
    var title: String { type == .text ? "Transcript" : "Note" }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.phoneBg.ignoresSafeArea()

            VStack(spacing: 0) {
                SubScreenBar(
                    title: title,
                    accentColor: accentColor,
                    onBack: { dismiss() },
                    trailingIcon: "···",
                    onTrailing: { showMenu.toggle() }
                )
                .overlay(alignment: .bottom) {
                    Rectangle().fill(accentColor.opacity(0.4)).frame(height: 1)
                }

                // File info
                HStack(spacing: 12) {
                    Image(systemName: type == .text ? "doc.text.fill" : "note.text")
                        .foregroundColor(accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.name).font(.inter(13, weight: .bold)).foregroundColor(.textPrimary)
                        Text("\(file.size) · \(file.createdAt.prefix(10))")
                            .font(.inter(11)).foregroundColor(.textQuaternary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.03))
                .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1) }

                // Content
                ScrollView(showsIndicators: false) {
                    Text(file.content ?? "No content available.")
                        .font(.inter(14))
                        .foregroundColor(.textSecondary)
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                }
            }

            // Context bubble menu
            if showMenu {
                VStack(spacing: 0) {
                    contextBubble
                }
                .padding(.top, 58)
                .padding(.trailing, 14)
            }
        }
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: $showPrompts) {
            PromptsView(context: .applyToText(transcriptTexts: [file.content ?? ""], itemId: "", transcriptIds: []))
        }
    }

    private var contextBubble: some View {
        VStack(spacing: 0) {
            bubbleRow(icon: "square.and.arrow.up", color: .brandCyan, title: "Share") { showMenu = false }
            Divider().background(Color.white.opacity(0.07))
            bubbleRow(icon: "sparkles", color: Color(hex: "#a78bfa"), title: "Apply Prompt") {
                showMenu = false; showPrompts = true
            }
            Divider().background(Color.white.opacity(0.07))
            bubbleRow(icon: "trash.fill", color: .danger, title: "Delete File", isDanger: true) { showMenu = false }
        }
        .background(Color.sheetBg)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.1), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
        .frame(width: 180)
    }

    private func bubbleRow(icon: String, color: Color, title: String, isDanger: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 22)
                Text(title)
                    .font(.inter(13, weight: .semibold))
                    .foregroundColor(isDanger ? .danger : .textPrimary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
    }
}
