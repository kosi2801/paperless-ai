# Multi-stage build for smaller image size
# Stage 1: Build Node.js native modules
FROM node:22-slim AS node-builder

WORKDIR /app

# Install only build dependencies needed for better-sqlite3
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    make \
    g++ \
    python3 && \
    rm -rf /var/lib/apt/lists/*

# Copy package files
COPY package*.json ./

# Install dependencies (including native modules)
RUN npm ci --only=production

# Stage 2: Build Python environment (using same base as Stage 3)
FROM node:22-slim AS python-builder

WORKDIR /app

# Install Python and build tools
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-venv \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY requirements.txt /app/

# Create virtual environment and install dependencies
RUN python3 -m venv /app/venv
ENV PATH="/app/venv/bin:$PATH"
RUN pip install --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Stage 3: Final runtime image
FROM node:22-slim

WORKDIR /app

# Install only runtime dependencies (no build tools!)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    python3 \
    python3-venv \
    curl \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install PM2 globally
RUN npm install pm2 -g

# Copy Node.js dependencies from builder
COPY --from=node-builder /app/node_modules ./node_modules

# Copy Python virtual environment from builder
COPY --from=python-builder /app/venv /app/venv
ENV PATH="/app/venv/bin:$PATH"

# Copy package.json (for npm scripts, version info)
COPY package*.json ./

# Copy application source code
COPY . .

# Make startup script executable
RUN chmod +x start-services.sh

# Configure persistent data volume
VOLUME ["/app/data"]

# Expose port
EXPOSE ${PAPERLESS_AI_PORT:-3000}

# Health check
HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:${PAPERLESS_AI_PORT:-3000}/health || exit 1

# Set production environment
ENV NODE_ENV=production

# Start services
CMD ["./start-services.sh"]
