#!/usr/bin/env bash
# İlk kurulum: git dışı CloudSecrets.swift yoksa örnekten boş kopya üretir, sonra Xcode projesini üretir.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f Shotmori/Cloud/CloudSecrets.swift ] || cp Shotmori/Cloud/CloudSecrets.swift.example Shotmori/Cloud/CloudSecrets.swift
xcodegen generate
