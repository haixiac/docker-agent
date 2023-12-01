# The MIT License
#
#  Copyright (c) 2015-2020, Intel, Inc. and other Jenkins contributors
#
#  Permission is hereby granted, free of charge, to any person obtaining a copy
#  of this software and associated documentation files (the "Software"), to deal
#  in the Software without restriction, including without limitation the rights
#  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#  copies of the Software, and to permit persons to whom the Software is
#  furnished to do so, subject to the following conditions:
#
#  The above copyright notice and this permission notice shall be included in
#  all copies or substantial portions of the Software.
#
#  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
#  THE SOFTWARE.
ARG JAVA_VERSION=11
FROM amr-registry.caas.intel.com/simics-containers-registry/sles12/ci/sles12sp5ci:2.0.4

#################################################################
# set up inbound agent environment 
#################################################################
ARG user=jenkins
ARG group=jenkins
ARG uid=1000
ARG gid=1000

# Add Jenkins user and group
RUN groupadd -g "${gid}" "${group}" \
  && useradd -d "/home/${user}" -u "${uid}" -g "${group}" "${user}"

ARG AGENT_WORKDIR=/home/"${user}"/agent

ENV LANG='en_US.UTF-8' LANGUAGE='en_US:en' LC_ALL='en_US.UTF-8'
ENV TZ=Etc/UTC

#install java 
#RUN zypper --non-interactive install java-11-openjdk-devel  && zypper clean
RUN zypper search openjdk-devel
RUN zypper --non-interactive install java-11-openjdk-devel  && zypper clean
#install some dependecies 
RUN zypper -n install git \
	sudo \
	curl \
	openssh \
	&& zypper clean
RUN java --version

# add agent.jar into docker
# Install jenkins jnlp
ARG VERSION=3192.v713e3b_039fb_e
ADD --chown="${user}":"${group}" "https://repo.jenkins-ci.org/public/org/jenkins-ci/main/remoting/${VERSION}/remoting-${VERSION}.jar" /usr/share/jenkins/agent.jar
RUN chmod 0644 /usr/share/jenkins/agent.jar \
  && ln -sf /usr/share/jenkins/agent.jar /usr/share/jenkins/slave.jar

#copy jenkins-slave 
USER root
COPY jenkins-agent /usr/local/bin/jenkins-agent
RUN chmod +x /usr/local/bin/jenkins-agent &&\
    ln -s /usr/local/bin/jenkins-agent /usr/local/bin/jenkins-slave


ENV AGENT_WORKDIR="${AGENT_WORKDIR}"
RUN mkdir -p /home/"${user}"/.jenkins \
    && mkdir -p "${AGENT_WORKDIR}" \
    && chown -R jenkins:jenkins /home/jenkins

VOLUME /home/"${user}"/.jenkins
VOLUME "${AGENT_WORKDIR}"
WORKDIR /home/"${user}"
ENV user=${user}
LABEL \
    org.opencontainers.image.vendor="Jenkins project" \
    org.opencontainers.image.title="Official Jenkins Agent Base Docker image" \
    org.opencontainers.image.description="This is a base image, which provides the Jenkins agent executable (agent.jar)" \
    org.opencontainers.image.version="${VERSION}" \
    org.opencontainers.image.url="https://www.jenkins.io/" \
    org.opencontainers.image.source="https://github.com/jenkinsci/docker-agent" \
    org.opencontainers.image.licenses="MIT"


USER ${user}

ENTRYPOINT ["/usr/local/bin/jenkins-agent"]


#set up fcds cloud  depenency

