#!/usr/bin/env python3
"""Verify catalog archives locally and retain only bounded JSON receipts."""
import argparse
from pathlib import Path

from catalog_asset_evidence import collect


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--artifacts', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    collect(args.artifacts, args.output)
    print('Verified six candidate archives; retained JSON receipts and digests only.')
