# nixos module: root service that blinks the power-button led while fprintd
# waits for a finger (sudo, login, lock screen, polkit, enroll).
#
#   services.framework-fingerprint-led-blink.enable = true;
#
# `src` and `version` are bound by flake.nix; the default package is built
# against the system's own pkgs, not this flake's nixpkgs pin.
{ src, version }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.framework-fingerprint-led-blink;
  inherit (lib) mkOption types;

  finalPackage = cfg.package.override {
    inherit (cfg)
      led
      onSeconds
      offSeconds
      maxBlinkSeconds
      ;
  };
in
{
  options.services.framework-fingerprint-led-blink = {
    enable = lib.mkEnableOption "blinking the Framework power-button LED while fprintd waits for a finger";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ./package.nix { inherit src version; };
      defaultText = lib.literalMD "framework-fingerprint-led-blink built against the system `pkgs`";
      description = ''
        The watcher package. It is `.override`n with `led`, `onSeconds`,
        `offSeconds` and `maxBlinkSeconds`, so a replacement must accept
        those arguments (see package.nix).
      '';
    };

    led = mkOption {
      type = types.str;
      default = "chromeos:white:power";
      example = "chromeos:multicolor:charging";
      description = ''
        LED name under /sys/class/leds. The default is the power button
        (which houses the fingerprint reader) on the Framework 16, exposed
        by the leds_cros_ec driver. It is handed back to the EC with the
        `chromeos-auto` trigger when blinking stops.
      '';
    };

    onSeconds = mkOption {
      type = types.numbers.positive;
      default = 0.25;
      description = "Seconds the LED stays on per blink.";
    };

    offSeconds = mkOption {
      type = types.numbers.positive;
      default = 0.25;
      description = "Seconds the LED stays off per blink.";
    };

    maxBlinkSeconds = mkOption {
      type = types.numbers.positive;
      default = 60;
      description = "Safety net: stop blinking after this long even if no stop signal was seen.";
    };
  };

  config = lib.mkIf cfg.enable {
    # nothing to watch without it
    services.fprintd.enable = lib.mkDefault true;

    systemd.services.framework-fingerprint-led-blink = {
      description = "Blink power-button LED while fprintd waits for a finger";
      after = [ "dbus.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = lib.getExe finalPackage;
        # the script restores the led on SIGTERM itself; this covers SIGKILL
        # and crashes. "-": a missing led must not fail the unit
        ExecStopPost = "-${pkgs.runtimeShell} -c 'echo chromeos-auto > /sys/class/leds/${cfg.led}/trigger'";
        Restart = "on-failure";
        RestartSec = 2;

        # has to be uid 0: the system bus only lets root call BecomeMonitor,
        # and the led sysfs files are root-owned 0644. no capabilities needed
        # for either, so drop all of them.
        CapabilityBoundingSet = "";
        NoNewPrivileges = true;
        # leaves /sys writable (ProtectKernelTunables would not)
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        # the system bus is a path socket, which survives a private netns
        PrivateNetwork = true;
        RestrictAddressFamilies = [ "AF_UNIX" ];
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectProc = "invisible";
        ProcSubset = "pid";
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [ "@system-service" ];
        UMask = "0077";
      };
    };
  };
}
