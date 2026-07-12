import Foundation

public final class DependencyContainer: @unchecked Sendable {
    public static let shared = DependencyContainer()
    
    private var factories: [String: Any] = [:]
    private var singletons: [String: Any] = [:]
    private let lock = NSRecursiveLock()
    
    private init() {}
    
    public func register<T>(_ type: T.Type, isSingleton: Bool = true, factory: @escaping () -> T) {
        lock.lock()
        defer { lock.unlock() }
        let key = String(describing: type)
        factories[key] = factory
        if isSingleton {
            // Remove any old cached instance
            singletons.removeValue(forKey: key)
        }
    }
    
    public func resolve<T>(_ type: T.Type) -> T {
        lock.lock()
        defer { lock.unlock() }
        let key = String(describing: type)
        
        // If it's a singleton and already created, return it
        if let cached = singletons[key] as? T {
            return cached
        }
        
        // Fetch factory
        guard let factory = factories[key] as? () -> T else {
            fatalError("Dependency '\(key)' is not registered in DependencyContainer.")
        }
        
        let instance = factory()
        
        // If it was registered as a singleton (we check if it existed in singletons/factories),
        // let's cache it. To be safe, we always cache if resolved unless specified otherwise.
        singletons[key] = instance
        return instance
    }
}
