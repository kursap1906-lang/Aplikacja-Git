#!/usr/bin/env bash
# Ponownie waliduje i uruchamia usługi; zatrzymuje wyłącznie własne procesy ze zmienionym fingerprintem.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec bash "$ROOT/scripts/dev-up.sh"
