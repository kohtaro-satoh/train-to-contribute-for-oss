// ローカル開発専用: admin/admin ユーザーを作成してセキュリティを有効化
// 本番環境では絶対に使用しないこと

import jenkins.model.*
import hudson.security.*

def instance = Jenkins.get()

// すでにセキュリティが設定済みの場合はスキップ
if (instance.getSecurityRealm() instanceof HudsonPrivateSecurityRealm
        && instance.getSecurityRealm().getAllUsers().size() > 0) {
    return
}

def hudsonRealm = new HudsonPrivateSecurityRealm(false)
hudsonRealm.createAccount("admin", "admin")
instance.setSecurityRealm(hudsonRealm)

def strategy = new GlobalMatrixAuthorizationStrategy()
strategy.add(Jenkins.ADMINISTER, "admin")
instance.setAuthorizationStrategy(strategy)

instance.save()
println "[init] admin user created (dev-only)"
