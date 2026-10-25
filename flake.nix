{
  description = "Gleam development environment";

  inputs = {
    design-layer.url = "github:lostbean/design-layer/main";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    treefmt-nix.follows = "design-layer/treefmt-nix";
  };
  outputs =
    {
      design-layer,
      self,
      nixpkgs,
      flake-utils,
      treefmt-nix,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ ];
        };

        treefmtEval = treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          programs.gleam.enable = true;
          programs.nixfmt.enable = true;
          programs.shfmt.enable = true;
          programs.ruff-format.enable = true;
          programs.erlfmt.enable = true;
          programs.prettier = {
            enable = true;
            includes = [
              "*.mjs"
              "*.yml"
              "*.yaml"
            ];
          };
          # Preserve oracle bytes, generated fixtures and rendered evidence.
          settings.global.excludes = [
            "test/oracle/*"
            "test/schema_manifest.json"
            "test/generated/*"
            "docs/design/*"
            "build/*"
            "examples/codegen/build/*"
            "examples/codegen/generate/build/*"
            "examples/build/*"
            ".ci-results/*"
          ];
        };

      in
      {
        apps.snips = design-layer.apps.${system}.snips;
        apps.design-gate-check = design-layer.apps.${system}.check;
        apps.design-gate-render = design-layer.apps.${system}.render;
        apps.design-gate-context = design-layer.apps.${system}.context;

        formatter = treefmtEval.config.build.wrapper;
        checks.formatting = treefmtEval.config.build.check ./.;

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            gleam
            beam29Packages.rebar3
            beam29Packages.erlang
            nodejs_24
            ruff
            findutils
            (python3.withPackages (pythonPackages: [ pythonPackages.jsonschema ]))
          ];

          shellHook = ''
            echo "Gleam magic"
          '';
        };
      }
    );
}
