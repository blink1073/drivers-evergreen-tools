# Scripts for OIDC testing

## Testing

`MONGODB-OIDC` is only supported on Linux, but we can run it on Docker.

We have two dedicated Atlas clusters that are configured with OIDC, one with a single Identity Provider (Idp),
and one with multiple IdPs configured.  Since `failCommand` is global, test runs have the chance to interfere
with each other.  After we implement DRIVERS-2688, we can specify that OIDC tests that use `failCommand` must
not be run on Atlas.

When running `setup.sh`, the local server for single IdP will be used when not on Windows and docker is available.

### Prerequisites

The `setup.sh` script will automatically fetch the credentials from the `drivers/oidc` vault.
See [Secrets Handling](../secrets_handling/README.md) for details on how the script accesses the vault.
Add `secrets-export.sh` to your `.gitignore` to prevent checking in credentials in your repo.

The secrets in the vault include:

```bash
OIDC_ALTAS_USER         # Atlas admin username and password
OIDC_ATLAS_PASSWORD
OIDC_ATLAS_URI_MULTI    # URI for the cluster with multiple IdPs configured
OIDC_ATLAS_URI_SINGLE   # URI for the cluster with single IdP configured
OIDC_CLIENT_SECRET      # The client secret used by the IdPs
OIDC_RSA_KEY            # The RSA key used by the IdPs
OIDC_JWKS_URI           # The JWKS URI used by the IdPs
OIDC_ISSUER_1_URI       # The issuer URI for mock IdP 1
OIDC_ISSUER_2_URI       # The issuer URI for mock IdP 2
```

### Usage

Use the `setup.sh` script to create a set of OIDC tokens in a temporary directory, including
`test_user1` and `test_user1_expires`.  The temp file location is exported as `OIDC_TOKEN_DIR`.
If not on Windows and Docker is available, it will start a local server.  Otherwise,
`OIDC_ATLAS_URI_SINGLE` is used.  The URIs will be written to `secrets-export.sh` as
`OIDC_URI_SINGLE` and `OIDC_URI_MULTI`.

```bash
. ./setup.sh
OIDC_TOKEN_FILE="$OIDC_TOKEN_DIR/test_user1" /my/test/command
```

There is also a token `test_user2` for the second IdP, and `test_user1_expires` that
can be used to test expired credentials.

While testing, to debug the server logs locally, use `docker ps` to find the running container,
and then run `docker exec -it <container> /bin/bash` to log into the box.
If you `cat /root/server.log` you can find the location of the `logpath`.

## Local Testing for Multi IdP Server

If desired, you can separately start a local server with multiple
IdPs configured, by running `./start_local_server.sh multi` in a terminal window.
Update `OIDC_URI_MULTI` in `secrets-export.sh` to `"mongodb://localhost:27018"`.

## Azure Testing

See the [Azure README](./azure/README.md).
