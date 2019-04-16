#!/usr/bin/env bash
echo "Re-setting Demo"

# Force push HEAD to baseline
git reset --hard origin/master
git push com master -f
