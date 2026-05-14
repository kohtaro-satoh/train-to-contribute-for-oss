@Override
public boolean start() throws Exception {
    ...
    synchronized (LockableResourcesManager.syncResources) {
        step.validate(lrm.isAllowEmptyOrNullValues());
        ...
        available = lrm.getAvailableResources(...);
        if (available == null || available.isEmpty()) {
            onLockFailed(...); // queue へ or skip
            return false;
        }
        lrm.lock(available, run, step.reason);
        ...
    }
    LockStepExecution.proceed(...); // ブロック実行へ
    return false;
}