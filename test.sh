#!/bin/zsh
# Generates the project and runs the tests. Prints only errors and test results.
cd "${0:A:h}"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate --quiet
xcodebuild test -scheme Shep -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData 2>&1 |
  grep -E "error:|✘|✔ Test run|\*\* TEST"
