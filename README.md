# starproject

This repository is a reference template for recreating the workflow used to bootstrap a small FastAPI project with Poetry, Docker, and GitHub Actions deployment to a remote server.

## Goal

To use this guide when I want to repeat the same setup for a new project:

- local SSH access to a server
- FastAPI app managed with Poetry
- Docker image build for the API
- GitHub repository setup
- GitHub Actions CI that builds the image and deploys it over SSH

## 1. Configure local SSH access

Create or edit `~/.ssh/config`:

```sshconfig
Host local-server
    HostName hostname.org
    User user
    IdentityFile ~/.ssh/clave
```

Test the connection:

```bash
ssh local-server
```

## 2. Create the FastAPI project

In the project directory

Initialize Poetry:

```bash
poetry init
```

Install dependencies:

```bash
poetry install
```

If Poetry tries to install the project as a package and fails, install without the local package:

```bash
poetry install --no-root
```

Create the application structure:

```bash
mkdir app
touch app/__init__.py
touch app/main.py
```

In `app/main.py`:

```python
from fastapi import FastAPI

app = FastAPI()


@app.get("/health")
def health():
    return {"status": "ok"}
```

Run the app locally:

```bash
poetry run uvicorn app.main:app --reload
```

Test it:

```bash
curl http://127.0.0.1:8000/health
```

## 3. Verify tool versions

Check versions:

```bash
py --version
poetry run python --version
poetry --version
```

## 4. Initialize Git and push the repository

Initialize and push:

```bash
git init
git add .
git commit -m "msg"
git branch -M main
git remote add origin git@github.com:TU_USUARIO/project.git
git push -u origin main
```

## 5. Add Docker

Create `Dockerfile`:

```dockerfile
FROM python:3.13.3-slim

WORKDIR /app

ENV PYTHONUNBUFFERED=1
ENV POETRY_VERSION=2.4.0

RUN pip install "poetry==$POETRY_VERSION"

COPY pyproject.toml poetry.lock ./

RUN poetry config virtualenvs.create false \
    && poetry install --no-root --only main

COPY app ./app
COPY entrypoint.sh ./entrypoint.sh
RUN chmod +x ./entrypoint.sh

EXPOSE 8000

ENTRYPOINT ["./entrypoint.sh"]
```

Create `entrypoint.sh`:

```sh
#!/bin/sh
set -eu

exec uvicorn app.main:app --host 0.0.0.0 --port "${PORT:-8000}"
```

Create `docker-compose.yml` for local container testing:

```yaml
services:
  api:
    build: .
    container_name: project-api
    ports:
      - "8020:8000"
    restart: unless-stopped
```

## 6. Prepare SSH for GitHub Actions deploy

Generate a dedicated SSH key for deploy:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/project
```

Print the public key:

```bash
cat ~/.ssh/project.pub
```

On the server:

```bash
mkdir -p ~/.ssh
nano ~/.ssh/authorized_keys
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

Add the public key to `~/.ssh/authorized_keys`.

## 7. Configure GitHub Actions variables and secrets

Repository variable:

- `SSH_HOST`

Repository secrets:

- `SSH_USERNAME`
- `SSH_KEY`
- `GHCR_TOKEN`

## 8. Create the GitHub Actions workflow

Create the workflow directory and file:

```bash
mkdir -p .github/workflows
touch .github/workflows/deploy.yml
```

Use this workflow:

```yaml
name: Deploy to Ubuntu Server

on:
  push:
    branches:
      - main
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    environment:
      name: "main"
    permissions:
      contents: read
      packages: write
    outputs:
      image_tag: ${{ steps.vars.outputs.image_tag }}
    steps:
      - uses: actions/checkout@v4

      - id: vars
        shell: bash
        run: |
          if [ "${GITHUB_REF_NAME}" = "main" ]; then
            echo "image_tag=prod" >> "$GITHUB_OUTPUT"
          else
            echo "image_tag=test" >> "$GITHUB_OUTPUT"
          fi

      - uses: docker/setup-buildx-action@v3

      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.repository_owner }}
          password: ${{ secrets.GHCR_TOKEN }}

      - name: Build & Push
        env:
          IMAGE_TAG: ${{ steps.vars.outputs.image_tag }}
        shell: bash
        run: |
          OWNER_LC=${GITHUB_REPOSITORY_OWNER,,}
          IMAGE_REPO="ghcr.io/$OWNER_LC/hostname-api"
          docker build -t "$IMAGE_REPO:$IMAGE_TAG" .
          docker push "$IMAGE_REPO:$IMAGE_TAG"

  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: "main"
    steps:
      - name: Deploy via SSH
        uses: appleboy/ssh-action@v1.2.0
        env:
          OWNER: ${{ github.repository_owner }}
          GHCR_TOKEN: ${{ secrets.GHCR_TOKEN }}
          IMAGE_TAG: ${{ needs.build.outputs.image_tag }}
          APP_CONTAINER: project-api
          APP_HOST_PORT: "8020"
        with:
          host: ${{ vars.SSH_HOST }}
          username: ${{ secrets.SSH_USERNAME }}
          key: ${{ secrets.SSH_KEY }}
          port: 22
          envs: OWNER,GHCR_TOKEN,IMAGE_TAG,APP_CONTAINER,APP_HOST_PORT
          script: |
            set -e
            OWNER_LC=$(echo "$OWNER" | tr '[:upper:]' '[:lower:]')
            IMAGE_REPO="ghcr.io/$OWNER_LC/hostname-api"

            sudo -n systemctl start docker || true
            echo "$GHCR_TOKEN" | sudo -n docker login ghcr.io -u "$OWNER" --password-stdin
            sudo -n docker pull "$IMAGE_REPO:$IMAGE_TAG"
            sudo -n docker stop "$APP_CONTAINER" || true
            sudo -n docker rm "$APP_CONTAINER" || true
            sudo -n docker run -d --name "$APP_CONTAINER" \
              -p "$APP_HOST_PORT:8000" \
              --restart unless-stopped \
              "$IMAGE_REPO:$IMAGE_TAG"
```

## 9. Optional line endings fix

Create `.gitattributes`:

```gitattributes
* text=auto
*.yml text eol=lf
*.yaml text eol=lf
Dockerfile text eol=lf
```

## 10. Set up pre-commit

Add the development tools to Poetry:

```bash
poetry add --group dev pre-commit ruff pytest mypy bandit
```

Create `.pre-commit-config.yaml` in the project root. A simple version for this project is:

```yaml
repos:
  - repo: local
    hooks:
      - id: ruff-format
        name: ruff-format
        entry: poetry run ruff format
        language: system
        pass_filenames: true
        files: ^app/.*\.py$

      - id: ruff
        name: ruff
        entry: poetry run ruff check --fix
        language: system
        pass_filenames: true
        files: ^app/.*\.py$

      - id: pytest
        name: pytest
        entry: poetry run pytest
        language: system
        pass_filenames: false
        stages: [manual]
        files: ^app/.*\.py$

      - id: mypy
        name: mypy
        entry: poetry run mypy app
        language: system
        pass_filenames: false
        stages: [manual]
        files: ^app/.*\.py$

      - id: bandit
        name: bandit
        entry: poetry run python -m bandit -r app
        language: system
        pass_filenames: false
        stages: [manual]
```

Install the git hook locally:

```bash
poetry run pre-commit install
```

Run it once on the whole repository:

```bash
poetry run pre-commit run --all-files
```

## Checklist for repeating this in a new project

1. Configure local SSH access.
2. Bootstrap the FastAPI app with Poetry.
3. Verify Python and Poetry versions.
4. Initialize Git and push the repository.
5. Add Docker and an entrypoint script.
6. Generate a dedicated SSH deploy key.
7. Add GitHub repository variables and secrets.
8. Add the GitHub Actions workflow.
9. Push to `main` and verify the deploy action.
10. Set up pre-commit
