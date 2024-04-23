import os
from pymongo import MongoClient
from pymongo.auth_oidc import OIDCCallback, OIDCCallbackContext, OIDCCallbackResult

uri = "mongodb://127.0.0.1:27017/?directConnection=true"

class MyCallback(OIDCCallback):
    def fetch(self, context: OIDCCallbackContext) -> OIDCCallbackResult:
        with open(os.environ['AWS_WEB_IDENTITY_TOKEN_FILE']) as fid:
            token = fid.read()
        return OIDCCallbackResult(access_token=token)

props = dict(OIDC_CALLBACK=MyCallback())
c = MongoClient(uri, authMechanism="MONGODB-OIDC", authMechanismProperties=props)
c.test.test.insert_one({})
c.close()

# apt-get update -y
# apt-get install -y vim lsof git python3 python3-venv curl
# git clone https://github.com/blink1073/drivers-evergreen-tools.git
# cd drivers-evergreen-tools/
# git fetch origin test-eks
# git checkout test-eks
# cd ./.evergreen
# pushd auth_oidc
# . ./activate-authoidcvenv.sh
# python oidc_write_orchestration.py
# popd
# MONGODB_VERSION=7.0 TOPOLOGY=replica_set ORCHESTRATION_FILE=auth-oidc.json bash run-orchestration.sh
# export URI="mongodb://127.0.0.1:27017/?directConnection=true"
# ../../mongodb/bin/mongosh -f ./setup_oidc.js "$URI&serverSelectionTimeoutMS=10000"

# python3 -m venv venv
# source venv/bin/activate
# git clone https://github.com/mongodb/mongo-python-driver.git
# pip install ./mongo-python-driver/
# vim test.py
# python test.py
