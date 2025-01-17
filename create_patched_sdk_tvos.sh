#!/usr/bin/env bash

print_usage() {
    printf "Usage: $(basename $0) {use_simulator} {sdks_output_path} {overwrite_existing} {no_warnings} {tbd_tool_path} {xcode_installation_path}\n"
    printf "Note: {} options are optional to provide, and can be ignored with a '-'\n"
}

ignored() {
    if [[ $1 == "-" ]]; then
        return 0
    else
        return 1
    fi
}

if [[ $1 == "-h" ]]; then
    print_usage
    exit 0
fi

sdks_output_path="$2"
if [[ $# -lt 2 ]] || ignored $sdks_output_path; then
    if [[ -z $THEOS ]]; then
        printf 'No Theos installation found. Please either install Theos or provide a path to an sdks directory\n\n'
        print_usage

        exit 1
    fi
    sdks_output_path="$THEOS/sdks"
fi

if ! [[ -d $sdks_output_path ]]; then
    mkdir -p "$sdks_output_path"
fi

# tbd info
version="v3"

archs_option=("--replace-archs" arm64)
tbd_options=("--allow-private-objc-symbols" "--ignore-missing-exports")
#write_options=("--maintain-directories" "--replace-path-extension")
write_options=("--preserve-subdirs")

no_overwrite="--no-overwrite"
if [[ $# -gt 2 ]] && ! ignored $3; then
    no_overwrite=""
fi

no_warnings=""
if [[ $# -gt 3 ]] && ! ignored $4; then
    no_warnings="--dont-print-warnings"
fi

tbd_tool="$5"
if [[ $# -lt 5 ]] || ignored $tbd_tool; then
    tbd_tool="tbd"
    tbd_exists=$(command -v $tbd_tool)

    if [[ -z $tbd_exists ]]; then
        printf 'No installation of tbd found. Please install the latest release of tbd from here; https://github.com/inoahdev/tbd/releases or provide a path to a tbd installation\n\n'
        print_usage

        exit 1
    fi
else
    tbd_exists=$(command -v "$tbd_tool")
    if [[ -z $tbd_exists ]]; then
        printf "Provided tbd-tool (%s) doesn't exist or isn't executable\n" "$tbd_tool"
        exit 1
    fi
fi

use_simulator="$1"
if [[ $# -lt 1 ]]; then
    use_simulator="-"
fi

xcode_developer_path="$6/Contents/Developer"
if [[ $# -lt 6 || $xcode_developer_path == "/Contents/Developer" ]]; then
    xcode_developer_path=$(xcode-select -p)
fi

if [[ -z $xcode_developer_path ]]; then
    printf 'No Xcode installation found. Please either install Xcode or provide a path to an Xcode installation\n\n'
    print_usage

    exit 1
fi

xcode_sim_runtime_path="$xcode_developer_path/Platforms/AppleTVOS.platform/Library/Developer/CoreSimulator/Profiles/Runtimes/tvOS.simruntime/Contents/Resources/RuntimeRoot"
xcode_default_sdk_path="$xcode_developer_path/Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS.sdk"

preferred_xcode_sdk_path=""
for xcode_sdk_path in "$xcode_developer_path/Platforms/AppleTVOS.platform/Developer/SDKs/"*; do
    xcode_sdk_real=$(realpath "$xcode_sdk_path")

    if [[ $xcode_sdk_real == $xcode_default_sdk_path ]]; then
        preferred_xcode_sdk_path=$xcode_sdk_path
    fi
done

if [[ -z $preferred_xcode_sdk_path ]]; then
    printf 'Failed to find sdk for simulator runtime\n'
    exit 1
fi

preferred_xcode_sdk_name=$(basename $preferred_xcode_sdk_path)

xcode_sdk_tvos_version=${preferred_xcode_sdk_name:9} # Remove 'AppleTVOS' in front of sdk name
xcode_sdk_tvos_version=${xcode_sdk_tvos_version%????} # Remove '.sdk' at back of sdk name

sdks_output_path_single_sdk_path=""

device_support_dir="$HOME/Library/Developer/Xcode/tvOS DeviceSupport/"
if [[ -d $device_support_dir ]] && ignored $use_simulator; then
    for symbols_path in "$device_support_dir"*; do
        if ! [[ -d $symbols_path ]]; then
            continue
        fi

        tvos_version="$(basename "$symbols_path" | grep -o "\d\+\(\.\d\+\)\{1,2\}")"
        sdk_name=$(printf "AppleTVOS%s.sdk" $tvos_version)

        symbols_actual_path="$symbols_path/Symbols/System"
        if ! [[ -d $symbols_actual_path ]]; then
            printf "Symbols for tvOS %s don't exist\n" "$tvos_version"
            continue
        fi

        sdks_output_path_single_sdk_path="$sdks_output_path/$sdk_name"
        if [[ -d $sdks_output_path_single_sdk_path ]]; then
            printf 'SDK for tvOS %s already exists\n' "$tvos_version"
            continue
        fi

        printf 'Creating SDK for tvOS %s ...\n' "$tvos_version"

        if [[ $xcode_sdk_tvos_version != $tvos_version ]]; then
            printf "Warning: Xcode SDK for tvOS %s will be used as a base for sdk for tvOS %s\n" $xcode_sdk_tvos_version "$tvos_version"
        fi

        mkdir -p "$sdks_output_path_single_sdk_path"
        cp -R "$xcode_default_sdk_path/"* "$sdks_output_path_single_sdk_path"

        "$tbd_tool" \
            -p $no_warnings "${tbd_options[@]}" "${archs_option[@]}" -v $version -r all "$symbols_actual_path" \
            -o "${write_options[@]}" $no_overwrite "$sdks_output_path_single_sdk_path/System"

        if [[ $? -ne 0 ]]; then
            printf 'Failed to create tbds from Symbols directory for tvOS %s\n' $tvos_version
        fi
    done
else
    if ignored $use_simulator; then
        printf 'No DeviceSupport binaries found, falling back to dumping from simulator runtime binaries\n'
    fi

    sdks_output_path_single_sdk_path="$sdks_output_path/$preferred_xcode_sdk_name"
    if [[ -d $sdks_output_path_single_sdk_path ]]; then
        printf 'SDK for tvOS %s already exists\n' $xcode_sdk_tvos_version
        exit 1
    fi

    printf 'Creating sdk for tvOS %s ...\n' "$xcode_sdk_tvos_version"

    mkdir -p "$sdks_output_path_single_sdk_path"
    cp -R "$xcode_default_sdk_path/"* "$sdks_output_path_single_sdk_path"

    parse_paths=("-p" "-r" "$xcode_sim_runtime_path/Developer"
                 "-p" "-r" "$xcode_sim_runtime_path/System"
                 "-p" "-r" "$xcode_sim_runtime_path/Library")

    write_paths=("-o" "${write_options[@]}" $no_overwrite "$sdks_output_path_single_sdk_path/Developer"
                 "-o" "${write_options[@]}" $no_overwrite "$sdks_output_path_single_sdk_path/System"
                 "-o" "${write_options[@]}" $no_overwrite "$sdks_output_path_single_sdk_path/Library")

    "$tbd_tool" "${parse_paths[@]}" "${write_paths[@]}" $no_warnings "${tbd_options[@]}" "${archs_option[@]}" -v $version

    if [[ $? -ne 0 ]]; then
        printf 'Failed to create tbds from AppleTVSimulator runtime for tvOS %s\n' $xcode_sdk_tvos_version
    fi
fi
