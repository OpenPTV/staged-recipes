#!/usr/bin/env bash

# PLEASE NOTE: This script has been automatically generated by conda-smithy. Any changes here
# will be lost next time ``conda smithy rerender`` is run. If you would like to make permanent
# changes to this script, consider a proposal to conda-smithy so that other feedstocks can also
# benefit from the improvement.

set -xeuo pipefail

export FEEDSTOCK_ROOT="${FEEDSTOCK_ROOT:-/home/conda/staged-recipes}"
source "${FEEDSTOCK_ROOT}/.scripts/logging_utils.sh"

# This closes the matching `startgroup` on `run_docker_build.sh`
( endgroup "Start Docker" ) 2> /dev/null

( startgroup "Configuring conda" ) 2> /dev/null

export PYTHONUNBUFFERED=1
export CI_SUPPORT="/home/conda/staged-recipes-copy/.ci_support"

cat >~/.condarc <<CONDARC
always_yes: true

channels:
 - conda-forge

conda-build:
  root-dir: ${FEEDSTOCK_ROOT}/build_artifacts

pkgs_dirs:
  - ${FEEDSTOCK_ROOT}/build_artifacts/pkg_cache
  - /opt/conda/pkgs

show_channel_urls: true

solver: libmamba
CONDARC

# Workaround for errors related to "unsafe" directories:
# https://github.blog/2022-04-12-git-security-vulnerability-announced/#cve-2022-24765 
git config --global --add safe.directory "${FEEDSTOCK_ROOT}"

# Copy the host recipes folder so we don't ever muck with it
# Skip build_artifacts and other big items because it gets huge with time
mkdir -p ~/staged-recipes-copy
shopt -s extglob dotglob
cp -r "${FEEDSTOCK_ROOT}"/!(.|..|build_artifacts|.pixi|miniforge3|MacOSX*.sdk.tar.xz|SDKs|output) ~/staged-recipes-copy
shopt -u extglob dotglob

# Remove any macOS system files
find ~/staged-recipes-copy/recipes -maxdepth 1 -name ".DS_Store" -delete

# Find the recipes from main in this PR and remove them.
echo "Pending recipes."
ls -la ~/staged-recipes-copy/recipes
echo "Finding recipes merged in main and removing them from the build."
pushd "${FEEDSTOCK_ROOT}/recipes" > /dev/null
if [ "${CI:-}" != "" ]; then
    git fetch --force origin main:main
fi
shopt -s extglob dotglob
git ls-tree --name-only main -- !(example|example-v1)  | xargs -I {} sh -c "rm -rf ~/staged-recipes-copy/recipes/{} && echo Removing recipe: {}"
shopt -u extglob dotglob
popd > /dev/null

# Update environment
mv /opt/conda/conda-meta/history /opt/conda/conda-meta/history.$(date +%Y-%m-%d-%H-%M-%S)
echo > /opt/conda/conda-meta/history
micromamba install --root-prefix ~/.conda --prefix /opt/conda \
    --yes --override-channels --channel conda-forge --strict-channel-priority \
    --file "${FEEDSTOCK_ROOT}/environment.yaml"

setup_conda_rc "${FEEDSTOCK_ROOT}" "/home/conda/staged-recipes-copy/recipes" "${CI_SUPPORT}/${CONFIG}.yaml"
source run_conda_forge_build_setup

# yum installs anything from a "yum_requirements.txt" file that isn't a blank line or comment.
find ~/staged-recipes-copy/recipes -mindepth 2 -maxdepth 2 -type f -name "yum_requirements.txt" \
    | xargs -n1 cat | { grep -v -e "^#" -e "^$" || test $? == 1; } | \
    xargs -r /usr/bin/sudo -n yum install -y

# Make sure build_artifacts is a valid channel
conda index "${FEEDSTOCK_ROOT}/build_artifacts"

( endgroup "Configuring conda" ) 2> /dev/null

echo "Building all recipes"
python "${CI_SUPPORT}/build_all.py"

( startgroup "Inspecting artifacts" ) 2> /dev/null
# inspect_artifacts was only added in conda-forge-ci-setup 4.6.0; --all-packages in 4.9.3
command -v inspect_artifacts >/dev/null 2>&1 && inspect_artifacts --all-packages || echo "inspect_artifacts needs conda-forge-ci-setup >=4.9.3"
( endgroup "Inspecting artifacts" ) 2> /dev/null

( startgroup "Final checks" ) 2> /dev/null

touch "${FEEDSTOCK_ROOT}/build_artifacts/conda-forge-build-done"