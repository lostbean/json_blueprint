{
  description = "Gleam development environment";

  inputs = {
    design-layer.url = "github:lostbean/design-layer";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
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
            "codegen/test/generated/*"
            "docs/design/*"
            "build/*"
            "codegen/build/*"
            ".ci-results/*"
          ];
        };

        # The upstream apps pin the renderer; authored imports also need its
        # generated local projection on a fresh checkout.
        designApp =
          name:
          let
            wrapper = pkgs.writeShellApplication {
              name = "design-gate-${name}";
              runtimeInputs = [ pkgs.coreutils ];
              text = ''
                project_layer() {
                  if [ -f "$1/design.typ" ]; then
                    mkdir -p "$1/.render"
                    cp -RL --remove-destination --no-preserve=mode ${
                      design-layer.packages.${system}.gate-bundle
                    }/render/. "$1/.render/"
                  fi
                }
                project_layer "''${1:-docs/design}"
                exec ${design-layer.apps.${system}.${name}.program} "$@"
              '';
            };
          in
          {
            type = "app";
            program = "${wrapper}/bin/design-gate-${name}";
          };
      in
      {
        apps.design-gate-check = designApp "check";
        apps.design-gate-render = designApp "render";
        apps.design-gate-context = designApp "context";

        formatter = treefmtEval.config.build.wrapper;
        checks.formatting = treefmtEval.config.build.check ./.;

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            gleam
            rebar3
            beam28Packages.erlang
            nodejs_24
            actionlint
            shellcheck
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
