#!/usr/bin/env python3
"""Local CSR/P12 helper. No network, account login or automatic uploads."""
import argparse
from getpass import getpass
from pathlib import Path
import os
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID


def password(prompt):
    value = getpass(prompt)
    if not value or value != getpass('Passwort wiederholen: '):
        raise ValueError('Passwörter sind leer oder stimmen nicht überein')
    return value.encode('utf-8')


def write_new(path, data):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, 'wb') as f:
        f.write(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['csr', 'p12'])
    args = parser.parse_args()
    folder = Path(__file__).resolve().parent.parent / 'signing-local'
    folder.mkdir(mode=0o700, exist_ok=True)
    key_path = folder / 'distribution-private.pem'
    if args.mode == 'csr':
        csr_path = folder / 'distribution.certSigningRequest'
        if key_path.exists() or csr_path.exists():
            raise FileExistsError('Existing signing material will not be overwritten')
        secret = password('Neues lokales Schlüsselpasswort: ')
        key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        csr = x509.CertificateSigningRequestBuilder().subject_name(x509.Name([
            x509.NameAttribute(NameOID.COMMON_NAME, 'LoRaLab iOS Distribution')
        ])).sign(key, hashes.SHA256())
        write_new(key_path, key.private_bytes(serialization.Encoding.PEM,
                  serialization.PrivateFormat.PKCS8, serialization.BestAvailableEncryption(secret)))
        write_new(csr_path, csr.public_bytes(serialization.Encoding.PEM))
        print('Public CSR created:', csr_path)
        print('Private key remains encrypted locally. Upload only the CSR to Apple.')
    else:
        target = folder / 'distribution.p12'
        if target.exists():
            raise FileExistsError('Existing P12 will not be overwritten')
        key = serialization.load_pem_private_key(key_path.read_bytes(),
                    password=getpass('Lokales Schlüsselpasswort: ').encode('utf-8'))
        cert = x509.load_der_x509_certificate((folder / 'distribution.cer').read_bytes())
        if key.public_key().public_numbers() != cert.public_key().public_numbers():
            raise ValueError('Apple certificate does not match the local private key')
        secret = password('Neues P12-Passwort: ')
        write_new(target, pkcs12.serialize_key_and_certificates(b'LoRaLab Apple Distribution',
                  key, cert, None, serialization.BestAvailableEncryption(secret)))
        print('Password-protected P12 created:', target)


if __name__ == '__main__':
    main()
