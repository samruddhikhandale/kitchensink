#!/usr/bin/env bash
#-------------------------------------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See https://go.microsoft.com/fwlink/?linkid=2090316 for license information.
#-------------------------------------------------------------------------------------------------------------
#
# Docs: ::TODO
# Maintainer: The VS Code and Codespaces Teams
#
# Syntax: ./java-debian.sh [JDK version]

JAVA_VERSION=${1:-"17.0.1"}
export JAVA_HOME="/opt/java/lts"

set -e

# Ensure that login shells get the correct path if the user updated the PATH using ENV.
rm -f /etc/profile.d/00-restore-env.sh
echo "export PATH=${PATH//$(sh -lc 'echo $PATH')/\$PATH/\${JAVA_HOME}/bin" > /etc/profile.d/00-restore-env.sh
chmod +x /etc/profile.d/00-restore-env.sh

updaterc() {
    echo "Updating /etc/bash.bashrc and /etc/zsh/zshrc..."
    if [[ "$(cat /etc/bash.bashrc)" != *"$1"* ]]; then
        echo -e "$1" >> /etc/bash.bashrc
    fi
    if [ -f "/etc/zsh/zshrc" ] && [[ "$(cat /etc/zsh/zshrc)" != *"$1"* ]]; then
        echo -e "$1" >> /etc/zsh/zshrc
    fi
}

# Function to run apt-get if needed
apt_get_update_if_needed()
{
    if [ ! -d "/var/lib/apt/lists" ] || [ "$(ls /var/lib/apt/lists/ | wc -l)" = "0" ]; then
        echo "Running apt-get update..."
        apt-get update
    else
        echo "Skipping apt-get update."
    fi
}

# Checks if packages are installed and installs them if not
check_packages() {
    if ! dpkg -s "$@" > /dev/null 2>&1; then
        apt_get_update_if_needed
        apt-get -y install --no-install-recommends "$@"
    fi
}

# Use SDKMAN to install something using a partial version match
sdk_install() {
    local install_type=$1
    local requested_version=$2
    local prefix=$3
    local suffix="${4:-"\\s*"}"
    local full_version_check=${5:-".*-[a-z]+"}
    if [ "${requested_version}" = "none" ]; then return; fi
    # Blank will install latest stable version
    if [ "${requested_version}" = "lts" ] || [ "${requested_version}" = "default" ]; then
         requested_version=""
    elif echo "${requested_version}" | grep -oE "${full_version_check}" > /dev/null 2>&1; then
        echo "${requested_version}"
    else
        local regex="${prefix}\\K[0-9]+\\.[0-9]+\\.[0-9]+${suffix}"
        local version_list="$(. ${SDKMAN_DIR}/bin/sdkman-init.sh && sdk list ${install_type} 2>&1 | grep -oP "${regex}" | tr -d ' ' | sort -rV)"
        if [ "${requested_version}" = "latest" ] || [ "${requested_version}" = "current" ]; then
            requested_version="$(echo "${version_list}" | head -n 1)"
        else
            set +e
            requested_version="$(echo "${version_list}" | grep -E -m 1 "^${requested_version//./\\.}([\\.\\s]|$)")"
            set -e
        fi
        if [ -z "${requested_version}" ] || ! echo "${version_list}" | grep "^${requested_version//./\\.}$" > /dev/null 2>&1; then
            echo -e "Version $2 not found. Available versions:\n${version_list}" >&2
            exit 1
        fi
    fi
    su ${USERNAME} -c "umask 0002 && . ${SDKMAN_DIR}/bin/sdkman-init.sh && sdk install ${install_type} ${requested_version} && sdk flush archives && sdk flush temp"
}

export DEBIAN_FRONTEND=noninteractive

# Install dependencies
check_packages curl ca-certificates zip unzip sed

# Install sdkman if not installed
if [ ! -d "${SDKMAN_DIR}" ]; then
    # Create sdkman group, dir, and set sticky bit
    if ! cat /etc/group | grep -e "^sdkman:" > /dev/null 2>&1; then
        groupadd -r sdkman
    fi
    usermod -a -G sdkman ${USERNAME}
    umask 0002
    # Install SDKMAN
    curl -sSL "https://get.sdkman.io?rcupdate=false" | bash
    chown -R :sdkman ${SDKMAN_DIR}
    find ${SDKMAN_DIR} -type d | xargs -d '\n' chmod g+s
    # Add sourcing of sdkman into bashrc/zshrc files (unless disabled)
    updaterc "export SDKMAN_DIR=${SDKMAN_DIR}\n. \${SDKMAN_DIR}/bin/sdkman-init.sh"
fi

# Use Microsoft JDK for everything but JDK 8
jdk_distro="ms"
if echo "${JAVA_VERSION}" | grep -E '^8([\s\.]|$)' > /dev/null 2>&1; then
    jdk_distro="tem"
fi
sdk_install java ${JAVA_VERSION} "\\s*" "(\\.[a-z0-9]+)*-${jdk_distro}\\s*" ".*-[a-z]+$"

echo "Done!"
