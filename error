FROM artifactory.voya.net/docker-virtual/openshift/ubi8/openjdk-8:latest

ARG TARGETPLATFORM
ARG RUNNER_VERSION
ARG RUNNER_CONTAINER_HOOKS_VERSION
ARG CHANNEL=stable
# Removed Docker version ARGs
ARG DUMB_INIT_VERSION=1.2.5
ARG RUNNER_USER_UID=1001
ARG DOCKER_GROUP_GID=121

# 1. Install corporate certificates
COPY voya_ecc_root.crx voyarootca.cer voya_rsa_root.crx zscalerrootca.cer /etc/pki/ca-trust/source/anchors/
RUN update-ca-trust extract

RUN microdnf update -y && \
    microdnf install -y \
        curl \
        ca-certificates \
        git \
        dnf \
        yum \
        jq \
        unzip \
        zip \
        libicu \
        krb5-libs \
        zlib \
        openssl-libs \
        shadow-utils \
        findutils \
        libyaml-devel \
        procps-ng \
        iputils \
        hostname \
        nc \
        tar \
        gzip \
        which \
        wget \
        less \
        vim-minimal \
        lsof \
    && dnf clean all

RUN curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.rpm.sh | bash && \
    dnf install -y git-lfs && \
    git lfs install

# Install Podman and related tools
RUN dnf install -y podman buildah crun fuse-overlayfs slirp4netns && \
    dnf clean all

RUN groupadd --gid $DOCKER_GROUP_GID docker && \
    useradd --uid $RUNNER_USER_UID -g $DOCKER_GROUP_GID --create-home runner && \
    chmod g+w /etc/passwd

ENV HOME=/home/runner
ENV RUNNER_HOME=/home/runner

# Configure Podman storage for rootless operation
ENV CONTAINERS_STORAGE_DRIVER=overlay
ENV CONTAINERS_CONF=/etc/containers/containers.conf
RUN mkdir -p $HOME/.local/share/containers && \
    chown -R $RUNNER_USER_UID:$DOCKER_GROUP_GID $HOME/.local

# Configure rootless containers
RUN echo -e '[storage]\ndriver = "overlay"\n[engine]\ncgroup_manager = "cgroupfs"\nevents_logger = "file"\n' > $CONTAINERS_CONF && \
    echo -e '[network]\ndns_bind_port = 0\n' >> $CONTAINERS_CONF

RUN ARCH=$(echo ${TARGETPLATFORM} | cut -d / -f2) && \
    if [ "$ARCH" = "arm64" ]; then ARCH=aarch64; fi && \
    if [ "$ARCH" = "amd64" ] || [ "$ARCH" = "i386" ]; then ARCH=x86_64; fi && \
    curl -fLo /usr/bin/dumb-init https://github.com/Yelp/dumb-init/releases/download/v${DUMB_INIT_VERSION}/dumb-init_${DUMB_INIT_VERSION}_${ARCH} && \
    chmod +x /usr/bin/dumb-init

ENV RUNNER_ASSETS_DIR=/runnertmp
RUN ARCH=$(echo ${TARGETPLATFORM} | cut -d / -f2) && \
    if [ "$ARCH" = "amd64" ] || [ "$ARCH" = "x86_64" ] || [ "$ARCH" = "i386" ]; then ARCH=x64; fi && \
    mkdir -p "$RUNNER_ASSETS_DIR" && \
    cd "$RUNNER_ASSETS_DIR" && \
    curl -fLo runner.tar.gz https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${ARCH}-${RUNNER_VERSION}.tar.gz && \
    tar xzf ./runner.tar.gz && \
    rm runner.tar.gz && \
    ./bin/installdependencies.sh

# Copy runner to home directory
RUN cp -r $RUNNER_ASSETS_DIR/* $HOME/ && \
    chown -R $RUNNER_USER_UID:$DOCKER_GROUP_GID $HOME

ENV RUNNER_TOOL_CACHE=/opt/hostedtoolcache
RUN mkdir /opt/hostedtoolcache && \
    chgrp $DOCKER_GROUP_GID /opt/hostedtoolcache && \
    chmod g+rwx /opt/hostedtoolcache

RUN cd "$RUNNER_ASSETS_DIR" && \
    curl -fLo runner-container-hooks.zip https://github.com/actions/runner-container-hooks/releases/download/v${RUNNER_CONTAINER_HOOKS_VERSION}/actions-runner-hooks-k8s-${RUNNER_CONTAINER_HOOKS_VERSION}.zip && \
    unzip ./runner-container-hooks.zip -d ./k8s && \
    rm -f runner-container-hooks.zip

COPY entrypoint.sh startup.sh logger.sh graceful-stop.sh update-status /usr/bin/
# Updated docker-shim to use Podman
COPY docker-shim.sh /usr/local/bin/docker
COPY hooks /etc/arc/hooks/

ENV PATH="${PATH}:${HOME}/.local/bin"
ENV ImageOS=rhel8

RUN echo "PATH=${PATH}" > /etc/environment && \
    echo "ImageOS=${ImageOS}" >> /etc/environment && \
    echo "CONTAINERS_STORAGE_DRIVER=overlay" >> /etc/environment

# Set execute permissions
RUN chmod 755 /usr/bin/entrypoint.sh /usr/bin/startup.sh /usr/bin/logger.sh /usr/bin/graceful-stop.sh /usr/local/bin/docker

# Add debug tools and ensure scripts are executable
RUN chmod +x $HOME/run.sh $HOME/bin/*.sh

# Create symlink to runner scripts in PATH
RUN ln -s $HOME/run.sh /usr/bin/run.sh

# Fix for OpenShift arbitrary user IDs
RUN chgrp -R 0 $HOME /opt /etc/arc /usr/bin && \
    chmod -R g=u $HOME /opt /etc/arc /usr/bin && \
    chmod g+rw /etc/passwd && \
    chmod 755 /usr/bin/entrypoint.sh /usr/bin/startup.sh /usr/bin/logger.sh /usr/bin/graceful-stop.sh

RUN ls -l /usr/bin/entrypoint.sh

WORKDIR $HOME

# Important: Use numeric UID for OpenShift compatibility
USER $RUNNER_USER_UID

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["/usr/bin/entrypoint.sh"]
