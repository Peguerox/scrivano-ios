import SwiftUI

struct PocketModeExplanationView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Drag indicator
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 36, height: 4)
                    .padding(.top, 12)
                    .padding(.bottom, 28)

                VStack(spacing: 22) {
                    // Icon
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(Color.white.opacity(0.30))

                    // Title
                    Text("Pocket Mode Active")
                        .font(.inter(16, weight: .heavy))
                        .foregroundColor(Color.white.opacity(0.70))

                    // Explanation rows
                    VStack(alignment: .leading, spacing: 14) {
                        explanationRow(
                            icon: "hand.tap",
                            title: "First tap arms the action",
                            detail: "A strong vibration confirms the button is armed. Nothing happens yet."
                        )
                        explanationRow(
                            icon: "hand.tap.fill",
                            title: "Second tap confirms",
                            detail: "Tap again within 6 seconds to pause or stop the recording."
                        )
                        explanationRow(
                            icon: "timer",
                            title: "Inaction cancels",
                            detail: "If you don't tap again, the action is cancelled with a soft vibration and recording continues."
                        )
                    }
                    .padding(.horizontal, 24)

                    Spacer().frame(height: 8)

                    Button {
                        dismiss()
                    } label: {
                        Text("Got it")
                            .font(.inter(14, weight: .heavy))
                            .foregroundColor(Color.white.opacity(0.60))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.06))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
        }
        .presentationDetents([.height(420)])
        .presentationDragIndicator(.hidden)
    }

    private func explanationRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color.white.opacity(0.30))
                .frame(width: 22)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.inter(13, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.55))
                Text(detail)
                    .font(.inter(12))
                    .foregroundColor(Color.white.opacity(0.28))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
