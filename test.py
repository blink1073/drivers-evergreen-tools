import os
from azure.identity import DefaultAzureCredential
from pymongo import MongoClient
from pymongo.auth_oidc import OIDCCallback, OIDCCallbackContext, OIDCCallbackResult

app_id = os.environ['AZURE_APP_CLIENT_ID']
client_id = os.environ['AZURE_IDENTITY_CLIENT_ID']
uri = "mongodb://127.0.0.1"

class MyCallback(OIDCCallback):
    def fetch(self, context: OIDCCallbackContext) -> OIDCCallbackResult:
        with open(os.environ['']) as fid:
            token = fid.read()
        return OIDCCallbackResult(access_token=token)

props = dict(OIDC_CALLBACK=MyCallback())
c = MongoClient(uri, authMechanism="MONGODB-OIDC", authMechanismProperties=props)
c.test.test.insert_one({})
c.close()
