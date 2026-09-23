import AppKit
import Vision

struct TextBox: Encodable {
    let text: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

let arguments = CommandLine.arguments
if arguments.count == 4, arguments[1] == "click",
   let x = Double(arguments[2]), let y = Double(arguments[3]) {
    let point = CGPoint(x: x, y: y)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
} else if arguments.count == 2 {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .fast
    request.usesLanguageCorrection = false
    try VNImageRequestHandler(url: URL(fileURLWithPath: arguments[1])).perform([request])
    let rows = (request.results ?? []).compactMap { observation -> TextBox? in
        guard let text = observation.topCandidates(1).first?.string else { return nil }
        let rect = observation.boundingBox
        return TextBox(text: text, x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }
    print(String(decoding: try JSONEncoder().encode(rows), as: UTF8.self))
} else { exit(2) }
