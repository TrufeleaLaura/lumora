#!/usr/bin/env bash
# Pipes xcodebuild output through xcbeautify (GitHub annotations) when available.
if command -v xcbeautify >/dev/null 2>&1; then
  exec xcbeautify --renderer github-actions
else
  exec cat
fi
