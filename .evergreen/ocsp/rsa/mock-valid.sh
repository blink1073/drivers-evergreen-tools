#!/usr/bin/env bash
python3 ../ocsp_mock.py \
  --ca_file ca.pem \
  --ocsp_responder_cert ca.crt \
  --ocsp_responder_key ca.key \
   -p 8100 \
   -v
