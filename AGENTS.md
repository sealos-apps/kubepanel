# KubePanel Agent Notes

## Project Shape

- This repository is the standalone migration of `labring/sealos/frontend/providers/kubepanel` from upstream commit `52ed8943dc320c21655b14259d9b279da24bc6d2`.
- Keep business behavior aligned with that upstream snapshot unless a task explicitly asks for a behavior change.
- The migrated Sealos Desktop SDK import uses the public package `@labring/sealos-desktop-sdk`; do not reintroduce `workspace:*` dependencies.

## Commands

- Install: `pnpm install`
- Build: `pnpm build`
- Lint: `pnpm lint`
- Helm check: `helm lint deploy/charts/kubepanel -f deploy/charts/kubepanel/values.yaml -f deploy/charts/kubepanel/kubepanel-values.yaml`
- Render check: `helm template kubepanel deploy/charts/kubepanel -n kubepanel -f deploy/charts/kubepanel/values.yaml -f deploy/charts/kubepanel/kubepanel-values.yaml`

## Deploy Rules

- Runtime image source is `Dockerfile`; Sealos cluster image source is `deploy/Kubefile`.
- `deploy/kubepanel-entrypoint.sh` must not delete Helm releases, Helm-owned resources, namespaces, or user values files.
- The entrypoint may delete only known previous manual YAML resources by exact namespace/kind/name, and it must skip resources that have Helm ownership annotations.
- Keep compatibility with existing `kubepanel` and `kubepanel-frontend` Helm releases; the entrypoint should reuse the existing release when detected.
- OSS upload in CI is optional and must be skipped successfully when `OSS_BUCKET`, `OSS_ENDPOINT`, `OSS_ACCESS_KEY_ID`, or `OSS_ACCESS_KEY_SECRET` is missing.
