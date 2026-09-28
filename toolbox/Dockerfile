FROM alpine:3.22
RUN apk add --no-cache bash curl jq postgresql-client python3 py3-cryptography py3-requests py3-pip \
 && pip install --no-cache-dir --break-system-packages "msal>=1.28,<2"
WORKDIR /work
