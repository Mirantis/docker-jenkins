FROM openjdk:8-jdk

LABEL maintainer="dev@mirantis.com"

ENV DEBIAN_FRONTEND=noninteractive \
    DEBCONF_NONINTERACTIVE_SEEN=true \
    LANG=C.UTF-8 \
    LANGUAGE=$LANG
SHELL ["/bin/bash", "-xec"]

#  Base apt config
RUN cd /etc/apt/ \
  && echo 'Acquire::Languages "none";' > apt.conf.d/docker-no-languages \
  && echo 'Acquire::GzipIndexes "true"; Acquire::CompressionTypes::Order:: "gz";' > apt.conf.d/docker-gzip-indexes \
  && echo 'APT::Get::Install-Recommends "false"; APT::Get::Install-Suggests "false";' > apt.conf.d/docker-recommends

RUN apt-get update && apt-get install -y git curl gettext-base python-virtualenv

ENV JENKINS_HOME /var/jenkins_home
ENV JENKINS_SLAVE_AGENT_PORT 50000

ARG user=jenkins
ARG group=jenkins
ARG uid=1000
ARG gid=1000

# Jenkins is run with user `jenkins`, uid = 1000
# If you bind mount a volume from the host or a data container,
# ensure you use the same uid
RUN groupadd -g ${gid} ${group} \
    && useradd -d "$JENKINS_HOME" -u ${uid} -g ${gid} -m -s /bin/bash ${user}

# Jenkins home directory is a volume, so configuration and build history
# can be persisted and survive image upgrades
VOLUME /var/jenkins_home

# `/usr/share/jenkins/ref/` contains all reference configuration we want
# to set on a fresh new installation. Use it to bundle additional plugins
# or config file with your custom jenkins Docker image.
RUN mkdir -p /usr/share/jenkins/ref/init.groovy.d; chown ${uid}:${gid} /usr/share/jenkins/ref/init.groovy.d

ENV TINI_VERSION 0.13.2
ENV TINI_SHA afbf8de8a63ce8e4f18cb3f34dfdbbd354af68a1

# Use tini as subreaper in Docker container to adopt zombie processes
RUN curl -fsSL https://github.com/krallin/tini/releases/download/v${TINI_VERSION}/tini-static-amd64 -o /bin/tini && chmod +x /bin/tini \
  && echo "$TINI_SHA  /bin/tini" | sha1sum -c -

COPY init.groovy /usr/share/jenkins/ref/init.groovy.d/tcp-slave-agent-port.groovy

# jenkins version being bundled in this docker image
ARG JENKINS_VERSION
ENV JENKINS_VERSION ${JENKINS_VERSION:-2.104}

# jenkins.war checksum, download will be validated using it
ARG JENKINS_SHA=51724ecb3c287d13679d9c1bde72552283928b17f49861fe2bfd337fbbfb95a0

# Can be used to customize where jenkins.war get downloaded from
ARG JENKINS_URL=https://repo.jenkins-ci.org/public/org/jenkins-ci/main/jenkins-war/${JENKINS_VERSION}/jenkins-war-${JENKINS_VERSION}.war

# could use ADD but this one does not check Last-Modified header neither does it allow to control checksum
# see https://github.com/docker/docker/issues/8331
RUN curl -fsSL ${JENKINS_URL} -o /usr/share/jenkins/jenkins.war \
  && echo "${JENKINS_SHA}  /usr/share/jenkins/jenkins.war" | sha256sum -c -

ENV JENKINS_UC https://updates.jenkins.io
RUN chown -R ${user} "$JENKINS_HOME" /usr/share/jenkins/ref

# for main web interface:
EXPOSE 8080

# will be used by attached slave agents:
EXPOSE 50000

ENV COPY_REFERENCE_FILE_LOG $JENKINS_HOME/copy_reference_file.log

COPY SimpleThemeDecorator.xml  /tmp/org.codefirst.SimpleThemeDecorator.xml
RUN chown ${user} /tmp/org.codefirst.SimpleThemeDecorator.xml

USER ${user}

COPY jenkins-support /usr/local/bin/jenkins-support
COPY jenkins.sh /usr/local/bin/jenkins.sh
ENTRYPOINT ["/bin/tini", "--", "/usr/local/bin/jenkins.sh"]

# from a derived Dockerfile, can use `RUN plugins.sh active.txt` to setup /usr/share/jenkins/ref/plugins from a support bundle
COPY plugins.sh /usr/local/bin/plugins.sh
COPY install-plugins.sh /usr/local/bin/install-plugins.sh
COPY theme /usr/share/jenkins/ref/userContent/theme

RUN JENKINS_UC_DOWNLOAD=http://archives.jenkins-ci.org /usr/local/bin/install-plugins.sh \
        artifactory \
        blueocean \
        build-blocker-plugin \
        build-monitor-plugin \
        build-timeout \
        build-user-vars-plugin \
        categorized-view \
        copyartifact \
        description-setter \
        discard-old-build \
        docker-workflow \
        email-ext \
        envinject \
        extended-choice-parameter \
        extensible-choice-parameter \
        gerrit-trigger \
        git \
        github \
        heavy-job \
        jobConfigHistory \
        jira \
        ldap \
        lockable-resources \
        matrix-auth \
        monitoring \
        multiple-scms \
        performance \
        permissive-script-security \
        pipeline-utility-steps \
        plot \
        prometheus \
        rebuild \
        simple-theme-plugin \
        slack \
        ssh-agent \
        test-stability \
        throttle-concurrents \
        workflow-cps \
        workflow-remote-loader \
        workflow-scm-step

# Switch user for cleanup
USER root
# Cleanup.
RUN apt-get -y autoremove; apt-get -y clean;
RUN rm -rf /root/.cache
RUN rm -rf /var/lib/apt/lists/*
RUN rm -rf /tmp/*
RUN rm -rf /var/tmp/*
# And switch it back
USER ${user}
