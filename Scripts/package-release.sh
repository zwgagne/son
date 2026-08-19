#!/bin/zsh

set -euo pipefail

script_directory="${0:A:h}"
repository_directory="${script_directory:h}"
plist_path="${repository_directory}/Son/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${plist_path}")"
output_directory="${SON_OUTPUT_DIR:-${repository_directory}/dist}"
derived_data_directory="${SON_DERIVED_DATA_DIR:-${repository_directory}/.build/release}"
developer_directory="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
signing_identity="${SON_SIGNING_IDENTITY:-}"
notary_profile="${SON_NOTARY_PROFILE:-}"

mkdir -p "${output_directory}" "${derived_data_directory}"

DEVELOPER_DIR="${developer_directory}" xcodebuild \
  -project "${repository_directory}/Son.xcodeproj" \
  -scheme Son \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "${derived_data_directory}" \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

built_app="${derived_data_directory}/Build/Products/Release/Son.app"
if [[ ! -d "${built_app}" ]]; then
  print -u2 "Son.app was not produced at ${built_app}"
  exit 1
fi

staging_directory="$(mktemp -d)"
trap 'rm -rf "${staging_directory}"' EXIT
staged_app="${staging_directory}/Son.app"
/usr/bin/ditto "${built_app}" "${staged_app}"

if [[ -n "${signing_identity}" ]]; then
  /usr/bin/codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --sign "${signing_identity}" \
    "${staged_app}"
else
  if [[ "${SON_ALLOW_UNSIGNED:-0}" != "1" ]]; then
    print -u2 "Set SON_SIGNING_IDENTITY to a Developer ID Application identity."
    print -u2 "For local packaging only, set SON_ALLOW_UNSIGNED=1."
    exit 1
  fi

  /usr/bin/codesign --force --deep --sign - "${staged_app}"
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "${staged_app}"

if [[ -n "${notary_profile}" ]]; then
  notarization_archive="${staging_directory}/Son-notarization.zip"
  /usr/bin/ditto -c -k --keepParent "${staged_app}" "${notarization_archive}"
  DEVELOPER_DIR="${developer_directory}" xcrun notarytool submit \
    "${notarization_archive}" \
    --keychain-profile "${notary_profile}" \
    --wait
  DEVELOPER_DIR="${developer_directory}" xcrun stapler staple "${staged_app}"
  DEVELOPER_DIR="${developer_directory}" xcrun stapler validate "${staged_app}"
elif [[ -n "${signing_identity}" && "${SON_SKIP_NOTARIZATION:-0}" != "1" ]]; then
  print -u2 "Set SON_NOTARY_PROFILE or SON_SKIP_NOTARIZATION=1."
  exit 1
fi

archive_name="Son-${version}.zip"
temporary_archive="${staging_directory}/${archive_name}"
final_archive="${output_directory}/${archive_name}"
/usr/bin/ditto -c -k --keepParent "${staged_app}" "${temporary_archive}"
/bin/mv -f "${temporary_archive}" "${final_archive}"

checksum="$(/usr/bin/shasum -a 256 "${final_archive}" | /usr/bin/awk '{print $1}')"
print "Archive: ${final_archive}"
print "SHA-256: ${checksum}"
