#!/bin/bash

# Run once after cloning to install git hooks:
#   bash scripts/install_hooks.sh

cp scripts/hooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
echo "Git hooks installed."
