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
ENV JENKINS_VERSION ${JENKINS_VERSION:-2.121.3}

# jenkins.war checksum, download will be validated using it
ARG JENKINS_SHA=50fbce11fa147d0ecd9ecf36cdae83ef795fb7d4776f33b5ea13bc15bf6e3c13

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
COPY jenkins-plugins-deps /usr/share/jenkins/ref/jenkins-plugins-deps
COPY theme /usr/share/jenkins/ref/userContent/theme

# list of plugins which should be installed. Doesn't include deps list, which specified in jenkins-plugins-deps file.
RUN JENKINS_UC_DOWNLOAD=http://archives.jenkins-ci.org /usr/local/bin/install-plugins.sh \
        antisamy-markup-formatter:1.5 \
        artifactory:2.16.2 \
        blueocean:1.9.0 \
        build-blocker-plugin:1.7.3 \
        build-monitor-plugin:1.12+build.201809061734 \
        build-timeout:1.19 \
        build-user-vars-plugin:1.5 \
        categorized-view:1.10 \
        command-launcher:1.2 \
        copyartifact:1.41 \
        description-setter:1.10 \
        discard-old-build:1.05 \
        docker-workflow:1.17 \
        email-ext:2.63 \
        envinject:2.1.6 \
        extended-choice-parameter:0.76 \
        extensible-choice-parameter:1.6.0 \
        gerrit-trigger:2.27.7 \
        git:3.9.1 \
        github:1.29.3 \
        heavy-job:1.1 \
        jdk-tool:1.1 \
        jobConfigHistory:2.18.2 \
        jira:3.0.3 \
        ldap:1.20 \
        lockable-resources:2.3 \
        matrix-auth:2.3 \
        monitoring:1.74.0 \
        multiple-scms:0.6 \
        performance:3.12 \
        permissive-script-security:0.3 \
        pipeline-utility-steps:2.1.0 \
        plot:2.1.0 \
        prometheus:2.0.0 \
        rebuild:1.29 \
        simple-theme-plugin:0.5.1 \
        slack:2.3 \
        ssh-agent:1.17 \
        test-stability:2.3 \
        throttle-concurrents:2.0.1 \
        workflow-cps:2.58 \
        workflow-remote-loader:1.4 \
        workflow-scm-step:2.7

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
