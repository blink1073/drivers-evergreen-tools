#!/usr/bin/env bash
#
# Ensure the given binary is on the PATH.
# Should be called as:
# . $DRIVERS_TOOLS/.evergreen/ensure-binary.sh <binary-name>

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/handle-paths.sh

NAME=$1
if [ -z "$NAME" ]; then
  echo "Must supply a binary name!"
  return 1
fi

if [ -z "$DRIVERS_TOOLS" ]; then
  echo "Must supply DRIVERS_TOOLS env variable!"
  return 1
fi

if command -v $NAME &> /dev/null; then
  echo "$NAME found in PATH!"
  return 0
fi

OS_NAME=$(uname -s | tr '[:upper:]' '[:lower:]')
MARCH=$(uname -m | tr '[:upper:]' '[:lower:]')
URL=""

. "$SCRIPT_DIR/retry-with-backoff.sh"

case $NAME in
  kubectl)
    VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    BASE="https://dl.k8s.io/release/$VERSION/bin"
    case "$OS_NAME-$MARCH" in
        linux-x86_64)
          URL="$BASE/linux/amd64/kubectl"
        ;;
        linux-aarch64)
          URL="$BASE/linux/arm64/kubectl"
        ;;
        darwin-x86_64)
          URL="$BASE/darwin/amd64/kubectl"
        ;;
        darwin-arm64)
          URL="$BASE/darwin/arm64/kubectl"
        ;;
    esac
  ;;
  gcloud)
    BASE="https://dl.google.com/dl/cloudsdk/channels/rapid/downloads"
    case "$OS_NAME-$MARCH" in
       linux-x86_64)
          URL="$BASE/google-cloud-cli-linux-x86_64.tar.gz"
        ;;
        linux-aarch64)
          URL="$BASE/google-cloud-cli-linux-arm.tar.gz"
        ;;
        darwin-x86_64)
          URL="$BASE/google-cloud-cli-darwin-x86_64.tar.gz"
        ;;
        darwin-arm64)
          URL="$BASE/google-cloud-cli-darwin-arm.tar.gz"
        ;;
      esac
esac

# Set up variables for Go and ensure go is on the path.
set -x
if [ -d /opt/golang/go1.22 ]; then
  export GOROOT=/opt/golang/go1.22
  export PATH="${GOROOT}/bin:$PATH"
elif [ -d /cygdrive/c/golang/go1.22 ]; then
  export GOROOT=C:/golang/go1.22
  export PATH="/cygdrive/c/golang/go1.22/bin:$PATH"
fi
GOBIN=${DRIVERS_TOOLS}/.bin
GOCACHE=${DRIVERS_TOOLS}/.go-cache

echo "Installing $NAME..."

case $NAME in
  gcloud)
    # Google Cloud needs special handling: we need a symlink to the source location.
    if [ -z "$URL" ]; then
      echo "Unsupported for $NAME: $OS_NAME-$MARCH"
      return 1
    fi
    pushd /tmp
    rm -rf google-cloud-sdk
    FNAME=/tmp/google-cloud-sdk.tgz
    retry_with_backoff curl -L -s $URL -o $FNAME
    tar xfz $FNAME
    popd
    ln -s /tmp/google-cloud-sdk/bin/gcloud $DRIVERS_TOOLS/.bin/gcloud
    ;;
  task)
    # Task is installed using "go install".
    go version
    env GOBIN=${GOBIN} GOCACHE=${GOCACHE} go install github.com/go-task/task/v3/cmd/task@latest
    ;;
  *)
    # Download directly using curl.
    if [ -z "$URL" ]; then
      echo "Unsupported for $NAME: $OS_NAME-$MARCH"
      return 1
    fi
    mkdir -p ${DRIVERS_TOOLS}/.bin
    TARGET=${DRIVERS_TOOLS}/.bin/$NAME
    retry_with_backoff curl -L -s $URL -o $TARGET
    chmod +x $TARGET
    ;;
esac

echo "Installing $NAME... done."
