#!/usr/bin/env bash

# Use the 0.0.0.0 address to ensure we bind to the container's network interface.
python3.11 -m venv .venv || exit 1
./.venv/bin/python -m mkdocs serve --dev-addr "0.0.0.0:8000" || exit 1
