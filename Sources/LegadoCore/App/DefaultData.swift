/// The default data that upstream ships — upstream
/// `io.legado.app.help.DefaultData`.
///
/// Upstream reads the JSON documents of `app/src/main/assets/defaultData/`
/// and inserts them into the database:
///
/// - the TXT table of contents rules when the table is empty
///   (`TextFile.getTocRules`),
/// - the HTTP TTS engines, the RSS sources and the dictionary rules when the
///   app is upgraded (`DefaultData.upVersion`).
///
/// The port embeds the very same documents (see `DefaultDataJSON`) so that
/// the core stays free of a resource bundle.
public enum DefaultData {

    // MARK: - The upstream defaults

    /// The default TXT table of contents rules — upstream
    /// `DefaultData.txtTocRules`.
    ///
    /// The upstream marks them with the negative ids (`-1`, `-2`, …) so that
    /// they can be replaced on an upgrade (`delete from txtTocRules where
    /// id < 0`).
    public static var txtTocRules: [TxtTocRule] {
        decodeArray(DefaultDataJSON.txtTocRule) { TxtTocRuleJSONBridge.decode($0) }
    }

    /// The default HTTP TTS engines — upstream `DefaultData.httpTTS`.
    public static var httpTTS: [HttpTTS] {
        decodeArray(DefaultDataJSON.httpTTS) { HttpTTSJSONBridge.decode($0) }
    }

    /// The default RSS sources — upstream `DefaultData.rssSources`.
    ///
    /// The upstream marks them with the group `legado`
    /// (`delete from rssSources where sourceGroup like 'legado'`).
    public static var rssSources: [RssSource] {
        decodeArray(DefaultDataJSON.rssSources) { RssSourceJSONBridge.decode($0) }
    }

    /// The default dictionary rules — upstream `DefaultData.dictRules`.
    public static var dictRules: [DictRule] {
        decodeArray(DefaultDataJSON.dictRules) { DictRuleJSONBridge.decode($0) }
    }

    /// The default keyboard assists — upstream
    /// `assets/defaultData/keyboardAssists.json`.
    public static var keyboardAssists: [KeyboardAssist] {
        decodeArray(DefaultDataJSON.keyboardAssists) { KeyboardAssistJSONBridge.decode($0) }
    }

    /// The default book cover rule — upstream
    /// `assets/defaultData/coverRule.json`.
    public static var coverRule: [String: String] {
        guard let value = try? JSONValue.parse(DefaultDataJSON.coverRule),
              case .object(let fields) = value else {
            return [:]
        }
        var result: [String: String] = [:]
        for (key, entry) in fields {
            result[key] = entry.textValue
        }
        return result
    }

    // MARK: - Importing

    /// Inserts the default data into a fresh database.
    ///
    /// Upstream only fills the empty tables: the TXT table of contents rules
    /// are inserted when `txtTocRules` is empty (`TextFile.getTocRules`) and
    /// the keyboard assists are inserted when the table is empty
    /// (`KeyboardAssistDialog`).
    public static func importDefaults(store: LegadoStore) throws {
        if try store.allTxtTocRules().isEmpty {
            for rule in txtTocRules {
                try store.insert(rule)
            }
        }
        if try store.allKeyboardAssists().isEmpty {
            for assist in keyboardAssists {
                try store.insert(assist)
            }
        }
    }

    /// Replaces the default HTTP TTS engines — upstream
    /// `DefaultData.importDefaultHttpTTS`.
    public static func importDefaultHttpTTS(store: LegadoStore) throws {
        try store.deleteDefaultHttpTTS()
        for engine in httpTTS {
            try store.insert(engine)
        }
    }

    /// Replaces the default RSS sources — upstream
    /// `DefaultData.importDefaultRssSources`.
    public static func importDefaultRssSources(store: LegadoStore) throws {
        try store.deleteDefaultRssSources()
        for source in rssSources {
            try store.insert(source)
        }
    }

    /// Replaces the default TXT table of contents rules — upstream
    /// `DefaultData.importDefaultTocRules`.
    public static func importDefaultTocRules(store: LegadoStore) throws {
        try store.deleteDefaultTxtTocRules()
        for rule in txtTocRules {
            try store.insert(rule)
        }
    }

    /// Inserts the default dictionary rules — upstream
    /// `DefaultData.importDefaultDictRules`.
    public static func importDefaultDictRules(store: LegadoStore) throws {
        for rule in dictRules {
            try store.insert(rule)
        }
    }

    // MARK: - Helpers

    private static func decodeArray<T>(
        _ json: String,
        _ decode: (JSONValue) -> T?
    ) -> [T] {
        guard let value = try? JSONValue.parse(json),
              case .array(let items) = value else {
            return []
        }
        return items.compactMap(decode)
    }
}

/// Decodes a `KeyboardAssist` from its JSON form.
public enum KeyboardAssistJSONBridge {
    public static func decode(_ value: JSONValue) -> KeyboardAssist? {
        guard case .object(let fields) = value,
              let key = fields["key"]?.textValue,
              let text = fields["value"]?.textValue else {
            return nil
        }
        return KeyboardAssist(
            type: fields["type"]?.intValue ?? 0,
            key: key,
            value: text,
            serialNo: fields["serialNo"]?.intValue ?? 0
        )
    }
}
