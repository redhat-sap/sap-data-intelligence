# This defines a function taking `pkgs` as parameter, and uses
# `nixpkgs` by default if no argument is passed to it.
#{ pkgs ? import <nixos-unstable-nixpkgs> { } }:
{ pkgs ? import <nixpkgs> { } }:

# This avoids typing `pkgs.` before each package name.
with pkgs;
let
  drv = callPackage ./default.nix { };
  goPackagePath = "github.com/redhat-sap-cop/sap-data-intelligence/operator";
in
drv.overrideAttrs (attrs: {
  src = null;
  nativeBuildInputs = [ govers go ] ++ attrs.nativeBuildInputs;

  buildInputs = [
    go
    jq
    jsonnet
    ocp4_8.openshift-client
    ocp4_8.openshift-install
    remarshal
    shellcheck
    operator-sdk
    golangci-lint
  ]; #++ attrs.buildInputs;

  shellHook = ''
    export  KUBECONFIG=$(pwd)/.kube/config

    echo 'Entering ${attrs.pname}'
    set -v
    #export GO111MODULE='on'
    unset GO111MODULE
    #export GOFLAGS=-mod=vendor
    unset GOFLAGS
    #go mod init ${goPackagePath}

    export GOPATH="$(pwd)/.go"
    export GOBIN="$GOPATH/bin"
    export GOCACHE=""
    export DOCKER_CMD="sudo podman"
    export PATH="$GOPATH/bin:$PATH"
    set +v
  '';
})
