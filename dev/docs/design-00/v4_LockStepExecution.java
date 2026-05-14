@Override
public void stop(@NonNull Throwable cause) {
    boolean cleaned = LockableResourcesManager.get().unqueueContext(getContext());
    ...
    getContext().onFailure(cause);
}