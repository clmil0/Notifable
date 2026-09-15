import Foundation

/// Icono para categorías que son una persona: "María", "Regalos papá",
/// "Pensión de mi hijo".
///
/// Mucha gente separa lo que gasta en alguien de su familia en una categoría
/// con su nombre. Sin esto esas categorías caían todas en la bolsa genérica.
/// Lo consulta `CategoryStyle.defaultIcon` **después** del catálogo de
/// palabras, así "Luz" sigue siendo el recibo y no una persona.
///
/// Todo se compara sin tildes ni mayúsculas: "Mamá", "mama" y "MAMÁ" son lo mismo.
enum PersonCategoryIcon {

    static let woman = "figure.stand.dress"
    static let man = "figure.stand"
    static let child = "figure.child"

    /// Recorre las palabras en orden y se queda con la primera que diga algo:
    /// en "Juan y María" manda Juan. Los niños se miran antes que nada, porque
    /// "hija" también es mujer pero el icono útil es el de niño.
    static func icon(for category: String) -> String? {
        let words = tokens(category)
        guard !words.isEmpty else { return nil }
        if words.contains(where: childWords.contains) { return child }
        for word in words {
            if femaleRelations.contains(word) || femaleNames.contains(word) { return woman }
            if maleRelations.contains(word) || maleNames.contains(word) { return man }
        }
        return nil
    }

    static func tokens(_ text: String) -> [String] {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_PE"))
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
    }

    // MARK: - Diccionarios (sin tildes, en minúsculas)

    static let childWords: Set<String> = [
        "hijo", "hija", "hijos", "hijas", "hijito", "hijita",
        "nino", "nina", "ninos", "ninas", "ninito", "ninita",
        "bebe", "bebes", "bebito", "bebita", "guagua", "wawa", "nene", "nena",
        "chiquito", "chiquita", "chiquitos", "peque", "pequeno", "pequena",
        "sobrino", "sobrina", "sobrinos", "nieto", "nieta", "nietos",
        "ahijado", "ahijada", "chibolo", "chibola", "chiquillo", "chiquilla",
        "infantil", "kids", "junior"
    ]

    static let femaleRelations: Set<String> = [
        "madre", "mama", "mami", "mamita", "mamacita",
        "abuela", "abuelita", "tia", "tiita", "hermana", "hermanita", "esposa",
        "novia", "enamorada", "suegra", "prima", "cunada", "madrina", "comadre",
        "senora", "mujer", "amiga", "chica", "jefa"
    ]

    /// "papa" también es el tubérculo, pero como nombre de categoría casi
    /// siempre es "Papá" escrito sin tilde.
    static let maleRelations: Set<String> = [
        "padre", "papa", "papi", "papito", "papacito",
        "abuelo", "abuelito", "tio", "tiito", "hermano", "hermanito", "esposo",
        "novio", "enamorado", "suegro", "primo", "cunado", "padrino", "compadre",
        "senor", "hombre", "amigo", "chico", "jefe"
    ]

    /// Nombres de mujer frecuentes en Perú. Se dejan fuera los que en el país
    /// se usan para ambos (Rosario, Guadalupe, Trinidad). Los que chocan con
    /// una palabra de gasto ("Luz", el recibo) no se pisan: el catálogo de
    /// `CategoryStyle` se consulta antes y gana con el nombre exacto.
    static let femaleNames: Set<String> = [
        "maria", "rosa", "carmen", "ana", "juana", "luisa", "elena", "julia", "martha", "marta",
        "gladys", "flor", "lucia", "sofia", "valentina", "camila", "isabella", "ximena", "valeria",
        "mariana", "daniela", "gabriela", "andrea", "alejandra", "fernanda", "natalia", "paola",
        "patricia", "milagros", "karina", "carolina", "claudia", "cecilia", "silvia", "sonia",
        "susana", "teresa", "vilma", "yolanda", "zoila", "nelly", "norma", "olga", "pilar",
        "raquel", "ruth", "sara", "sandra", "monica", "veronica", "victoria", "wendy", "yesenia",
        "yessica", "jessica", "jennifer", "katherine", "kiara", "lizbeth", "lorena", "lourdes",
        "magaly", "margarita", "maribel", "marisol", "mercedes", "miriam", "nancy", "nataly",
        "noemi", "pamela", "rocio", "roxana", "sheyla", "shirley", "tania", "vanessa", "yanet",
        "janet", "evelyn", "fiorella", "giuliana", "isabel", "jimena", "juliana", "karen", "kelly",
        "leslie", "liliana", "lucero", "luz", "maritza", "melissa", "nicole", "angela", "angelica",
        "antonella", "ariana", "beatriz", "betty", "brenda", "carla", "catalina", "celia", "cinthia",
        "diana", "dayana", "doris", "edith", "elizabeth", "emilia", "esther", "estefany", "fatima",
        "gloria", "graciela", "irma", "ivonne", "jacqueline", "josefina", "judith", "laura",
        "leticia", "lidia", "lucy", "marleny", "martina", "mayra", "mirella", "nadia", "rebeca",
        "regina", "renata", "rosalia", "rosmery", "sabrina", "salome", "silvana", "stephanie",
        "susy", "thalia", "ursula", "vania", "violeta", "yuliana", "zulema", "abigail", "alicia",
        "amanda", "aurora", "belen", "blanca", "clara", "consuelo", "dora", "elsa", "emma",
        "eva", "francesca", "hilda", "ines", "irene", "jazmin", "julissa", "leonor", "lina",
        "maite", "micaela", "mia", "nora", "paula", "rosana", "rut", "soledad", "tatiana",
        "yadira", "zaida"
    ]

    /// Nombres de hombre frecuentes en Perú.
    static let maleNames: Set<String> = [
        "jose", "juan", "luis", "carlos", "jorge", "miguel", "cesar", "victor", "manuel", "pedro",
        "javier", "julio", "alberto", "roberto", "ricardo", "fernando", "eduardo", "oscar", "raul",
        "walter", "wilmer", "wilson", "segundo", "santiago", "sebastian", "mateo", "matias",
        "diego", "daniel", "david", "alejandro", "andres", "antonio", "angel", "adrian", "alex",
        "alexander", "alfredo", "alonso", "arturo", "augusto", "bruno", "christian", "cristian",
        "edgar", "edwin", "elmer", "emilio", "enrique", "erick", "ernesto", "fabricio", "felipe",
        "francisco", "franco", "freddy", "gabriel", "gerardo", "german", "gonzalo", "gustavo",
        "hector", "hugo", "ivan", "jaime", "jean", "jesus", "joaquin", "joel", "jonathan",
        "kevin", "leonardo", "lucas", "marco", "marcos", "mario", "martin", "maximo", "nestor",
        "nicolas", "omar", "pablo", "paolo", "percy", "rafael", "ramon", "renato", "rodrigo",
        "rolando", "ronald", "ruben", "samuel", "sergio", "teodoro", "thiago", "tomas", "wilfredo",
        "william", "yuri", "abel", "abraham", "agustin", "aldo", "amador", "anibal", "armando",
        "benjamin", "braulio", "carlitos", "cristobal", "dante", "dario", "dennis", "edson",
        "elias", "esteban", "fabian", "felix", "fidel", "gilberto", "guillermo", "hernan",
        "ignacio", "isaac", "jhon", "john", "jhonatan", "josue", "juanito", "julian", "leandro",
        "lorenzo", "manolo", "mauricio", "moises", "nelson", "orlando", "pepe", "piero", "renzo",
        "reynaldo", "rogelio", "salvador", "saul", "silvio", "teofilo", "ulises", "vicente",
        "wagner", "yordi", "anthony", "bryan", "brayan", "jhair", "jefferson", "gianfranco",
        "luciano", "valentino", "gael", "emiliano", "iker", "liam", "dylan", "ezequiel"
    ]
}
