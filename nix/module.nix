{ config, lib, pkgs, ... }:

let
  cfg = config.services.qxfx0;
in {
  options.services.qxfx0 = {
    enable = lib.mkEnableOption "QxFx0 philosophical dialogue thinking system";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.haskellPackages.callCabal2nix "qxfx0" (lib.cleanSource ./..) {};
      description = "The QxFx0 package to use.";
    };

    dbPath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/qxfx0/qxfx0.db";
      description = "Path to the SQLite database file.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 9170;
      description = "TCP port for the QxFx0 HTTP service.";
    };

    conceptsPath = lib.mkOption {
      type = lib.types.str;
      default = "/etc/qxfx0/concepts.nix";
      description = "Path to the constitutional concepts.nix file.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc."qxfx0/concepts.nix".source = ../../semantics/concepts.nix;

    systemd.services.qxfx0 = {
      description = "QxFx0 Philosophical Dialogue Thinking System";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      environment = {
        QXFX0_ROOT = "/var/lib/qxfx0";
        QXFX0_DB_PATH = cfg.dbPath;
        QXFX0_CONCEPTS_PATH = cfg.conceptsPath;
        QXFX0_PORT = toString cfg.port;
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/qxfx0-main";

        DynamicUser = true;
        User = "qxfx0";
        Group = "qxfx0";

        StateDirectory = "qxfx0";
        StateDirectoryMode = "0750";
        CacheDirectory = "qxfx0";
        LogsDirectory = "qxfx0";

        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        PrivateNetwork = false;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        MemoryDenyWriteExecute = true;
        RestrictRealtime = true;
        RestrictNamespaces = true;
        LockPersonality = true;
        RemoveIPC = true;

        CapabilityBoundingSet = "";
        AmbientCapabilities = "";

        SystemCallFilter = [ "@system-service" ];
        SystemCallErrorNumber = "EPERM";

        BindReadOnlyPaths = [
          "/etc/qxfx0/concepts.nix"
          "${cfg.package}/"
        ];
        ReadWritePaths = [ "/var/lib/qxfx0" ];

        LimitNOFILE = 1024;
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.enable [ cfg.port ];
  };
}
