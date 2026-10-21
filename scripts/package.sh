#!/bin/bash
set -euo pipefail

# 构建无需开发者账号的未签名 IPA，供自行签名安装和开源发布。
package_unsigned() {
    cd "$(dirname "$0")/.."
    xcodegen generate
    xcodebuild archive -project HushNest.xcodeproj -scheme HushNest \
        -configuration Release -destination 'generic/platform=iOS' \
        -archivePath build/Unsigned.xcarchive CODE_SIGNING_ALLOWED=NO
    mkdir -p build/unsigned/Payload
    ditto build/Unsigned.xcarchive/Products/Applications/HushNest.app build/unsigned/Payload/HushNest.app
    ditto -c -k --norsrc --noextattr --keepParent build/unsigned/Payload build/HushNest-unsigned.ipa
}

package_unsigned
