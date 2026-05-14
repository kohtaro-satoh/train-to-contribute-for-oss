protected void finished(StepContext context) throws Exception {
    ...
    LockableResourcesManager.get().unlockNames(this.resourceNames, build);
}