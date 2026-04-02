FROM ubuntu:24.04

ARG DEVOPS_UID=1001
ARG DEVOPS_GID=1001

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    KUBECTL_VERSION=v1.29.3

# Packages système
RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server \
    libpam-google-authenticator \
    sudo \
    curl \
    wget \
    git \
    vim \
    jq \
    python3 \
    iproute2 \
    iputils-ping \
    netcat-openbsd \
    dnsutils \
    ca-certificates \
    gnupg \
    lsb-release \
    procps \
    less \
    fail2ban \
    iptables \
    acct \
  && rm -rf /var/lib/apt/lists/*

# Docker CLI uniquement (pas le daemon)
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) \
    signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
    https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends docker-ce-cli \
  && rm -rf /var/lib/apt/lists/*

# kubectl
RUN curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    -o /usr/local/bin/kubectl \
  && chmod +x /usr/local/bin/kubectl

# Utilisateur devops non-root
RUN groupadd -g ${DEVOPS_GID} devops \
  && groupadd -g 999 docker || true \
  && useradd -m -u ${DEVOPS_UID} -g devops -G docker,sudo \
      -s /bin/bash -c "DevOps Engineer" devops \
  && passwd -l devops

# Sudo limité
COPY config/sudoers.d/devops /etc/sudoers.d/devops
RUN chmod 0440 /etc/sudoers.d/devops

# SSH config
RUN mkdir -p /run/sshd /var/log/bastion
COPY config/sshd_config /etc/ssh/sshd_config
COPY config/sshd_pam /etc/pam.d/sshd

# MOTD
COPY config/motd /etc/motd
RUN chmod -x /etc/update-motd.d/* 2>/dev/null || true

# Fail2ban
COPY config/fail2ban/jail.local /etc/fail2ban/jail.local

# Audit logger
COPY scripts/audit-logger.sh /etc/profile.d/audit-logger.sh
RUN chmod +x /etc/profile.d/audit-logger.sh

RUN mkdir -p /var/log/bastion/audit \
  && chown devops:devops /var/log/bastion/audit

# Scripts
COPY scripts/entrypoint.sh /entrypoint.sh
COPY scripts/fail2ban-watcher.sh /usr/local/bin/fail2ban-watcher.sh
RUN chmod +x /entrypoint.sh /usr/local/bin/fail2ban-watcher.sh

# SSH host keys
RUN ssh-keygen -A

EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]
