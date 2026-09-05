import Foundation

/// Cómo viaja el dinero en JSON.
///
/// El problema: `JSONEncoder` escribe un `Double` con su representación
/// binaria más corta, así que un monto que no sea exactamente representable
/// —o que llegue de una operación sin normalizar— sale como
/// `20.000000000000004`. Postgres lo recibe por `->>` como ese mismo texto y
/// lo guarda tal cual en la columna `numeric`: el error deja de ser un detalle
/// de punto flotante y pasa a ser un dato.
///
/// La solución es la misma regla que `Money` ya impone dentro de la app,
/// extendida al borde: **el dinero cruza la red como texto decimal exacto**,
/// derivado de céntimos enteros ("20.00", "-3.05"). Postgres castea ese texto
/// a `numeric` sin pasar por un `float` intermedio, así que lo que se guarda
/// es exactamente lo que la app tiene.
///
/// Al leer se aceptan las dos formas —texto y número— para que los respaldos
/// escritos antes de este cambio sigan restaurándose.
@propertyWrapper
struct MoneyCoded: Codable, Equatable, Hashable {

    var wrappedValue: Double

    init(wrappedValue: Double) {
        // Se normaliza al entrar: un valor sucio no llega nunca al encoder.
        self.wrappedValue = Money.normalized(wrappedValue)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self), let value = Double(text) {
            self.init(wrappedValue: value)
            return
        }
        self.init(wrappedValue: try container.decode(Double.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Money.decimalText(wrappedValue))
    }
}

/// Igual que `MoneyCoded` pero opcional: `nil` viaja como `null`.
@propertyWrapper
struct MoneyCodedOptional: Codable, Equatable, Hashable {

    var wrappedValue: Double?

    init(wrappedValue: Double?) {
        self.wrappedValue = wrappedValue.map(Money.normalized)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self.init(wrappedValue: nil); return }
        if let text = try? container.decode(String.self) {
            self.init(wrappedValue: Double(text))
            return
        }
        self.init(wrappedValue: try? container.decode(Double.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let value = wrappedValue {
            try container.encode(Money.decimalText(value))
        } else {
            try container.encodeNil()
        }
    }
}

/// Un tipo de cambio no es dinero: necesita más decimales que dos (3.7412), así
/// que tiene su propia regla. Sigue viajando como texto por el mismo motivo.
@propertyWrapper
struct RateCoded: Codable, Equatable, Hashable {

    var wrappedValue: Double?

    init(wrappedValue: Double?) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self.init(wrappedValue: nil); return }
        if let text = try? container.decode(String.self) {
            self.init(wrappedValue: Double(text))
            return
        }
        self.init(wrappedValue: try? container.decode(Double.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        guard let value = wrappedValue, value.isFinite else {
            try container.encodeNil()
            return
        }
        var decimal = Decimal(string: "\(value)") ?? Decimal(value)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &decimal, 6, .plain)
        try container.encode("\(rounded)")
    }
}

extension Money {

    /// Texto decimal exacto con dos decimales, sin locale de por medio.
    ///
    /// No usa `String(format:)` sobre el `Double` —eso volvería a partir del
    /// valor binario— sino los céntimos enteros, que son la única
    /// representación fiable del monto en este proyecto.
    static func decimalText(_ value: Double) -> String {
        let total = cents(value)
        let sign = total < 0 ? "-" : ""
        let magnitude = abs(total)
        let units = magnitude / 100
        let fraction = magnitude % 100
        return "\(sign)\(units)." + (fraction < 10 ? "0\(fraction)" : "\(fraction)")
    }
}
