// Reproducible, original vector artwork rendered to the asset catalog. No downloaded assets.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 2 else { fatalError("Pass the output PNG path.") }
let size = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                              bytesPerRow: size * 4, space: colorSpace,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("No drawing context") }
context.setFillColor(CGColor(red: 0.15, green: 0.36, blue: 0.92, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
// A four-point compass spark, drawn from curves rather than a font glyph.
let spark = CGMutablePath()
spark.move(to: CGPoint(x: 512, y: 790))
spark.addCurve(to: CGPoint(x: 790, y: 512), control1: CGPoint(x: 551, y: 576), control2: CGPoint(x: 576, y: 551))
spark.addCurve(to: CGPoint(x: 512, y: 234), control1: CGPoint(x: 576, y: 473), control2: CGPoint(x: 551, y: 448))
spark.addCurve(to: CGPoint(x: 234, y: 512), control1: CGPoint(x: 473, y: 448), control2: CGPoint(x: 448, y: 473))
spark.addCurve(to: CGPoint(x: 512, y: 790), control1: CGPoint(x: 448, y: 551), control2: CGPoint(x: 473, y: 576))
spark.closeSubpath()
context.setFillColor(CGColor(gray: 1, alpha: 1))
context.addPath(spark)
context.fillPath()
guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL,
                                                       UTType.png.identifier as CFString, 1, nil) else { fatalError("Cannot encode icon") }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Cannot save icon") }
