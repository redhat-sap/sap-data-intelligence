{ buildGoModule                                                                                                               
, nix-gitignore
}:
   
buildGoModule {
  pname = "sdi-operator";
  version = "0.2.0";
  src = nix-gitignore.gitignoreSource [ ] ./.;
  #goPackagePath = "github.com/miminar/sdimetrics";
  #modSha256 = "0000000000000000000000000000000000000000000000000000";
  #vendorSha256 = "0000000000000000000000000000000000000000000000000000";
  vendorSha256 = null;
}

