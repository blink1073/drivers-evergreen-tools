#!/usr/bin/env bash
set -o errexit
set -o pipefail

source env.sh
pushd ./drivers-evergreen-tools/.evergreen/auth_oidc
. ./activate-authoidcvenv.sh

# Run the Python Driver Test
git clone https://github.com/mongodb/mongo-python-driver
pushd mongo-python-driver
pip install -U -q pip
pip install .
popd
pip install -q requests
python azure/remote-scripts/test.py
popd
