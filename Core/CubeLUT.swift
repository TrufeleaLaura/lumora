import Foundation

/// A 3D color lookup table parsed from an Adobe/Resolve `.cube` file.
public struct CubeLUT: Equatable, Sendable {
    public var title: String
    /// Cube edge length (e.g. 33 or 65).
    public var size: Int
    /// RGB triples, red changing fastest, then green, then blue (size³ entries).
    public var values: [Float]
    public var domainMin: (Float, Float, Float)
    public var domainMax: (Float, Float, Float)

    public static func == (lhs: CubeLUT, rhs: CubeLUT) -> Bool {
        lhs.title == rhs.title && lhs.size == rhs.size && lhs.values == rhs.values
            && lhs.domainMin == rhs.domainMin && lhs.domainMax == rhs.domainMax
    }

    public enum ParseError: Error, LocalizedError {
        case missingSize
        case unsupportedSize(Int)
        case wrongValueCount(expected: Int, found: Int)
        case invalidLine(Int)

        public var errorDescription: String? {
            switch self {
            case .missingSize: return "The file has no LUT_3D_SIZE."
            case .unsupportedSize(let size): return "LUT size \(size) isn't supported (2–129)."
            case .wrongValueCount(let expected, let found): return "Expected \(expected) color values, found \(found)."
            case .invalidLine(let line): return "Couldn't read line \(line)."
            }
        }
    }

    public init(title: String, size: Int, values: [Float], domainMin: (Float, Float, Float) = (0, 0, 0), domainMax: (Float, Float, Float) = (1, 1, 1)) {
        self.title = title
        self.size = size
        self.values = values
        self.domainMin = domainMin
        self.domainMax = domainMax
    }

    public static func parse(_ text: String, fallbackTitle: String = "LUT") throws -> CubeLUT {
        var title = fallbackTitle
        var size: Int?
        var domainMin: (Float, Float, Float) = (0, 0, 0)
        var domainMax: (Float, Float, Float) = (1, 1, 1)
        var values: [Float] = []

        for (index, rawLine) in text.split(whereSeparator: \.isNewline).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard let keyword = parts.first else { continue }
            switch keyword.uppercased() {
            case "TITLE":
                title = line.dropFirst(5).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            case "LUT_3D_SIZE":
                guard parts.count >= 2, let value = Int(parts[1]) else { throw ParseError.invalidLine(index + 1) }
                size = value
            case "DOMAIN_MIN":
                guard parts.count >= 4, let r = Float(parts[1]), let g = Float(parts[2]), let b = Float(parts[3]) else { throw ParseError.invalidLine(index + 1) }
                domainMin = (r, g, b)
            case "DOMAIN_MAX":
                guard parts.count >= 4, let r = Float(parts[1]), let g = Float(parts[2]), let b = Float(parts[3]) else { throw ParseError.invalidLine(index + 1) }
                domainMax = (r, g, b)
            case "LUT_1D_SIZE", "LUT_1D_INPUT_RANGE", "LUT_3D_INPUT_RANGE":
                continue
            default:
                guard parts.count >= 3, let r = Float(parts[0]), let g = Float(parts[1]), let b = Float(parts[2]) else {
                    // Unknown keywords are ignored; malformed numbers are errors.
                    if Float(parts[0]) != nil { throw ParseError.invalidLine(index + 1) }
                    continue
                }
                values.append(contentsOf: [r, g, b])
            }
        }

        guard let size else { throw ParseError.missingSize }
        guard (2...129).contains(size) else { throw ParseError.unsupportedSize(size) }
        let expected = size * size * size * 3
        guard values.count == expected else { throw ParseError.wrongValueCount(expected: expected / 3, found: values.count / 3) }
        return CubeLUT(title: title, size: size, values: values, domainMin: domainMin, domainMax: domainMax)
    }

    /// RGBA float data in the layout Core Image's color cube filters expect.
    /// (Input domains other than 0...1 are rare for creative LUTs and are treated as 0...1.)
    public func cubeData() -> [Float] {
        var data = [Float](repeating: 1, count: size * size * size * 4)
        for i in 0..<(size * size * size) {
            data[i * 4] = values[i * 3]
            data[i * 4 + 1] = values[i * 3 + 1]
            data[i * 4 + 2] = values[i * 3 + 2]
        }
        return data
    }

    /// Identity cube of the given size (useful for tests and as a base for generated LUTs).
    public static func identity(size: Int) -> CubeLUT {
        var values: [Float] = []
        values.reserveCapacity(size * size * size * 3)
        let scale = Float(size - 1)
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    values.append(contentsOf: [Float(r) / scale, Float(g) / scale, Float(b) / scale])
                }
            }
        }
        return CubeLUT(title: "Identity", size: size, values: values)
    }
}
