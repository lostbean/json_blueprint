{
  description = "Go development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = {
    self,
    nixpkgs,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachDefaultSystem
    (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [];
        };
      in {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            gleam
          ];

          shellHook = ''
            echo "Gleam magic"
          '';
        };
      }
    );
}
