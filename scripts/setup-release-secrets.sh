#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
properties_file="$root_dir/android/key.properties"

for command in gh base64 keytool; do
  if ! command -v "$command" > /dev/null 2>&1; then
    echo "Required command not found: $command" >&2
    exit 1
  fi
done

if [[ ! -f "$properties_file" ]]; then
  echo "Missing $properties_file" >&2
  exit 1
fi

declare -A properties=()
while IFS='=' read -r key value || [[ -n "$key" ]]; do
  [[ -z "$key" || "$key" == \#* ]] && continue
  properties["${key%$'\r'}"]="${value%$'\r'}"
done < "$properties_file"

for key in storePassword keyPassword keyAlias storeFile; do
  if [[ -z "${properties[$key]:-}" ]]; then
    echo "Missing $key in android/key.properties" >&2
    exit 1
  fi
done

store_file="${properties[storeFile]}"
if [[ "$store_file" == '$HOME/'* ]]; then
  store_file="$HOME/${store_file#\$HOME/}"
elif [[ "$store_file" == '~/'* ]]; then
  store_file="$HOME/${store_file#\~/}"
elif [[ "$store_file" != /* ]]; then
  store_file="$root_dir/android/app/$store_file"
fi
if [[ ! -f "$store_file" ]]; then
  echo "Keystore not found: $store_file" >&2
  exit 1
fi
if ! keytool -list \
  -keystore "$store_file" \
  -alias "${properties[keyAlias]}" \
  -storepass "${properties[storePassword]}" > /dev/null 2>&1; then
  echo "Could not access keyAlias in the keystore. Check keyAlias and storePassword." >&2
  exit 1
fi

cd "$root_dir"
gh auth status

printf '%s' "${properties[storePassword]}" | gh secret set ANDROID_KEYSTORE_PASSWORD
printf '%s' "${properties[keyPassword]}" | gh secret set ANDROID_KEY_PASSWORD
printf '%s' "${properties[keyAlias]}" | gh secret set ANDROID_KEY_ALIAS
base64 < "$store_file" | tr -d '\n' | gh secret set ANDROID_KEYSTORE_BASE64

echo "Android signing secrets are configured. You can now use scripts/publish.sh."
