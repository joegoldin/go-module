{
  description = ''
    A garnix module for projects using Go.

    Build your Go packages with `buildGoModule`, run `go test` and `go vet`, check formatting with `gofmt`, and optionally deploy a web server.

    [Source](https://github.com/joegoldin/go-module).
  '';

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
  inputs.garnix-lib.url = "github:joegoldin/garnix-lib";
  inputs.garnix-lib.inputs.nixpkgs.follows = "nixpkgs";

  outputs =
    { self, nixpkgs, garnix-lib }:
    {
      garnixModules.default =
        {
          pkgs,
          lib,
          config,
          ...
        }:
        let
          webServerSubmodule.options = {
            command =
              lib.mkOption {
                type = lib.types.nonEmptyStr;
                description = "The command to run to start the server in production.";
                example = "server --port \"$PORT\"";
              }
              // {
                name = "server command";
              };

            port = lib.mkOption {
              type = lib.types.port;
              description = "Port to forward incoming HTTP requests to. The server command has to listen on this port. This also sets the PORT environment variable for the server command.";
              default = 8000;
            };

            path =
              lib.mkOption {
                type = lib.types.nonEmptyStr;
                description = "Path your Go server will be hosted on.";
                default = "/";
              }
              // {
                name = "API path";
              };
          };

          goSubmodule.options = {
            src =
              lib.mkOption {
                type = lib.types.path;
                description = "A path to the directory containing `go.mod`, `go.sum`, and your Go sources.";
                example = "./.";
              }
              // {
                name = "source directory";
              };

            goVersion =
              lib.mkOption {
                type = lib.types.str;
                description = "The Go toolchain version to build with (maps to nixpkgs `go_<major>_<minor>`, falling back to the default `go`).";
                default = "1.23";
                example = "1.22";
              }
              // {
                name = "Go version";
              };

            vendorHash = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              description = "The hash of the vendored Go module dependencies. Use `null` when the project has no external dependencies, or `lib.fakeHash` to discover the correct value on first build.";
              default = null;
              example = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
            };

            subPackages = lib.mkOption {
              type = lib.types.nullOr (lib.types.listOf lib.types.str);
              description = "Which subpackages (relative import paths) to build and install. `null` builds everything.";
              default = null;
              example = [ "./cmd/server" ];
            };

            ldflags = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              description = "Extra `-ldflags` passed to `go build`.";
              default = [ ];
              example = [ "-s" "-w" ];
            };

            tags = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              description = "Go build tags to enable.";
              default = [ ];
            };

            vet = lib.mkOption {
              type = lib.types.bool;
              description = "Whether to run `go vet ./...` as part of the test check.";
              default = true;
            };

            webServer = lib.mkOption {
              type = lib.types.nullOr (lib.types.submodule webServerSubmodule);
              description = "Whether to build a server configuration based on this project and deploy it to the garnix cloud.";
              default = null;
            };

            devTools =
              lib.mkOption {
                type = lib.types.listOf lib.types.package;
                description = "A list of packages to make available in the devshell for this project. This is useful for things like LSPs, formatters, etc.";
                default = [ ];
              }
              // {
                name = "development tools";
              };

            buildDependencies = lib.mkOption {
              type = lib.types.listOf lib.types.package;
              description = ''
                A list of additional dependencies required to build this package. They are made available in the devshell, and at build time.

                (It's not necessary to include Go module dependencies manually, these are fetched via `vendorHash`.)
              '';
              default = [ ];
            };

            runtimeDependencies = lib.mkOption {
              type = lib.types.listOf lib.types.package;
              description = "A list of dependencies required at runtime. They are made available in the devshell, at build time, and are available on the server at runtime.";
              default = [ ];
            };
          };

          goPackageFor =
            projectConfig:
            let
              attr = "go_" + builtins.replaceStrings [ "." ] [ "_" ] projectConfig.goVersion;
            in
            pkgs.${attr} or pkgs.go;

          buildGoModuleFor = projectConfig: pkgs.buildGoModule.override { go = goPackageFor projectConfig; };

          baseArgsFor = name: projectConfig: {
            pname = name;
            version = "0.1.0";
            src = projectConfig.src;
            vendorHash = projectConfig.vendorHash;
            ldflags = projectConfig.ldflags;
            tags = projectConfig.tags;
            nativeBuildInputs = projectConfig.buildDependencies;
            buildInputs = projectConfig.runtimeDependencies;
          }
          // lib.optionalAttrs (projectConfig.subPackages != null) {
            subPackages = projectConfig.subPackages;
          };
        in
        {
          options = {
            go = lib.mkOption {
              type = lib.types.attrsOf (lib.types.submodule goSubmodule);
              description = "An attrset of Go projects to generate.";
            };
          };

          config = {
            packages = builtins.mapAttrs (
              name: projectConfig:
              (buildGoModuleFor projectConfig) ((baseArgsFor name projectConfig) // { doCheck = false; })
            ) config.go;

            checks = lib.foldlAttrs (
              acc: name: projectConfig:
              acc
              // {
                "${name}-test" = (buildGoModuleFor projectConfig) (
                  (baseArgsFor name projectConfig)
                  // {
                    doCheck = true;
                    preCheck = lib.optionalString projectConfig.vet "go vet ./...\n";
                  }
                );

                "${name}-gofmt" =
                  pkgs.runCommand "${name}-gofmt"
                    {
                      nativeBuildInputs = [ (goPackageFor projectConfig) ];
                    }
                    ''
                      unformatted="$(cd ${projectConfig.src} && gofmt -l .)"
                      if [ -n "$unformatted" ]; then
                        echo "The following files are not gofmt-formatted:"
                        echo "$unformatted"
                        exit 1
                      fi
                      mkdir "$out"
                    '';
              }
            ) { } config.go;

            devShells = builtins.mapAttrs (
              name: projectConfig:
              pkgs.mkShell {
                packages = [
                  (goPackageFor projectConfig)
                  pkgs.gotools
                ]
                ++ projectConfig.devTools
                ++ projectConfig.buildDependencies
                ++ projectConfig.runtimeDependencies;
              }
            ) config.go;

            nixosConfigurations =
              let
                hasAnyWebServer = builtins.any (projectConfig: projectConfig.webServer != null) (
                  builtins.attrValues config.go
                );
              in
              lib.mkIf hasAnyWebServer {
                default =
                  [
                    {
                      services.nginx = {
                        enable = true;
                        recommendedProxySettings = true;
                        recommendedOptimisation = true;
                        virtualHosts.default = {
                          default = true;
                        };
                      };

                      networking.firewall.allowedTCPPorts = [ 80 ];
                    }
                  ]
                  ++ (builtins.attrValues (
                    builtins.mapAttrs (
                      name: projectConfig:
                      lib.mkIf (projectConfig.webServer != null) {
                        environment.systemPackages = projectConfig.runtimeDependencies;

                        systemd.services.${name} = {
                          description = "${name} Go garnix module";
                          wantedBy = [ "multi-user.target" ];
                          after = [ "network-online.target" ];
                          wants = [ "network-online.target" ];
                          environment.PORT = toString projectConfig.webServer.port;
                          serviceConfig = {
                            Type = "simple";
                            DynamicUser = true;
                            ExecStart = lib.getExe (
                              pkgs.writeShellApplication {
                                name = "start-${name}";
                                runtimeInputs = [ config.packages.${name} ] ++ projectConfig.runtimeDependencies;
                                text = projectConfig.webServer.command;
                              }
                            );
                          };
                        };

                        services.nginx.virtualHosts.default.locations.${projectConfig.webServer.path}.proxyPass =
                          "http://localhost:${toString projectConfig.webServer.port}";
                      }
                    ) config.go
                  ));
              };
          };
        };

      # Example wiring, used to verify the module evaluates end-to-end via
      # garnix-lib's `mkModules`. Not built by garnix CI (only `packages`,
      # `checks`, `devShells` and `nixosConfigurations` are).
      lib.exampleFlakeOutputs = garnix-lib.lib.mkModules {
        modules = [ self.garnixModules.default ];
        config = {
          go.example.src = ./example;
        };
      };
    };
}
