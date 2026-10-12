import Foundation

/// Decodes JSON written by older app versions: keys missing from the file are filled in
/// from a default value, so adding new settings never breaks saved projects or presets.
public enum LenientJSON {
    public static func decode<T: Codable>(_ type: T.Type, from data: Data, defaults: T) throws -> T {
        let defaultObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(defaults))
        let fileObject = try JSONSerialization.jsonObject(with: data)
        let merged = merge(base: defaultObject, overlay: fileObject)
        let mergedData = try JSONSerialization.data(withJSONObject: merged)
        return try JSONDecoder().decode(T.self, from: mergedData)
    }

    /// Recursively overlays `overlay` on `base`. Dictionaries merge key by key; anything else
    /// (numbers, strings, arrays) is taken from the overlay.
    static func merge(base: Any, overlay: Any) -> Any {
        guard let baseDictionary = base as? [String: Any],
              let overlayDictionary = overlay as? [String: Any] else {
            return overlay
        }
        var result = baseDictionary
        for (key, value) in overlayDictionary {
            if let existing = baseDictionary[key] {
                result[key] = merge(base: existing, overlay: value)
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
        try LenientJSON.decode(EditDocument.self, from: data, defaults: EditDocument())
    }
}
