#!/usr/bin/env bash

#
# Copyright (C) 2025 Akash Yadav
#
# This file is part of The Scribe Project.
#
# Scribe is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published
# by the Free Software Foundation, either version 3 of the License,
# or (at your option) any later version.
#
# Scribe is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Scribe.  If not, see <https://www.gnu.org/licenses/>.
#

script=$(realpath "$0")
script_dir=$(dirname "$script")

# shellcheck source=common.sh
. "${script_dir}/common.sh"

declare -a PATCHES=(

  # Adds our own GPG keys
  "termux-keyring.patch"

  # Update mirror configurations
  "termux-tools-mirrors.patch"

  # Update motd
  "termux-tools-motd.patch"

  # Makes some of the packages depend on and link against libandroid-shmem.so
  # Required to fix some build failures
  "libdb-depend-on-android-shmem.patch"
  "libunbound-depend-on-android-shmem.patch"
  "libx11-depend-on-android-shmem.patch"

  # Fix dependencies in binutils-libs
  "binutils-libs-fix-dependencies.patch"

  # subversion fails to compile, complaining that the apr.h and other
  # headers could not be found. These headers are located in
  # $PREFIX/include/apr-1
  "subversion-missing-apr-includes.patch"

  # libuv has missing sources in their Makefile configuration.
  # This missing source issue was fixed in their CMake configuration,
  # so we force termux-packages to build using CMake instead of Makefile.
  "libuv-force-cmake-build.patch"

  # Changes for our version of bootstrap-*.zip files.
  # This also handles the process of creating a brotli archive
  # from the generated ZIP archive.
  "scripts-generate-bootstraps-CoGo-changes.patch"

  # Update package name in termux-tools
  "termux-tools-update-package-name.patch"

  # Cleanup OpenJDK packages
  "openjdk-17-cleanup.patch"
  "openjdk-21-cleanup.patch"
  "openjdk-25-cleanup.patch"

  # Cleanup vim to remove postinst scripts
  "vim-cleanup.patch"

  # Link pulseaudio against libiconv to resolve linker errors at build time
  "pulseaudio-link-against-libiconv.patch"

  # Ensure libacl is installed before coreutils
  "coreutils-depend-on-libacl.patch"

  # libapr-1.so needs to be linked against libandroid-shmem.so
  "apr-link-against-libandroid-shmem.patch"

  # Revert ASharedMemory changes from libandroid-shmem
  "libandroid-shmem-revert-a-shared-memory-patch.patch"

  # Use our keys to install dependencies
  "use-our-keys-to-install-deps.patch"
)

# ---------------------------------------------------------
# Script configuration
# ---------------------------------------------------------

COTG_ARCH=""
COTG_NO_BUILD="false"
COTG_INSTALL_DEPS="false"

usage() {
  echo "Script to build selected termux-packages for Code On the Go."
  echo ""
  echo "Usage: $0 -a ARCH [options] package..."
  echo ""
  echo "Options:"
  echo "  -a        Target architecture. Must be one of [${COTG_ALL_ARCHS}]."
  echo "  -n        Set up the build, but do not execute."
  echo "  -p        Application package name."
  echo "  -r        Package repository URL."
  echo "  -s        GPG key used for signing packages."
  echo "  -I        Prefer downloading packages from remote repository if versions match."
  echo "  -h        Show this help message and exit."
  echo ""
  echo "Packages may be comma-separated:"
  echo ""
  echo "  $0 -a aarch64 openjdk-25,unzip,libcurl"
  echo ""
  echo "Spaces after commas are supported:"
  echo ""
  echo "  $0 -a aarch64 'openjdk-25, unzip, libcurl'"
  echo ""
}

# ---------------------------------------------------------
# Setup termux-packages
# ---------------------------------------------------------

setup_termux_packages() {

  pushd "$TERMUX_PACKAGES_DIR" ||
    scribe_error_exit "Unable to pushd into termux-packages"

  # Change package name
  echo "Updating package name.."

  grep -rniF . \
    -e "${TERMUX_PACKAGE_NAME}" \
    -l \
    --exclude-dir=".git" |
    xargs -L1 sed -i \
      "s/${TERMUX_PACKAGE_NAME//./\\.}/${COTG_PACKAGE_NAME}/g" ||
    scribe_error_exit "Unable to update package name"

  # Remove existing keyrings
  echo "Removing existing GPG keys..."

  rm -rvf packages/termux-keyring/*.gpg

  # Add our own keyring
  echo "Adding our keyring..."

  cp "${COTG_GPG_KEY}" \
    "./packages/termux-keyring/$(basename "$COTG_GPG_KEY")"

  # Create termux-keyring.patch
  termux_keyring_patch="$script_dir/patches/termux-keyring.patch"

  sed \
    "s|@COTG_GPG_KEY@|$(basename "$COTG_GPG_KEY")|g" \
    "${termux_keyring_patch}.in" \
    > "$termux_keyring_patch"

  # Create termux-tools-update-package-name.patch
  termux_tools_update_package_name_patch="$script_dir/patches/termux-tools-update-package-name.patch"

  sed \
    "s|@TERMUX_PACKAGE_NAME@|$COTG_PACKAGE_NAME|g" \
    "${termux_tools_update_package_name_patch}.in" \
    > "$termux_tools_update_package_name_patch"

  # Apply patches
  for patch in "${PATCHES[@]}"; do

    scribe_info "Applying patch: ${patch}"

    if patch -p1 --no-backup-if-mismatch \
      < "$script_dir/patches/$patch" ||
      scribe_error_exit "Failed to apply '$patch'"
    then
      scribe_ok "Applied '$patch'"
    fi

  done

  # Update package repository
  grep -rnI . \
    -e "https://packages-cf.termux.dev/apt/termux-main" \
    -l |
    xargs -L1 sed -i \
      "s|https://packages-cf.termux.dev/apt/termux-main|${COTG_REPO}|g"

  # Mark as patched
  touch .scribe-patched

  popd ||
    scribe_error_exit "Unable to popd from termux-packages"
}

# ---------------------------------------------------------
# No arguments
# ---------------------------------------------------------

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

# ---------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------

while getopts "a:np:r:s:Ih" opt; do

  case "$opt" in

    a)
      COTG_ARCH="$OPTARG"
      ;;

    n)
      COTG_NO_BUILD="true"
      ;;

    p)
      COTG_PACKAGE_NAME="$OPTARG"
      ;;

    r)
      COTG_REPO="$OPTARG"
      ;;

    s)
      COTG_GPG_KEY="$(realpath "$OPTARG")"
      ;;

    I)
      COTG_INSTALL_DEPS="true"
      ;;

    h)
      usage
      exit 0
      ;;

    *)
      echo "Invalid option." >&2
      usage
      exit 1
      ;;

  esac

done

shift $((OPTIND - 1))

# ---------------------------------------------------------
# Parse ONLY explicitly requested packages
#
# Example:
#
#   openjdk-25,unzip,libcurl
#
# becomes:
#
#   openjdk-25
#   unzip
#   libcurl
# ---------------------------------------------------------

declare -a EXTRA_PACKAGES=()

for arg in "$@"; do

  IFS=',' read -ra PACKAGES <<< "$arg"

  for package in "${PACKAGES[@]}"; do

    # Remove leading whitespace
    package="${package#"${package%%[![:space:]]*}"}"

    # Remove trailing whitespace
    package="${package%"${package##*[![:space:]]}"}"

    if [[ -n "$package" ]]; then
      EXTRA_PACKAGES+=("$package")
    fi

  done

done

# ---------------------------------------------------------
# Validate architecture
# ---------------------------------------------------------

if [[ "$COTG_ALL_ARCHS" != *" $COTG_ARCH "* ]]; then
  scribe_error_exit "Unsupported arch: '$COTG_ARCH'"
fi

# ---------------------------------------------------------
# Validate package name
# ---------------------------------------------------------

if [[ -z "${COTG_PACKAGE_NAME}" ]]; then
  scribe_error_exit "A package name must be specified."
fi

# ---------------------------------------------------------
# Validate repository
# ---------------------------------------------------------

if [[ -z "${COTG_REPO}" ]]; then
  scribe_error_exit "A package repository URL must be specified."
fi

# ---------------------------------------------------------
# Validate GPG key
# ---------------------------------------------------------

if ! [[ -f "${COTG_GPG_KEY}" ]]; then
  scribe_error_exit \
    "${COTG_GPG_KEY} does not exist or is not a file."
fi

# ---------------------------------------------------------
# Validate selected packages
# ---------------------------------------------------------

if [[ ${#EXTRA_PACKAGES[@]} -eq 0 ]]; then
  scribe_error_exit "No packages specified."
fi

# ---------------------------------------------------------
# Remove duplicate packages while preserving order
# ---------------------------------------------------------

declare -A SEEN_PACKAGES
declare -a UNIQUE_PACKAGES=()

for package in "${EXTRA_PACKAGES[@]}"; do

  if [[ -z "${SEEN_PACKAGES[$package]+x}" ]]; then

    UNIQUE_PACKAGES+=("$package")
    SEEN_PACKAGES["$package"]=1

  fi

done

EXTRA_PACKAGES=("${UNIQUE_PACKAGES[@]}")

# ---------------------------------------------------------
# Display selected packages
# ---------------------------------------------------------

echo
echo "========================================"
echo "Selected packages"
echo "========================================"

printf '  - %s\n' "${EXTRA_PACKAGES[@]}"

echo "========================================"
echo

# ---------------------------------------------------------
# Output directory
# ---------------------------------------------------------

OUTPUT_DIR="${COTG_OUTPUT_DIR}/${COTG_ARCH}"

mkdir -p "$OUTPUT_DIR"

# ---------------------------------------------------------
# Check required commands
# ---------------------------------------------------------

scribe_check_command "git"
scribe_check_command "patch"
scribe_check_command "tee"
scribe_check_command "time"

# ---------------------------------------------------------
# Setup and patch termux-packages
# ---------------------------------------------------------

if ! [[ -f "$TERMUX_PACKAGES_DIR/.scribe-patched" ]]; then
  setup_termux_packages
fi

# ---------------------------------------------------------
# Symlink termux-packages/output
# ---------------------------------------------------------

if ! [[ -L "$TERMUX_PACKAGES_DIR/output" ]]; then
  rm -rf "$TERMUX_PACKAGES_DIR/output"
fi

rm -vf "$TERMUX_PACKAGES_DIR/output" || true

ln -sf \
  "$OUTPUT_DIR" \
  "$TERMUX_PACKAGES_DIR/output"

# ---------------------------------------------------------
# No-build mode
# ---------------------------------------------------------

if [[ "$COTG_NO_BUILD" == "true" ]]; then
  scribe_ok "Skipping build."
  exit 0
fi

# ---------------------------------------------------------
# Build ONLY selected packages
#
# IMPORTANT:
#
# COTG_PACKAGES from packages.sh is intentionally NOT used.
#
# The only packages passed to build-package.sh are the ones
# explicitly provided through the command line.
# ---------------------------------------------------------

pushd "$TERMUX_PACKAGES_DIR" ||
  scribe_error_exit "Unable to pushd into termux-packages"

echo
echo "========================================"
echo "Building packages"
echo "========================================"

echo "Architecture: ${COTG_ARCH}"
echo

printf '  - %s\n' "${EXTRA_PACKAGES[@]}"

echo
echo "========================================"
echo

declare -a BUILD_ARGS=(
  "-a"
  "${COTG_ARCH}"

  "-o"
  "${OUTPUT_DIR}"
)

# Prefer remote repository packages when requested
if [[ "$COTG_INSTALL_DEPS" == "true" ]]; then
  BUILD_ARGS+=("-I")
fi

# ---------------------------------------------------------
# CRITICAL:
#
# Only explicitly requested packages are added here.
# No COTG_PACKAGES.
# ---------------------------------------------------------

BUILD_ARGS+=("${EXTRA_PACKAGES[@]}")

echo "Running:"
printf '  %q' ./build-package.sh
printf ' %q' "${BUILD_ARGS[@]}"
echo
echo

# ---------------------------------------------------------
# Execute build
# ---------------------------------------------------------

if ! {
  time ./build-package.sh "${BUILD_ARGS[@]}" |&
    tee "$OUTPUT_DIR/build.log"
}; then

  scribe_error_exit "Failed to build selected packages."

fi

popd ||
  scribe_error_exit "Unable to popd from termux-packages"

# ---------------------------------------------------------
# Build summary
# ---------------------------------------------------------

echo
echo "========================================"
echo "Build completed successfully"
echo "========================================"
echo

echo "Requested packages:"
printf '  - %s\n' "${EXTRA_PACKAGES[@]}"

echo
echo "Generated .deb packages:"

find "$OUTPUT_DIR" \
  -maxdepth 1 \
  -type f \
  -name "*.deb" \
  -printf '  %f\n' |
  sort

echo
echo "Output directory:"
echo "  $OUTPUT_DIR"

echo
echo "Build log:"
echo "  $OUTPUT_DIR/build.log"

echo
echo "========================================"
