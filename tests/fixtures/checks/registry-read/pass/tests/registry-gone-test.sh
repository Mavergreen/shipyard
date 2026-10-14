#!/bin/sh
grep -q "cmake/packages" out && { echo "the registry came back"; exit 1; }
