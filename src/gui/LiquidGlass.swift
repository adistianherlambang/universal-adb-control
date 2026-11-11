import SwiftUI

// MARK: - Konfigurasi Liquid Glass macOS 27 (Figma & Native Engine Parameters)
// Anda dapat mengubah langsung angka parameter di bawah ini (skala 0 - 100):
public struct GlassConfig {
    /// 1. REFRACTION (0 - 100): Ketegasan pembiasan & pantulan specular rim pada tepi lensa kaca
    public static var refraction: Double = 100.0

    /// 2. DEPTH (0 - 100): Elevasi fisik 3D dan kedalaman bayangan ambien di bawah lempengan kaca
    public static var depth: Double = 10.0

    /// 3. FROST (0 - 100): Keburaman permukaan (< 20 menggunakan Glass.clear murni khas macOS 27)
    public static var frost: Double = 5.0

    /// 4. DISPERSION (0 - 100): Pendaran prisma kromatik halus pada pantulan tepi pembiasan
    public static var dispersion: Double = 20.0

    /// 5. SPLAY (0 - 100): Lebar sebaran pendaran kilau cahaya (specular flare sheen) di permukaan kaca
    public static var splay: Double = 100.0
}

// MARK: - Render Shader Kaca Liquid Glass macOS 27
public struct LiquidGlassModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    var isInteractive: Bool = false
    var tintColor: Color? = nil
    @State private var isHovered = false

    private var refFactor: Double { max(0, min(100, GlassConfig.refraction)) / 100.0 }
    private var depthFactor: Double { max(0, min(100, GlassConfig.depth)) / 100.0 }
    private var dispFactor: Double { max(0, min(100, GlassConfig.dispersion)) / 100.0 }
    private var splayFactor: Double { max(0, min(100, GlassConfig.splay)) / 100.0 }

    private var nativeGlass: Glass {
        // Frost < 20 menggunakan Glass.clear bawaan macOS 27 untuk transparansi kristal cair murni
        var g: Glass = (GlassConfig.frost < 20.0) ? .clear : .regular
        if let tint = tintColor {
            g = g.tint(tint)
        }
        if isInteractive {
            g = g.interactive()
        }
        return g
    }

    public func body(content: Content) -> some View {
        content
            // 1. HARDWARE-ACCELERATED NATIVE macOS 27 LIQUID GLASS
            .glassEffect(nativeGlass, in: shape)
            // 2. REFRACTION & DISPERSION: Specular Bevel Rim
            .overlay {
                if refFactor > 0 {
                    let rimAlpha = (isHovered ? 0.35 : 0.20) * refFactor
                    if dispFactor > 0.05 {
                        // Dispersi prisma kromatik halus khas optik premium
                        shape.strokeBorder(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(rimAlpha * 1.5), location: 0.0),
                                    .init(color: Color(red: 0.55, green: 0.85, blue: 1.0).opacity(rimAlpha * 0.85 * dispFactor), location: 0.25),
                                    .init(color: Color(red: 0.80, green: 0.65, blue: 1.0).opacity(rimAlpha * 0.75 * dispFactor), location: 0.50),
                                    .init(color: Color(red: 1.0, green: 0.75, blue: 0.50).opacity(rimAlpha * 0.65 * dispFactor), location: 0.75),
                                    .init(color: Color.white.opacity(rimAlpha * 0.35), location: 1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                    } else {
                        shape.strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(rimAlpha * 1.4), Color.white.opacity(rimAlpha * 0.25)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.8
                        )
                    }
                }
            }
            // 3. SPLAY: Specular Flare Sheen
            .overlay {
                if splayFactor > 0 {
                    let flareRadius = CGFloat(20.0 + 45.0 * splayFactor)
                    shape.fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity((isHovered ? 0.18 : 0.10) * splayFactor),
                                Color.white.opacity(0.02 * splayFactor),
                                Color.clear
                            ],
                            center: .top,
                            startRadius: 0,
                            endRadius: flareRadius
                        )
                    )
                    .allowsHitTesting(false)
                }
            }
            // 4. DEPTH: Ambient Elevation Shadow
            .shadow(
                color: Color.black.opacity((isHovered ? 0.25 : 0.15) * depthFactor),
                radius: (isHovered ? 16 : 8) * depthFactor,
                x: 0,
                y: (isHovered ? 8 : 4) * depthFactor
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
