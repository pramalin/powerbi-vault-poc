FROM alpine:3.22
RUN apk add --no-cache python3 postgresql-client
COPY server.py /app/server.py
USER 65534:65534
CMD ["python3", "/app/server.py"]

