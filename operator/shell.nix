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
  ]; #++ attrs.buildInputs;

  shellHook = ''
    export  KUBECONFIG=$(pwd)/.kube/config

    echo 'Entering ${attrs.pname}'
    set -v
    export GOPATH="$(pwd)/.go"
    export GOCACHE=""
    export GO111MODULE='on'
    export GOFLAGS=-mod=vendor
    go mod init ${goPackagePath}
    export DOCKER_CMD="sudo podman"
    set +v
  '';
})
