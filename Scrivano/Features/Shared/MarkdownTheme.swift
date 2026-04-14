import SwiftUI
import MarkdownUI

extension Theme {
    static let scrivano = Theme()
        .text {
            ForegroundColor(.init(Color.white.opacity(0.87)))
            FontSize(15)
        }
        .strong {
            ForegroundColor(.init(Color.white))
            FontWeight(.bold)
        }
        .emphasis {
            ForegroundColor(.init(Color.white.opacity(0.75)))
        }
        .strikethrough {
            ForegroundColor(.init(Color.white.opacity(0.38)))
        }
        .link {
            ForegroundColor(.init(Color(hex: "#22d3ee")))
        }
        .heading1 { config in
            config.label
                .markdownMargin(top: .em(1.2), bottom: .em(0.3))
                .markdownTextStyle {
                    FontWeight(.heavy)
                    FontSize(.em(1.75))
                    ForegroundColor(.init(Color.white))
                }
        }
        .heading2 { config in
            config.label
                .markdownMargin(top: .em(1.2), bottom: .em(0.3))
                .markdownTextStyle {
                    FontWeight(.heavy)
                    FontSize(.em(1.35))
                    ForegroundColor(.init(Color.white))
                }
        }
        .heading3 { config in
            config.label
                .markdownMargin(top: .em(1), bottom: .em(0.25))
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(.em(1.1))
                    ForegroundColor(.init(Color.white.opacity(0.9)))
                }
        }
        .heading4 { config in
            config.label
                .markdownMargin(top: .em(0.8), bottom: .em(0.2))
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(.em(0.97))
                    ForegroundColor(.init(Color.white.opacity(0.75)))
                }
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.86))
            ForegroundColor(.init(Color(hex: "#22d3ee")))
            BackgroundColor(.init(Color(hex: "#22d3ee").opacity(0.1)))
        }
        .codeBlock { config in
            config.label
                .markdownMargin(top: .em(0.9), bottom: .em(0.9))
                .padding(14)
                .background(Color(hex: "#070f1e"))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(hex: "#3b82f6").opacity(0.28), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .markdownTextStyle {
                    FontFamilyVariant(.monospaced)
                    FontSize(.em(0.84))
                    ForegroundColor(.init(Color.white.opacity(0.82)))
                }
        }
        .blockquote { config in
            config.label
                .markdownMargin(top: .em(0.7), bottom: .em(0.7))
                .padding(.leading, 14)
                .padding(.vertical, 7)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color(hex: "#22d3ee"))
                        .frame(width: 3)
                }
                .background(Color(hex: "#22d3ee").opacity(0.06))
                .markdownTextStyle {
                    ForegroundColor(.init(Color.white.opacity(0.6)))
                }
        }
        .table { config in
            config.label
                .markdownMargin(top: .em(0.9), bottom: .em(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .tableCell { config in
            config.label
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .markdownTextStyle {
                    FontSize(.em(0.9))
                    ForegroundColor(config.row == 0
                        ? .init(Color.white)
                        : .init(Color.white.opacity(0.85)))
                    if config.row == 0 { FontWeight(.bold) }
                }
                .background(config.row == 0
                    ? Color(hex: "#1a2d4a")
                    : Color(hex: "#081221"))
        }
        .image { config in
            config.label
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .markdownMargin(top: .em(0.6), bottom: .em(0.6))
        }
}
