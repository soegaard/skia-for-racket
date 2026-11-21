#!/usr/bin/env python3
"""Require byte-identical independent native/font archives and Racket checksums."""
import argparse
from pathlib import Path
from native_packages import need, read_json

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('first', type=Path)
    p.add_argument('second', type=Path)
    args = p.parse_args()
    first = read_json(args.first / 'native-artifacts.json')
    second = read_json(args.second / 'native-artifacts.json')
    need(first == second, 'native assembly receipts differ')
    for receipt in first['artifacts']:
        for suffix in ('', '.CHECKSUM'):
            name = receipt['archive'] + suffix
            need((args.first / name).read_bytes() == (args.second / name).read_bytes(), 'non-reproducible archive: ' + name)
    print('Four native/font packages and Racket checksums reproduce byte for byte.')
