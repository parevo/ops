import SwiftUI

/// Native surface container that tracks light/dark automatically.
public struct SurfaceCard<Content: View>: View {
    private let content: Content
    private let padding: CGFloat

    public init(
        padding: CGFloat = BrandSpacing.large,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.padding = padding
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BrandColor.surface, in: RoundedRectangle(cornerRadius: BrandSpacing.radiusMedium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BrandSpacing.radiusMedium, style: .continuous)
                    .strokeBorder(BrandColor.border.opacity(0.6), lineWidth: 1)
            )
    }
}

/// Backward-compatible alias used by existing call sites during migration.
public typealias GlassCard = SurfaceCard
