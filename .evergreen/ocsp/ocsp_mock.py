#! /usr/bin/env python3
"""
Python script to interface as a mock OCSP responder.
"""

import argparse
import logging
import os
import sys

sys.path.append(os.path.join(os.getcwd(), "src", "third_party", "mock_ocsp_responder"))

import mock_ocsp_responder
from waitress import serve


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(description="MongoDB Mock OCSP Responder.")

    parser.add_argument(
        "-p", "--port", type=int, default=8080, help="Port to listen on"
    )

    parser.add_argument(
        "-b", "--bind_ip", type=str, default="127.0.0.1", help="IP to listen on"
    )

    parser.add_argument(
        "--ca_file", type=str, required=True, help="CA file for OCSP responder"
    )

    parser.add_argument(
        "-v", "--verbose", action="count", help="Enable verbose tracing"
    )

    parser.add_argument(
        "--ocsp_responder_cert",
        type=str,
        required=True,
        help="OCSP Responder Certificate",
    )

    parser.add_argument(
        "--ocsp_responder_key", type=str, required=True, help="OCSP Responder Keyfile"
    )

    parser.add_argument(
        "--fault",
        choices=[
            mock_ocsp_responder.FAULT_REVOKED,
            mock_ocsp_responder.FAULT_UNKNOWN,
            None,
        ],
        default=None,
        type=str,
        help="Specify a specific fault to test",
    )

    parser.add_argument(
        "--next_update_seconds",
        type=int,
        default=32400,
        help="Specify how long the OCSP response should be valid for",
    )

    args = parser.parse_args()
    level = logging.DEBUG if args.verbose else logging.INFO
    logging.basicConfig(level=level, format="%(asctime)s %(levelname)-8s %(message)s")

    mock_ocsp_responder.logger.info("Initializing OCSP Responder")
    mock_ocsp_responder.init_responder(
        issuer_cert=args.ca_file,
        responder_cert=args.ocsp_responder_cert,
        responder_key=args.ocsp_responder_key,
        fault=args.fault,
        next_update_seconds=args.next_update_seconds,
    )

    serve(mock_ocsp_responder.app, host=args.bind_ip, port=args.port)
    mock_ocsp_responder.logger.info("Shutting down OCSP Responder")


if __name__ == "__main__":
    main()
