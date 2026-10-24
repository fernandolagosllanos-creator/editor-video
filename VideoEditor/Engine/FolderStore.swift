import Foundation
import Observation
import Security
import CryptoKit
import LocalAuthentication

/// Carpeta de la galería. Las privadas piden contraseña (guardada en el Llavero del sistema).
struct ProjectFolder: Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String
    var colorIndex = 0
    var symbol = "folder.fill"
    var isPrivate = false
    /// Permite abrirla con Face ID / Touch ID además de la contraseña.
    var useBiometrics = false
    var createdAt = Date()

    init(name: String) {
        self.name = name
    }

    // Codable a mano: los campos que se agreguen en el futuro se leen con decodeIfPresent.
    private enum CodingKeys: String, CodingKey {
        case id, name, colorIndex, symbol, isPrivate, useBiometrics, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Carpeta"
        colorIndex = try c.decodeIfPresent(Int.self, forKey: .colorIndex) ?? 0
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? "folder.fill"
        isPrivate = try c.decodeIfPresent(Bool.self, forKey: .isPrivate) ?? false
        useBiometrics = try c.decodeIfPresent(Bool.self, forKey: .useBiometrics) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(colorIndex, forKey: .colorIndex)
        try c.encode(symbol, forKey: .symbol)
        try c.encode(isPrivate, forKey: .isPrivate)
        try c.encode(useBiometrics, forKey: .useBiometrics)
        try c.encode(createdAt, forKey: .createdAt)
    }
}

/// Carpetas y en qué carpeta está cada proyecto. Se guarda en `Application Support/VideoEditor/Folders.json`
/// (así no hace falta tocar el archivo de cada proyecto). Todo es local y gratuito.
@MainActor
@Observable
final class FolderStore {
    static let shared = FolderStore()

    /// Ordenadas por nombre.
    private(set) var folders: [ProjectFolder] = []
    /// Proyecto → carpeta.
    private(set) var assignments: [UUID: UUID] = [:]
    /// Carpetas privadas abiertas en esta sesión. Se vuelven a cerrar al salir de ellas o al pasar a segundo plano.
    private(set) var unlocked: Set<UUID> = []

    private init() {
        load()
    }

    // MARK: - Consultas

    func folder(_ id: UUID) -> ProjectFolder? {
        folders.first { $0.id == id }
    }

    func folderID(of project: UUID) -> UUID? {
        assignments[project]
    }

    func projects(in folder: UUID, from all: [ProjectSummary]) -> [ProjectSummary] {
        all.filter { assignments[$0.id] == folder }
    }

    /// Proyectos que no están en ninguna carpeta.
    func unfiled(_ all: [ProjectSummary]) -> [ProjectSummary] {
        all.filter { assignments[$0.id] == nil }
    }

    /// Verdadero si el proyecto está en una carpeta privada que sigue cerrada.
    func isHidden(_ project: UUID) -> Bool {
        guard let fid = assignments[project], let f = folder(fid) else { return false }
        return f.isPrivate && !unlocked.contains(fid)
    }

    func isLocked(_ folder: ProjectFolder) -> Bool {
        folder.isPrivate && !unlocked.contains(folder.id)
    }

    // MARK: - Carpetas

    /// Crea una carpeta. Si es privada, `password` es obligatoria. Devuelve nil si no se pudo guardar la contraseña.
    @discardableResult
    func create(_ folder: ProjectFolder, password: String?) -> ProjectFolder? {
        if folder.isPrivate {
            guard let password, FolderLock.setPassword(password, for: folder.id) else { return nil }
            unlocked.insert(folder.id)
        }
        folders.append(folder)
        save()
        return folder
    }

    /// Guarda cambios de nombre, color, ícono o privacidad. `password` se usa al volverla privada o al cambiarla.
    @discardableResult
    func update(_ folder: ProjectFolder, password: String?) -> Bool {
        guard let i = folders.firstIndex(where: { $0.id == folder.id }) else { return false }
        if folder.isPrivate {
            if let password, !password.isEmpty {
                guard FolderLock.setPassword(password, for: folder.id) else { return false }
            } else if !FolderLock.hasPassword(folder.id) {
                return false
            }
            unlocked.insert(folder.id)
        } else {
            FolderLock.removePassword(for: folder.id)
        }
        folders[i] = folder
        save()
        return true
    }

    /// Borra la carpeta. Sus proyectos vuelven a la pantalla principal (no se borran).
    func delete(_ id: UUID) {
        folders.removeAll { $0.id == id }
        assignments = assignments.filter { $0.value != id }
        unlocked.remove(id)
        FolderLock.removePassword(for: id)
        save()
    }

    // MARK: - Proyectos

    func move(_ project: UUID, to folder: UUID?) {
        assignments[project] = folder
        save()
    }

    /// Se llama al borrar un proyecto.
    func forget(_ project: UUID) {
        guard assignments[project] != nil else { return }
        assignments[project] = nil
        save()
    }

    /// Olvida proyectos que ya no existen (p. ej. uno nuevo que se cerró sin agregarle videos).
    func prune(existing: Set<UUID>) {
        let kept = assignments.filter { existing.contains($0.key) }
        guard kept.count != assignments.count else { return }
        assignments = kept
        save()
    }

    // MARK: - Bloqueo

    func unlock(_ id: UUID, password: String) -> Bool {
        guard FolderLock.check(password, for: id) else { return false }
        unlocked.insert(id)
        return true
    }

    /// Desbloquea con Face ID / Touch ID. Con `allowDevicePasscode` también acepta el código del iPhone o la clave del Mac
    /// (se usa para "¿Olvidaste la contraseña?").
    func unlockWithDevice(_ id: UUID, allowDevicePasscode: Bool = false) async -> Bool {
        let name = folder(id)?.name ?? "la carpeta"
        let ok = await Biometrics.authenticate(reason: "Abrir la carpeta privada «\(name)»", allowPasscode: allowDevicePasscode)
        if ok { unlocked.insert(id) }
        return ok
    }

    func lock(_ id: UUID) {
        unlocked.remove(id)
    }

    func lockAll() {
        unlocked.removeAll()
    }

    // MARK: - Archivo

    private struct Stored: Codable {
        var folders: [ProjectFolder] = []
        var assignments: [String: String] = [:]
    }

    nonisolated static var fileURL: URL {
        ProjectStore.directory.deletingLastPathComponent().appendingPathComponent("Folders.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let stored = try? JSONDecoder.project.decode(Stored.self, from: data)
        else { return }
        folders = stored.folders
        var map: [UUID: UUID] = [:]
        for (p, f) in stored.assignments {
            if let p = UUID(uuidString: p), let f = UUID(uuidString: f), stored.folders.contains(where: { $0.id == f }) {
                map[p] = f
            }
        }
        assignments = map
        sortFolders()
    }

    private func save() {
        sortFolders()
        var stored = Stored()
        stored.folders = folders
        stored.assignments = Dictionary(uniqueKeysWithValues: assignments.map { ($0.key.uuidString, $0.value.uuidString) })
        if let data = try? JSONEncoder.project.encode(stored) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }

    private func sortFolders() {
        folders.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Contraseñas en el Llavero

/// Guarda en el Llavero del sistema (gratis, cifrado por Apple) una huella de la contraseña con sal,
/// nunca la contraseña en texto.
enum FolderLock {
    private static let service = "VideoEditor.PrivateFolders"

    static func hasPassword(_ id: UUID) -> Bool {
        read(id) != nil
    }

    static func setPassword(_ password: String, for id: UUID) -> Bool {
        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard status == errSecSuccess else { return false }
        return write(salt + digest(password, salt: salt), for: id)
    }

    static func check(_ password: String, for id: UUID) -> Bool {
        guard let stored = read(id), stored.count > 16 else { return false }
        let salt = stored.prefix(16)
        return Data(stored.dropFirst(16)) == digest(password, salt: Data(salt))
    }

    static func removePassword(for id: UUID) {
        SecItemDelete(baseQuery(id) as CFDictionary)
    }

    private static func digest(_ password: String, salt: Data) -> Data {
        Data(SHA256.hash(data: salt + Data(password.utf8)))
    }

    private static func baseQuery(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: id.uuidString]
    }

    private static func write(_ data: Data, for id: UUID) -> Bool {
        removePassword(for: id)
        var query = baseQuery(id)
        query[kSecValueData as String] = data
        #if os(iOS)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        #endif
        query[kSecAttrLabel as String] = "Editor de Video – carpeta privada"
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private static func read(_ id: UUID) -> Data? {
        var query = baseQuery(id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
}

// MARK: - Face ID / Touch ID

enum Biometrics {
    private static var type: LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }

    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    static var name: String {
        switch type {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "Face ID / Touch ID"
        }
    }

    static var symbol: String {
        switch type {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        default: return "lock.shield"
        }
    }

    /// Nombre de la clave del dispositivo, para "¿Olvidaste la contraseña?".
    static var devicePasscodeName: String {
        #if os(macOS)
        return "la contraseña de tu Mac"
        #else
        return "el código de tu iPhone"
        #endif
    }

    static func authenticate(reason: String, allowPasscode: Bool) async -> Bool {
        let context = LAContext()
        let policy: LAPolicy = allowPasscode ? .deviceOwnerAuthentication : .deviceOwnerAuthenticationWithBiometrics
        guard context.canEvaluatePolicy(policy, error: nil) else { return false }
        do {
            return try await context.evaluatePolicy(policy, localizedReason: reason)
        } catch {
            return false
        }
    }
}
