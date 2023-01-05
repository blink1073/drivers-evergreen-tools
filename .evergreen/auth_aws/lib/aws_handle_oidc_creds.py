#!/usr/bin/env python3
"""
Script for handling OIDC credentials.
"""
import argparse
import base64
import os
import time
import uuid

from jwkest.jwk import RSAKey, import_rsa_key
from pyop.authz_state import AuthorizationState
from pyop.provider import Provider
from pyop.subject_identifier import HashBasedSubjectIdentifierFactory
from pyop.userinfo import Userinfo


HERE = os.path.abspath(os.path.dirname(__file__))
ISSUER = os.environ['IDP_ISSUER']
JWKS_URI = os.environ['IDP_JWKS_URI']
RSA_KEY = os.environ["IDP_RSA_KEY"]
if RSA_KEY.endswith('='):
    RSA_KEY = base64.urlsafe_b64decode(RSA_KEY).decode('utf-8')
AUDIENCE = 'sts.amazonaws.com'
CLIENT_ID = os.getenv("IDP_CLIENT_ID", "0oadp0hpl7q3UIehP297")
CLIENT_SECRET = os.getenv("IDP_CLIENT_SECRET", uuid.uuid4().hex)
USERNAME = 'test_user'


def get_provider():
    """Get a configured OIDC provider."""
    configuration_information = {
        'issuer': ISSUER,
        'authorization_endpoint': "https://example.com",
        'jwks_uri': JWKS_URI,
        'token_endpoint': "https://example.com",
        'userinfo_endpoint': "https://example.com",
        'registration_endpoint': "https://example.com",
        'end_session_endpoint': "https://example.com",
        'scopes_supported': ['openid', 'profile'],
        'response_types_supported': ['code', 'code id_token', 'code token', 'code id_token token'],  # code and hybrid
        'response_modes_supported': ['query', 'fragment'],
        'grant_types_supported': ['authorization_code', 'implicit'],
        'subject_types_supported': ['pairwise'],
        'token_endpoint_auth_methods_supported': ['client_secret_basic'],
        'claims_parameter_supported': True
    }

    userinfo_db = Userinfo({USERNAME: {}})
    kid = '1549e0aef574d1c7bdd136c202b8d290580b165c'
    signing_key = RSAKey(key=import_rsa_key(RSA_KEY), alg='RS256', use='sig', kid=kid)

    client_info = {
        'client_id': CLIENT_ID,
        'client_id_issued_at': int(time.time()),
        'client_secret': CLIENT_SECRET,
        'redirect_uris': ['https://example.com'],
        'response_types': ['code'],
        'client_secret_expires_at': 0  # never expires
    }
    clients = {CLIENT_ID: client_info}
    auth_state = AuthorizationState(HashBasedSubjectIdentifierFactory('salt'))
    return Provider(signing_key, configuration_information,
                    auth_state, clients, userinfo_db)


def get_id_token():
    """Get a valid ID token."""
    provider = get_provider()
    response = provider.parse_authentication_request(f'response_type=code&client_id={CLIENT_ID}&scope=openid&redirect_uri=https://example.com')
    resp = provider.authorize(response, USERNAME)
    code = resp.to_dict()["code"]
    creds = f'{CLIENT_ID}:{CLIENT_SECRET}'
    creds = base64.urlsafe_b64encode(creds.encode('utf-8')).decode('utf-8')
    headers = dict(Authorization=f'Basic {creds}')
    extra_claims = {'foo': 'bar'}
    response = provider.handle_token_request(f'grant_type=authorization_code&code={code}&redirect_uri=https://example.com', headers, extra_id_token_claims=extra_claims)

    token = response["id_token"]
    if 'AWS_WEB_IDENTITY_TOKEN_FILE' in os.environ:
        with open(os.environ['AWS_WEB_IDENTITY_TOKEN_FILE'], 'w') as fid:
            fid.write(token)
    return token


def get_jwks_data():
    """Get the jkws data for the jwks lambda endpoint."""
    return get_provider().jwks


def get_config_data():
    """Get the config data for the openid config lambda endpoint."""
    return get_provider().provider_configuration.to_dict()


def get_user_id():
    """Get the user id (sub) that will be used for authorization."""
    return get_provider().authz_state.get_subject_identifier('pairwise', USERNAME, "example.com")


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument(dest='command', help="The command to run (config, jwks, token, user_id)")

    # Parse and print the results
    args = parser.parse_args()
    if args.command == 'jwks':
        print(get_jwks_data(), end='')
    elif args.command == 'config':
        print(get_config_data(), end='')
    elif args.command == 'token':
        print(get_id_token(), end='')
    elif args.command == 'user_id':
        print(get_user_id(), end='')
    else:
        raise ValueError('Command must be one of: (config, jwks, token, user_id)')
