import Foundation
import Vision
import ImageIO

enum ImageOCRService {
    /// Local diagnostic for the paired inspector's green arrow. Reject
    /// ambiguous candidates; no application text or controls are selected.
    static func navigationCursorAnchor(in data:Data) async ->CGPoint? {
        await Task.detached(priority:.userInitiated) { locateNavigationCursor(in:data) }.value
    }

    private static func locateNavigationCursor(in data:Data)->CGPoint? {
        guard let source=CGImageSourceCreateWithData(data as CFData,nil),
              let image=CGImageSourceCreateImageAtIndex(source,0,nil),image.width<5000,image.height<5000 else { return nil }
        let w=image.width,h=image.height
        var pixels=[UInt8](repeating:0,count:w*h*4)
        let drawn=pixels.withUnsafeMutableBytes { bytes->Bool in
            guard let context=CGContext(data:bytes.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,
                space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue|CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(image,in:CGRect(x:0,y:0,width:w,height:h)); return true
        }
        guard drawn else { return nil }
        var mask=[UInt8](repeating:0,count:w*h)
        for i in 0..<(w*h) {
            let r=Int(pixels[i*4]),g=Int(pixels[i*4+1]),b=Int(pixels[i*4+2])
            if r>100 && r<185 && g-r>25 && g>170 && g<235 && abs(b-r)<25 { mask[i]=1 }
        }
        var candidates=[CGPoint]()
        for i in 0..<(w*h) where mask[i]==1 {
            var queue=[i],head=0,minX=i%w,maxX=i%w,minY=i/w,maxY=i/w
            mask[i]=0
            while head<queue.count {
                let p=queue[head],x=p%w,y=p/w; head+=1
                minX=min(minX,x);maxX=max(maxX,x);minY=min(minY,y);maxY=max(maxY,y)
                for n in [x>0 ? p-1 : -1,x<w-1 ? p+1 : -1,y>0 ? p-w : -1,y<h-1 ? p+w : -1] where n>=0 {
                    if mask[n]==1 { mask[n]=0;queue.append(n) }
                }
            }
            let width=maxX-minX+1,height=maxY-minY+1,ratio=Double(width)/Double(height)
            if queue.count>80 && queue.count<4000 && width>=12 && width<100 && height>=20 && height<140 && ratio>0.5 && ratio<0.85 {
                candidates.append(CGPoint(x:Double(minX)/Double(w),y:Double(minY)/Double(h)))
            }
        }
        return candidates.count==1 ? candidates[0] : nil
    }

    /// When iOS hides its bar, use the full-display key-window geometry
    /// measured while our app was active, only if the fresh portrait capture
    /// still matches it. This locates the device edge, not another app's UI.
    static func measuredBottom(in data: Data, windowSize: CGSize, bottomInset: CGFloat) -> Double? {
        guard windowSize.width > 0, windowSize.height > windowSize.width,
              (12...80).contains(bottomInset),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let horizontalScale = Double(image.width) / windowSize.width
        let verticalScale = Double(image.height) / windowSize.height
        guard (1...6).contains(horizontalScale), abs(horizontalScale - verticalScale) < 0.01 else { return nil }
        let y = (windowSize.height - bottomInset / 2) / windowSize.height
        return (0.95...0.995).contains(y) ? y : nil
    }

    static func homeIndicator(in data: Data) -> HomeIndicatorObservation? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.height > image.width, image.width > 0 else { return nil }
        let width = min(512, image.width)
        let height = Int(Double(image.height) * Double(width) / Double(image.width))
        guard height <= 4096 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? HomeIndicatorRecognizer.locate(pixels: pixels, width: width, height: height) : nil
    }

    static func nativeFrame(in data: Data, recognitionLanguages:[String]? = nil) async throws -> NativeScreenFrame {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                          image.width > 0, image.height > image.width else {
                        throw NativeScreenError.unreadable
                    }
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.usesLanguageCorrection = false
                    if let recognitionLanguages { request.recognitionLanguages=recognitionLanguages }
                    try VNImageRequestHandler(cgImage: image).perform([request])
                    let items = (request.results ?? []).compactMap { result -> NativeScreenText? in
                        guard let candidate = result.topCandidates(1).first, candidate.confidence >= 0.7 else { return nil }
                        let box = result.boundingBox
                        return NativeScreenText(label: candidate.string, x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
                    }.filter(\.valid).sorted { a, b in a.y == b.y ? a.x < b.x : a.y < b.y }
                    continuation.resume(returning: NativeScreenFrame(image: data, items: items))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    static func hasNavigationBanner(in data:Data) async throws -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData,nil),
              let image = CGImageSourceCreateImageAtIndex(source,0,nil),
              let top = image.cropping(to:CGRect(x:0,y:0,width:image.width,height:Int(Double(image.height)*0.12))) else { return false }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage:top).perform([request])
        return (request.results ?? []).contains { $0.topCandidates(1).first?.string == "Tapp navigation" }
    }

    static func recognizeText(in data: Data) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.usesLanguageCorrection = true
                    try VNImageRequestHandler(data: data).perform([request])
                    let text = (request.results ?? [])
                        .compactMap { $0.topCandidates(1).first?.string }
                        .joined(separator: "\n")
                    continuation.resume(returning: text)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
