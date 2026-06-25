# Minimal SSH host for remote CLI install integration tests.
# Ships curl/wget for Node bootstrap but no Node/npm/CLIs preinstalled.
FROM debian:bookworm-slim

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      openssh-server \
      curl \
      wget \
      ca-certificates \
      xz-utils \
      socat \
 && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /run/sshd \
 && ssh-keygen -A \
 && useradd -m -s /bin/bash testuser \
 && echo 'testuser:teampilot-test' | chpasswd \
 && sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config \
 && sed -i 's/#PermitEmptyPasswords.*/PermitEmptyPasswords no/' /etc/ssh/sshd_config

EXPOSE 22
CMD ["/usr/sbin/sshd", "-D", "-e"]
