#!/bin/zsh

set -euo pipefail

script_directory="${0:A:h}"
repository_directory="${script_directory:h}"
plist_path="${repository_directory}/Son/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${plist_path}")"
applications_directory="${SON_APPLICATIONS_DIR:-/Applications}"
launch_after_install="${SON_LAUNCH_AFTER_INSTALL:-1}"
archive_path="${repository_directory}/dist/Son-${version}.zip"
installed_app="${applications_directory}/Son.app"

if [[ ! -d /Applications/Xcode.app ]]; then
  print -u2 "Xcode is required. Install it from the Mac App Store, then run this command again."
  exit 1
fi

mkdir -p "${applications_directory}"
if [[ ! -w "${applications_directory}" ]]; then
  print -u2 "Cannot write to ${applications_directory}."
  print -u2 "Run the script from an administrator account or set SON_APPLICATIONS_DIR."
  exit 1
fi

print "Building Son ${version} from source…"
SON_ALLOW_UNSIGNED=1 \
SON_OUTPUT_DIR="${repository_directory}/dist" \
"${script_directory}/package-release.sh"

if [[ ! -f "${archive_path}" ]]; then
  print -u2 "Release archive was not produced at ${archive_path}."
  exit 1
fi

staging_directory="$(mktemp -d)"
trap 'rm -rf "${staging_directory}"' EXIT
/usr/bin/ditto -x -k "${archive_path}" "${staging_directory}"

if [[ ! -d "${staging_directory}/Son.app" ]]; then
  print -u2 "Son.app is missing from ${archive_path}."
  exit 1
fi

print "Installing Son in ${applications_directory}…"
/usr/bin/ditto "${staging_directory}/Son.app" "${installed_app}"
/usr/bin/codesign --verify --deep --strict --verbose=2 "${installed_app}"

if [[ "${launch_after_install}" == "1" ]]; then
  /usr/bin/open "${installed_app}"
fi

print "Son ${version} is installed at ${installed_app}."
