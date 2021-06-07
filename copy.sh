#!/bin/zsh -x
rm -rf .devcontainer
rm -rf test-project

cp -r ../vscode-dev-containers/containers/codespaces-linux/ .
