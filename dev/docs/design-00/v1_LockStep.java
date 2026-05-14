@Extension
public static final class DescriptorImpl extends StepDescriptor {
    @Override
    public String getFunctionName() {
        return "lock";
    }

    @Override
    public boolean takesImplicitBlockArgument() {
        return true;
    }
}