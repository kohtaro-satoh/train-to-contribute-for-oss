FROM jenkins/jenkins:lts-jdk21

# Install dependency plugins at image build time
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# Install the locally built lockable-resources plugin
# (built by start.sh before docker compose build is invoked)
COPY lockable-resources.hpi /usr/share/jenkins/ref/plugins/lockable-resources.hpi

# Dev init scripts (create admin user, disable setup wizard)
COPY init.groovy.d/ /usr/share/jenkins/ref/init.groovy.d/

# Disable the setup wizard
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"

# Serve under /jenkins/ to match hpi:run default
ENV JENKINS_OPTS="--prefix=/jenkins"
