FROM docker.io/library/nginx:alpine

# Install apache2-utils for htpasswd command
RUN apk add --no-cache apache2-utils

# Create directory for htpasswd file
RUN mkdir -p /etc/nginx/auth

# Copy nginx configuration
COPY nginx.conf /etc/nginx/nginx.conf

# Expose the proxy port
EXPOSE 8080

# Default command
CMD ["nginx", "-g", "daemon off;"]
