// 1. RootAction で REST エンドポイント提供
@Extension
public class P2PApiEndpoint implements UnprotectedRootAction { ... }

// 2. LockableResourcesManager の薄いラッパー/デコレータで
//    Remote リソースを Local と同じインターフェイスで見せる
public class FederatedResourceResolver {
    Resource resolve(String name) {
        if (isLocal(name)) return localManager.get(name);
        else return new RemoteResourceProxy(peer, name);
    }
}

// 3. Pipeline の lock ステップは既存のまま動く（プロキシが透過的に処理）

// 4. GlobalConfiguration でピア一覧と公開ポリシーを管理
@Extension
public class P2PConfiguration extends GlobalConfiguration { ... }