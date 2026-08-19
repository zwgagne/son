#!/bin/zsh

set -euo pipefail

if [[ $# -ne 1 ]]; then
  print -u2 "Usage: Scripts/update-cask.sh path/to/Son-VERSION.zip"
  exit 64
fi

archive_path="${1:A}"
archive_name="${archive_path:t}"
if [[ ! "${archive_name}" =~ '^Son-([0-9]+\.[0-9]+\.[0-9]+)\.zip$' ]]; then
  print -u2 "Expected an archive named Son-VERSION.zip"
  exit 65
fi

version="${match[1]}"
checksum="$(/usr/bin/shasum -a 256 "${archive_path}" | /usr/bin/awk '{print $1}')"
script_directory="${0:A:h}"
cask_path="${script_directory:h}/Casks/son.rb"

/usr/bin/sed -E -i '' "s/^  version \"[^\"]+\"/  version \"${version}\"/" "${cask_path}"
/usr/bin/sed -E -i '' "s/^  sha256 \"[0-9a-f]+\"/  sha256 \"${checksum}\"/" "${cask_path}"

print "Updated ${cask_path} to Son ${version} (${checksum})"
