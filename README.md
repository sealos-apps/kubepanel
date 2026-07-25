# KubePanel

KubePanel is the Sealos resource monitoring panel, migrated from the Sealos monorepo into an independent application repository.

Source snapshot: `labring/sealos/frontend/providers/kubepanel` at commit `52ed8943dc320c21655b14259d9b279da24bc6d2`.

## Development

Requirements:

- Node.js `20.20.2`
- pnpm `9.15.4`

Install dependencies and start development:

```bash
pnpm install
pnpm dev
```

For local development outside Sealos Desktop, create `.env.local`:

```bash
NEXT_PUBLIC_MOCK_USER=""
SEALOS_DOMAIN="dev.sealos.top"
NODE_ENV="development"
```

Set `NEXT_PUBLIC_MOCK_USER` to a JSON string containing your Sealos session kubeconfig when you need to mock a logged-in user.

## Build

```bash
pnpm build
pnpm lint
make build
```

The runtime Docker image is built from `Dockerfile`:

```bash
docker build -t kubepanel:dev .
```

## Sealos Cluster Image

The `Build Sealos from Sealos` GitHub Actions workflow builds:

- Runtime images: `ghcr.io/<owner>/<repo>/kubepanel:<tag>`
- Sealos cluster images: `ghcr.io/<owner>/<repo>/kubepanel-cluster:<tag>`

The cluster image packages Helm chart assets and a cached runtime image. During deployment, `deploy/kubepanel-entrypoint.sh` reads Sealos Cloud config from `sealos-system/sealos-config`, reuses an existing `kubepanel` or `kubepanel-frontend` Helm release when present, creates the user values file when missing, cleans only previous manual YAML-deployed KubePanel resources by exact names, and runs `helm upgrade -i`.

It does not delete Helm releases, namespaces, or existing user values files.

## Optional OSS Sync

The workflow keeps OSS package sync support. It only runs when all of these are configured:

- Repository variable: `OSS_BUCKET`
- Repository secrets: `OSS_ENDPOINT`, `OSS_ACCESS_KEY_ID`, `OSS_ACCESS_KEY_SECRET`

When any value is missing, the OSS sync job reports a skip and exits successfully.
