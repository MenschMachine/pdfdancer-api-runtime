#!/bin/bash

# Resolve the directory where the script itself is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Parent directory of the script
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

rsync -av /Users/michael/Code/TFC/pdfdancer/pdfdancer-api/_main/scripts "$PARENT_DIR"
