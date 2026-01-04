FROM alpine:latest

# Install required packages
RUN apk add --no-cache \
    bash \
    openssh-client \
    rsync \
    maven

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
