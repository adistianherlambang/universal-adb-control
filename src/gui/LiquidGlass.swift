import SwiftUI

// MARK: - Pengaturan Efek Glass (Figma Glass Effect Parameters)
// Anda dapat mengubah langsung angka parameter di bawah ini (skala 0 - 100):
public struct GlassConfig {
    /// 1. REFRACTION (0 - 100): Kekuatan pembiasan & pantulan Fresnel pada sudut kaca
    public static var refraction: Double = 100.0

    /// 2. DEPTH (0 - 100): Ketebalan fisik 3D, elevasi bayangan, dan volume lempengan kaca
    public static var depth: Double = 100.0

    /// 3. FROST (0 - 100): Keburaman permukaan (5 = kristal cair jernih, 100 = buram susu pekat)
    public static var frost: Double = 5.0

    /// 4. DISPERSION (0 - 100): Penguraian spektrum prisma kromatik pelangi pada tepi pembiasan
    public static var dispersion: Double = 100.0

    /// 5. SPLAY (0 - 100): Lebar sebaran pendaran kilau cahaya (specular flare sheen) di permukaan kaca
    public static var splay: Double = 100.0
}

// MARK: - Render Shader Kaca Liquid Glass
public struct LiquidGlassBackground<S: InsettableShape>: View {
    let shape: S
    var isHovered: Bool = false
    var tintColor: Color? = nil

    private var refFactor: Double { max(0, min(100, GlassConfig.refraction)) / 100.0 }
    private var depthFactor: Double { max(0, min(100, GlassConfig.depth)) / 100.0 }
    private var frostFactor: Double { max(0, min(100, GlassConfig.frost)) / 100.0 }
    private var dispFactor: Double { max(0, min(100, GlassConfig.dispersion)) / 100.0 }
    private var splayFactor: Double { max(0, min(100, GlassConfig.splay)) / 100.0 }

    public var body: some View {
        ZStack {
            // 2. DEPTH: Contact Shadow
            if depthFactor > 0 {
                shape
                    .fill(Color.black.opacity(0.35 * depthFactor))
                    .shadow(color: Color.black.opacity(0.40 * depthFactor),
                            radius: 3 * depthFactor,
                            x: 0,
                            y: 2 * depthFactor)

                // 2. DEPTH: Deep Projection Shadow
                shape
                    .fill(Color.clear)
                    .shadow(color: Color.black.opacity((isHovered ? 0.45 : 0.30) * depthFactor),
                            radius: (isHovered ? 24 : 16) * depthFactor,
                            x: 0,
                            y: (isHovered ? 12 : 8) * depthFactor)
            }

            // 3. FROST: Base Fill Translucency (Frost rendah = jernih kristal, Frost tinggi = buram susu)
            if let tint = tintColor {
                shape.fill(
                    LinearGradient(
                        colors: [
                            tint.opacity((isHovered ? 0.70 : 0.55) * (0.6 + 0.4 * frostFactor)),
                            tint.opacity((isHovered ? 0.45 : 0.35) * (0.6 + 0.4 * frostFactor))
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            } else {
                let topAlpha = (isHovered ? 0.16 : 0.10) + (0.50 * frostFactor)
                let btmAlpha = (isHovered ? 0.05 : 0.02) + (0.35 * frostFactor)
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(topAlpha),
                            Color.white.opacity(btmAlpha)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }

            // 2. DEPTH: Internal 3D Volume Gradient
            if depthFactor > 0 {
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.18 * depthFactor),
                            Color.clear,
                            Color.black.opacity(0.25 * depthFactor)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }

            // 5. SPLAY: Specular Flare Sheen
            if splayFactor > 0 {
                let flareRadius = CGFloat(25.0 + 50.0 * splayFactor)
                shape.fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity((isHovered ? 0.42 : 0.28) * splayFactor),
                            Color.white.opacity(0.08 * splayFactor),
                            Color.clear
                        ],
                        center: .top,
                        startRadius: 0,
                        endRadius: flareRadius
                    )
                )
            }

            // 4. DISPERSION: Chromatic Prism Rim (Pelangi pada tepi pembiasan)
            let baseWhite = Color.white.opacity(0.95)
            let cyan = Color(red: 0.45, green: 0.85, blue: 1.0, opacity: 0.80 * dispFactor)
            let violet = Color(red: 0.80, green: 0.60, blue: 1.0, opacity: 0.75 * dispFactor)
            let magenta = Color(red: 1.0, green: 0.55, blue: 0.75, opacity: 0.60 * dispFactor)
            let amber = Color(red: 1.0, green: 0.80, blue: 0.45, opacity: 0.50 * dispFactor)

            shape.strokeBorder(
                LinearGradient(
                    stops: [
                        .init(color: baseWhite, location: 0.0),
                        .init(color: dispFactor > 0.05 ? cyan : baseWhite.opacity(0.6), location: 0.20),
                        .init(color: dispFactor > 0.05 ? violet : baseWhite.opacity(0.4), location: 0.45),
                        .init(color: dispFactor > 0.05 ? magenta : baseWhite.opacity(0.3), location: 0.65),
                        .init(color: dispFactor > 0.05 ? amber : baseWhite.opacity(0.2), location: 0.85),
                        .init(color: Color.white.opacity(0.15), location: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.2
            )

            // 1. REFRACTION: Sharp Inner Caustics Fresnel Rim
            if refFactor > 0 {
                shape
                    .inset(by: 1.2)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity((isHovered ? 0.75 : 0.50) * refFactor),
                                Color.white.opacity(0.10 * refFactor),
                                Color.clear,
                                Color.white.opacity(0.20 * refFactor)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.8 * CGFloat(refFactor)
                    )
            }
        }
    }
}

// MARK: - ViewModifier & Extension
public struct LiquidGlassModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    var isInteractive: Bool = false
    var tintColor: Color? = nil
    @State private var isHovered = false

    public func body(content: Content) -> some View {
        content
            .background(
                LiquidGlassBackground(shape: shape, isHovered: isHovered, tintColor: tintColor)
            )
            .contentShape(shape)
            .onHover { hovering in
                guard isInteractive else { return }
                withAnimation(.smooth(duration: 0.2)) {
                    isHovered = hovering
                }
            }
    }
}

public extension View {
    func liquidGlass<S: InsettableShape>(
        in shape: S,
        interactive: Bool = false,
        tint: Color? = nil
    ) -> some View {
        self.modifier(LiquidGlassModifier(shape: shape, isInteractive: interactive, tintColor: tint))
    }
}
