#!/usr/bin/env bash
set -euo pipefail

if command -v sealos >/dev/null 2>&1; then
  sealos version
  exit 0
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

arch="$(uname -m)"
case "${arch}" in
  x86_64|amd64)
    sealos_arch="amd64"
    ;;
  aarch64|arm64)
    sealos_arch="arm64"
    ;;
  *)
    echo "Unsupported architecture: ${arch}" >&2
    exit 1
    ;;
esac

cd "${tmp_dir}"
SEALOS_VERSION="${SEALOS_VERSION:-5.1.1}"
SEALOS_TAG="${SEALOS_VERSION}"
case "${SEALOS_TAG}" in
  v*) ;;
  *) SEALOS_TAG="v${SEALOS_TAG}" ;;
esac
SEALOS_ARCHIVE_VERSION="${SEALOS_TAG#v}"

until curl -sSfLo sealos.tar.gz "https://github.com/labring/sealos/releases/download/${SEALOS_TAG}/sealos_${SEALOS_ARCHIVE_VERSION}_linux_${sealos_arch}.tar.gz"; do
  sleep 3
done

tar -zxf sealos.tar.gz sealos
chmod +x sealos
mv sealos /usr/bin/sealos
sealos version
