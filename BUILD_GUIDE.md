# Maximo Connector - Build and Deployment Guide

This guide explains how to build and push the Maximo connector Docker image without having Maven installed locally.

## Prerequisites

- **Docker** installed and running
- **Container registry account** (Docker Hub, GitHub Container Registry, Quay.io, etc.)
- **Registry credentials** (username and password/token)

## Quick Start

### 1. Configure Environment Variables

Copy the example environment file and edit it with your values:

```bash
cp .env.example .env
nano .env  # or use your preferred editor
```

The .env file already has `export` statements, so you just need to fill in your values:

```bash
export REGISTRY_URL=docker.io
export REGISTRY_USERNAME=your-username
export REGISTRY_PASSWORD=your-password-or-token
export IMAGE_NAME=your-org/maximo-connector
export IMAGE_TAG=1.0.0
```

### 2. Run with One Command

Simply source the .env file and run the script in one line:

```bash
source .env && ./build-and-push.sh
```

That's it! The `source .env` command loads all the exported variables, and then the script runs with those values.

The script will:
1. ✅ Clean previous builds
2. ✅ Build the application using Maven (in Docker)
3. ✅ Build the Docker image
4. ✅ Login to your container registry
5. ✅ Push the image to the registry
6. ✅ Tag and push as 'latest' (if not already)

## Detailed Instructions

### Option 1: Using Environment File (Recommended)

1. **Create your .env file:**
   ```bash
   cp .env.example .env
   ```

2. **Edit .env with your credentials:**
   ```bash
   # The file already has 'export' statements, just change the values
   export REGISTRY_URL=docker.io
   export REGISTRY_USERNAME=myusername
   export REGISTRY_PASSWORD=dckr_pat_xxxxxxxxxxxxxxxxxxxxx
   export IMAGE_NAME=myusername/maximo-connector
   export IMAGE_TAG=1.0.0
   ```

3. **Run (one command):**
   ```bash
   source .env && ./build-and-push.sh
   ```
   
   The `source .env` automatically exports all variables, then the script runs.

### Option 2: Inline Environment Variables

Run the script with environment variables set inline:

```bash
REGISTRY_URL=docker.io \
REGISTRY_USERNAME=myusername \
REGISTRY_PASSWORD=mypassword \
IMAGE_NAME=myorg/maximo-connector \
IMAGE_TAG=1.0.0 \
./build-and-push.sh
```

### Option 3: Export Variables

Export variables in your shell session:

```bash
export REGISTRY_URL=docker.io
export REGISTRY_USERNAME=myusername
export REGISTRY_PASSWORD=mypassword
export IMAGE_NAME=myorg/maximo-connector
export IMAGE_TAG=1.0.0

./build-and-push.sh
```

## Registry-Specific Examples

### Docker Hub

```bash
# Create access token at: https://hub.docker.com/settings/security
export REGISTRY_URL=docker.io
export REGISTRY_USERNAME=myusername
export REGISTRY_PASSWORD=dckr_pat_xxxxxxxxxxxxxxxxxxxxx
export IMAGE_NAME=myusername/maximo-connector
export IMAGE_TAG=1.0.0

./build-and-push.sh
```

**Result:** Image available at `docker.io/myusername/maximo-connector:1.0.0`

### GitHub Container Registry (ghcr.io)

```bash
# Create token at: https://github.com/settings/tokens
# Required scopes: write:packages, read:packages, delete:packages
export REGISTRY_URL=ghcr.io
export REGISTRY_USERNAME=myusername
export REGISTRY_PASSWORD=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
export IMAGE_NAME=myusername/maximo-connector
export IMAGE_TAG=1.0.0

./build-and-push.sh
```

**Result:** Image available at `ghcr.io/myusername/maximo-connector:1.0.0`

**Note:** Make the package public in GitHub:
1. Go to https://github.com/users/USERNAME/packages/container/maximo-connector
2. Click "Package settings"
3. Scroll to "Danger Zone"
4. Click "Change visibility" → "Public"

### Quay.io

```bash
# Create robot account at: https://quay.io/organization/ORGNAME?tab=robots
export REGISTRY_URL=quay.io
export REGISTRY_USERNAME=myorg+robot
export REGISTRY_PASSWORD=XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
export IMAGE_NAME=myorg/maximo-connector
export IMAGE_TAG=1.0.0

./build-and-push.sh
```

**Result:** Image available at `quay.io/myorg/maximo-connector:1.0.0`

### Google Container Registry (GCR)

```bash
# Create service account and download JSON key
export REGISTRY_URL=gcr.io
export REGISTRY_USERNAME=_json_key
export REGISTRY_PASSWORD='<paste entire JSON key here>'
export IMAGE_NAME=my-project/maximo-connector
export IMAGE_TAG=1.0.0

./build-and-push.sh
```

**Result:** Image available at `gcr.io/my-project/maximo-connector:1.0.0`

### AWS Elastic Container Registry (ECR)

```bash
# First, get login token
aws ecr get-login-password --region us-east-1

# Then use it
export REGISTRY_URL=123456789012.dkr.ecr.us-east-1.amazonaws.com
export REGISTRY_USERNAME=AWS
export REGISTRY_PASSWORD=<token from previous command>
export IMAGE_NAME=maximo-connector
export IMAGE_TAG=1.0.0

./build-and-push.sh
```

**Result:** Image available at `123456789012.dkr.ecr.us-east-1.amazonaws.com/maximo-connector:1.0.0`

## Advanced Options

### Custom Maven Image

Use a different Maven Docker image:

```bash
export MAVEN_IMAGE=maven:3.8-openjdk-17
./build-and-push.sh
```

### Additional Build Arguments

Pass extra arguments to Docker build:

```bash
export BUILD_ARGS="--no-cache --build-arg HTTP_PROXY=http://proxy:8080"
./build-and-push.sh
```

### Build Without Pushing

To only build the image locally without pushing:

1. Comment out the push steps in `build-and-push.sh`, or
2. Build manually:

```bash
# Build with Maven in Docker
docker run --rm \
  -v "$(pwd)":/workspace \
  -v "$HOME/.m2":/root/.m2 \
  -w /workspace \
  maven:3.9-eclipse-temurin-21 \
  mvn clean package -DskipTests

# Build Docker image
docker build -t maximo-connector:local -f container/Dockerfile .
```

## Troubleshooting

### Issue: "Docker daemon is not running"

**Solution:** Start Docker Desktop or Docker daemon:
```bash
# macOS
open -a Docker

# Linux
sudo systemctl start docker
```

### Issue: "Permission denied" when running script

**Solution:** Make the script executable:
```bash
chmod +x build-and-push.sh
```

### Issue: "Maven build failed"

**Solution:** Check Maven output for errors. Common issues:
- Missing dependencies
- Java version mismatch
- Network connectivity issues

Try cleaning Maven cache:
```bash
rm -rf ~/.m2/repository
```

### Issue: "Failed to push image"

**Solution:** Verify:
1. Registry credentials are correct
2. You have push permissions
3. Repository exists (create it first if needed)
4. Network connectivity to registry

### Issue: "Disk space" errors

**Solution:** Clean up Docker:
```bash
# Remove unused images
docker image prune -a

# Remove build cache
docker builder prune

# Remove everything unused
docker system prune -a --volumes
```

## Verifying the Build

### Check Local Image

```bash
docker images | grep maximo-connector
```

### Test Run Locally

```bash
docker run -p 8080:9443 your-registry/maximo-connector:1.0.0
```

### Pull from Registry

```bash
docker pull your-registry/maximo-connector:1.0.0
```

### Inspect Image

```bash
docker inspect your-registry/maximo-connector:1.0.0
```

## CI/CD Integration

### GitHub Actions

Create `.github/workflows/build-and-push.yml`:

```yaml
name: Build and Push

on:
  push:
    branches: [ main ]
    tags: [ 'v*' ]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up environment
        run: |
          echo "REGISTRY_URL=ghcr.io" >> $GITHUB_ENV
          echo "REGISTRY_USERNAME=${{ github.actor }}" >> $GITHUB_ENV
          echo "IMAGE_NAME=${{ github.repository }}" >> $GITHUB_ENV
          echo "IMAGE_TAG=${{ github.ref_name }}" >> $GITHUB_ENV
      
      - name: Build and Push
        env:
          REGISTRY_PASSWORD: ${{ secrets.GITHUB_TOKEN }}
        run: ./build-and-push.sh
```

### GitLab CI

Create `.gitlab-ci.yml`:

```yaml
build-and-push:
  image: docker:latest
  services:
    - docker:dind
  script:
    - export REGISTRY_URL=$CI_REGISTRY
    - export REGISTRY_USERNAME=$CI_REGISTRY_USER
    - export REGISTRY_PASSWORD=$CI_REGISTRY_PASSWORD
    - export IMAGE_NAME=$CI_PROJECT_PATH
    - export IMAGE_TAG=$CI_COMMIT_TAG
    - ./build-and-push.sh
  only:
    - tags
```

## Security Best Practices

1. **Never commit .env file** - It's already in .gitignore
2. **Use access tokens** instead of passwords when possible
3. **Rotate credentials** regularly
4. **Use least-privilege** service accounts
5. **Scan images** for vulnerabilities:
   ```bash
   docker scan your-registry/maximo-connector:1.0.0
   ```

## Next Steps

After building and pushing the image:

1. **Deploy to AIOps** - Follow the deployment guide in MAXIMO_CONNECTOR_README.md
2. **Configure the connector** - Use the configuration examples in config-examples/
3. **Set up the DB2 view** - Follow MAXIMO_DB2_VIEW_SETUP.md

## Support

For issues:
1. Check the troubleshooting section above
2. Review Docker and Maven logs
3. Verify all prerequisites are met
4. Check registry-specific documentation

## Additional Resources

- [Docker Documentation](https://docs.docker.com/)
- [Maven in Docker](https://hub.docker.com/_/maven)
- [Container Registry Comparison](https://www.docker.com/blog/choosing-a-container-registry/)