FROM ubuntu:latest

WORKDIR /workspace

# Обновление списка пакетов и установка необходимых утилит
RUN apt-get update && \
    apt-get install -y curl gnupg unzip && \
    rm -rf /var/lib/apt/lists/*

# Установка kubectl
ENV KUBECTL_VERSION=v1.26.5
RUN curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/

# Установка vault, так как репозиторий любезно заблокировали с той стороны волт пришлось скачать руками и положить сюда
#ENV VAULT_VERSION=1.14.0
#RUN curl -fsSL "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip" -o vault.zip && \
COPY vault.zip /workspace

RUN unzip vault.zip && \
    chmod +x vault && \
    mv vault /usr/local/bin/ && \
    rm vault.zip

# Установка jq для обработки JSON
RUN apt-get update && \
    apt-get install -y jq && \
    rm -rf /var/lib/apt/lists/*

# Проверка установленных версий kubectl и vault
RUN kubectl version --client && \
    vault --version

CMD ["/bin/bash"]
