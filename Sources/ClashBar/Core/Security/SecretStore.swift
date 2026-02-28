import Foundation

protocol SecretStore {
    func loadControllerSecret() -> String?
    func saveControllerSecret(_ value: String?) throws
}
