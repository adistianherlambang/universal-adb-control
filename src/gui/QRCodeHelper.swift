import Cocoa
import CoreImage

public enum QRCodeHelper {
    /// Menghasilkan NSImage QR code dengan skala resolusi tajam (pixel-crisp)
    public static func generate(from string: String, size: CGFloat = 160) -> NSImage? {
        guard let data = string.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let ciImage = filter.outputImage else { return nil }

        let scale = size / ciImage.extent.size.width
        let transformed = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }
}
