BodyInvoker bodyInvoker =
    context.newBodyInvoker().withCallback(new Callback(resourceNames, resourceDescription));
...
bodyInvoker.start();