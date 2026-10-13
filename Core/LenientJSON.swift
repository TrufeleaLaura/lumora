import Foundation

/// Decodes JSON written by older app versions: keys missing from the file are filled in
/// from a default value, so adding new settings never breaks saved projects or presets.
public enum LenientJSON {
    /// - Parameter elementDefaults: templates for the elements of arrays, keyed by the array's
    ///   dotted path ("masks", "masks.components"), so settings inside list items are filled in too.
    public static func decode<T: Codable>(_ type: T.Type, from data: Data, defaults: T, elementDefaults: [String: Any] = [:]) throws -> T {
        let defaultObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(defaults))
        let fileObject = try JSONSerialization.jsonObject(with: data)
        let merged = merge(base: defaultObject, overlay: fileObject, elements: elementDefaults)
        let mergedData = try JSONSerialization.data(withJSONObject: merged)
        return try JSONDecoder().decode(T.self, from: mergedData)
    }

    /// The JSON object for a value (for element templates).
    public static func object<T: Encodable>(_ value: T) -> Any {
        (try? JSONEncoder().encode(value)).flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? [String: Any]()
    }

    /// Recursively overlays `overlay` on `base`. Dictionaries merge key by key; arrays with an
    /// element template merge each element with it; anything else is taken from the overlay.
    static func merge(base: Any, overlay: Any, path: String = "", elements: [String: Any] = [:]) -> Any {
        if let array = overlay as? [Any], let template = elements[path], template is [String: Any] {
            return array.map { merge(base: template, overlay: $0, path: path, elements: elements) }
        }
        guard let baseDictionary = base as? [String: Any],
              let overlayDictionary = overlay as? [String: Any] else {
            return overlay
        }
        var result = baseDictionary
        for (key, value) in overlayDictionary {
            let childPath = path.isEmpty ? key : "\(path).\(key)"
            if let existing = baseDictionary[key] {
                result[key] = merge(base: existing, overlay: value, path: childPath, elements: elements)
            } else if let array = value as? [Any], let template = elements[childPath], template is [String: Any] {
                result[key] = array.map { merge(base: template, overlay: $0, path: childPath, elements: elements) }
            } else {
                result[key] = value
            }
        }
        return result
    }
}

extension EditDocument {
    /// Encodes the document as JSON.
    public func jsonData(pretty: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(self)
    }

    /// Decodes a document, tolerating files written before newer settings existed.
    public static func decode(from data: Data) throws -> EditDocument {
        try LenientJSON.decode(EditDocument.self, from: data, defaults: EditDocument(), elementDefaults: elementTemplates)
    }

    /// Defaults for items inside the document's lists (per-face, per-person, masks).
    static let elementTemplates: [String: Any] = [
        "beauty.faces": LenientJSON.object(FaceEdit(anchor: FaceAnchor(x: 0, y: 0, size: 0), settings: FaceRetouchSettings())),
        "body.bodies": LenientJSON.object(BodyEdit(anchor: BodyAnchor(x: 0, y: 0, size: 0), settings: BodySettings())),
        "masks": LenientJSON.object(Mask()),
        "masks.components": LenientJSON.object(MaskComponent()),
        "masks.components.strokes": LenientJSON.object(BrushStroke()),
        "retouch.operations": LenientJSON.object(RetouchOperation()),
        "retouch.operations.strokes": LenientJSON.object(BrushStroke()),
    ]
}
