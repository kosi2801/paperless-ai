# Docker Image Optimization Guide

## Current Issues & Solutions

### 1. **Multi-Stage Build** ✅ (Already Implemented)
The Dockerfile now uses a 3-stage build:
- **Stage 1**: Build Node.js native modules (better-sqlite3)
- **Stage 2**: Build Python environment with packages
- **Stage 3**: Minimal runtime image with only compiled artifacts

**Benefit**: Removes ~500-800 MB of build tools from final image.

---

## Additional Optimizations

### 2. **Use CPU-Only PyTorch** (BIGGEST WIN)

**Current Issue**: PyTorch with CUDA support is ~3-4 GB
**Solution**: Use CPU-only version (~800 MB)

Update `requirements.txt`:
```txt
# Add before torch installation
--extra-index-url https://download.pytorch.org/whl/cpu
torch>=2.0.0
```

**Estimated Savings**: 2-3 GB

---

### 3. **Remove Unnecessary Dependencies**

#### Node.js Dependencies
Review `package.json` - these are production dependencies:

**Potentially removable**:
- `nodemon` (line 46) - Only needed for development! Should be in devDependencies
- `swagger-ui-express` - If API docs aren't critical in production
- `cheerio` - Only used if parsing HTML (check usage)
- `dockerode` - Only if container management is needed

**Action**: Move nodemon to devDependencies:
```json
{
  "dependencies": {
    // Remove nodemon from here
  },
  "devDependencies": {
    "nodemon": "^3.1.9",  // Move here
    ...
  }
}
```

**Estimated Savings**: 50-100 MB

#### Python Dependencies
Check if all are essential:
- `tqdm` - Progress bars (optional, ~1 MB)
- Full NLTK data downloads (check main.py downloads)

---

### 4. **Optimize Python Package Installation**

Add to Stage 2 (python-builder):
```dockerfile
# Install with optimizations
RUN pip install --upgrade pip && \
    pip install --no-cache-dir \
    --no-compile \
    --prefer-binary \
    -r requirements.txt
```

**Flags explained**:
- `--no-cache-dir`: Don't cache packages
- `--no-compile`: Skip .pyc compilation (Python will compile on first run)
- `--prefer-binary`: Use pre-built wheels instead of compiling from source

**Estimated Savings**: 100-200 MB

---

### 5. **Reduce NLTK Data**

In `main.py` (lines 68-71), only specific NLTK data is downloaded:
```python
nltk.download('punkt', quiet=True)
nltk.download('punkt_tab', quiet=True)
nltk.download('stopwords', quiet=True)
```

This is already optimized (only ~30 MB), but you could make it conditional:
```python
import os
if not os.path.exists('/app/data/nltk_data'):
    nltk.download('punkt', download_dir='/app/data/nltk_data', quiet=True)
    # etc.
```

---

### 6. **Use .dockerignore**

Create/update `.dockerignore`:
```
# Development files
node_modules/
.git/
.github/
*.log
*.md
docs/
test/

# Python cache
__pycache__/
*.pyc
*.pyo
*.pyd
.Python
*.egg-info/
venv/
.venv/

# IDE
.vscode/
.idea/
*.swp
*.swo

# Data files (use volumes instead)
data/
*.db
*.db-shm
*.db-wal

# Images
*.png
*.jpg
*.jpeg
dashboard.png
preview.png
rag_ready.png
setup.png
icon.png
icon.webp
*.zip

# Documentation
README.md
CONTRIBUTING.md
CODE_OF_CONDUCT.md
SECURITY.md
PRIVACY_POLICY.md
LICENSE
```

**Estimated Savings**: 50-100 MB (especially with image files)

---

### 7. **Optimize Base Images**

Current: `node:22-slim` and `python:3.10-slim`

Consider even smaller alternatives:
```dockerfile
# Option 1: Alpine (smallest, but can have compatibility issues)
FROM node:22-alpine AS node-builder
FROM python:3.10-alpine AS python-builder

# Option 2: Distroless (no shell, most secure, hard to debug)
FROM node:22-slim AS node-builder
# ... build stages ...
FROM gcr.io/distroless/nodejs22-debian12:nonroot
```

**Note**: Alpine can have issues with native modules. Test thoroughly.

**Estimated Savings**: 50-100 MB with Alpine

---

### 8. **Optimize Better-SQLite3**

Check if you can use a pre-built binary:
```dockerfile
# In Stage 1
RUN npm ci --only=production --build-from-source=false
```

Or use the `better-sqlite3` Docker-friendly build:
```json
{
  "optionalDependencies": {
    "better-sqlite3": "^11.8.1"
  }
}
```

---

### 9. **Remove wget** (Already Fixed)

The original Dockerfile had `wget` but it's unused. Current version only has `curl` for health checks. ✅

---

## Implementation Priority

### High Impact (Do First):
1. ✅ **Multi-stage build** - Already implemented
2. **CPU-only PyTorch** - 2-3 GB savings
3. **Move nodemon to devDependencies** - 50 MB savings
4. **Add .dockerignore** - 50-100 MB savings

### Medium Impact:
5. **Optimize pip install flags** - 100-200 MB
6. **Remove unused Node packages** - 50-100 MB

### Low Impact (Optional):
7. Alpine base images - 50-100 MB but compatibility risk
8. Remove optional dependencies - 10-50 MB

---

## Expected Results

| Optimization | Current Size | Optimized Size | Savings |
|-------------|--------------|----------------|---------|
| Before multi-stage | ~5-6 GB | - | - |
| After multi-stage ✅ | ~4-5 GB | ~4-5 GB | 1 GB |
| + CPU PyTorch | ~4-5 GB | ~1.5-2 GB | **2-3 GB** |
| + All optimizations | ~4-5 GB | **~1-1.5 GB** | **3-4 GB** |

---

## Quick Start

### Option 1: Use Optimized Requirements
```bash
# Replace requirements.txt with CPU-only PyTorch
cp requirements.optimized.txt requirements.txt
docker build -t paperless-ai:optimized .
```

### Option 2: Test Current Multi-Stage Build
```bash
# The Dockerfile is already optimized with multi-stage
docker build -t paperless-ai:latest .
docker images paperless-ai:latest  # Check size
```

---

## Verification

Check image size:
```bash
docker images paperless-ai
```

Check layer sizes:
```bash
docker history paperless-ai:latest --human --format "table {{.CreatedBy}}\t{{.Size}}"
```

Analyze image:
```bash
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  wagoodman/dive:latest paperless-ai:latest
```

---

## Notes

- **g++ and make ARE needed** for `better-sqlite3` native compilation (Stage 1 only)
- **python3-dev IS needed** for Python package compilation (Stage 2 only)
- These are NOT in the final image (Stage 3) thanks to multi-stage build ✅
- Most space is consumed by PyTorch - switching to CPU version is the biggest win
