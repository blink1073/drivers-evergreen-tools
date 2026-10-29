# AWS Lamba Testing

See the [FaaS Automated Testing specification](https://github.com/mongodb/specifications/blob/master/source/faas-automated-testing/faas-automated-testing.md) for details.

Per MongoDB's cloud resource tag policy, the deployed Lambda stack and function are tagged with
`mongodb-owner=client-libraries-managers@mongodb.com` and `mongodb-env=dev`. Override
the tag values with `MONGODB_OWNER_TAG` and `MONGODB_ENV_TAG`.

See [Secrets Handling README](../secrets_handling/README.md) for details on how to access the secrets
from the `drivers/atlas-qa` vault.
