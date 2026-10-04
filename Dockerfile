FROM ubuntu:26.04

LABEL org.opencontainers.image.source=https://github.com/textyre/bootstrap

ENV LANG=C.UTF-8 \
    EDITOR=vi \
    REPO_ROOT=/opt/bootstrap \
    ANSIBLE_CONFIG=/opt/bootstrap/ansible/ansible.cfg \
    ANSIBLE_INVENTORY=/opt/bootstrap/ansible/inventory/openstrap.yml \
    ANSIBLE_VAULT_PASSWORD_FILE=/opt/bootstrap/ansible/vault-pass.sh \
    ANSIBLE_COLLECTIONS_PATH=/opt/ansible/collections:/usr/share/ansible/collections \
    ARA_API_CLIENT=offline \
    ARA_BASE_DIR=/root/ara

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3 python3-pip ansible-core ansible-lint python3-jmespath \
        openssh-client rsync git ca-certificates vim-tiny \
    && python3 -m pip install --break-system-packages --no-cache-dir \
        'ara[server]==1.7.3' 'django-health-check<4' \
    && mkdir -p /opt/ansible \
    && ln -s "$(python3 -m ara.setup.callback_plugins)" /opt/ansible/ara-callback \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/bootstrap/ansible
COPY ansible/requirements.yml requirements.yml
RUN ansible-galaxy collection install -r requirements.yml -p /opt/ansible/collections
COPY ansible/ ./
RUN chmod 0755 vault-pass.sh

CMD ["sleep", "infinity"]
