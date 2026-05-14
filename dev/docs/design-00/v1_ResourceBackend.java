public interface ResourceBackend {
    boolean tryLock(String resource, String owner, Duration ttl);
    void unlock(String resource, String owner);
    void heartbeat(String resource, String owner);
    List<String> listAvailable(String label, int quantity);
    Optional<ResourceState> getState(String resource);
}

// 実装クラス
// - LocalResourceBackend       (既存互換)
// - EtcdResourceBackend        (新規)
// - RedisResourceBackend       (新規)