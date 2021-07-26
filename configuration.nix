{ pkgs, lib, config, ... }:
let
  sshPath = "/srv";
  customEnvironment = {
    NIX_REMOTE = "daemon";
    NIX_PATH = "nixpkgs=${pkgs.path}";
    SSH_PATH = "${sshPath}";
    ARTIFACTS_DIRECTORY = "${sshPath}";
    STREAM_PATH = "${sshPath}";
  };
  # Additional Environment Variables
  runCampaign = pkgs.writeScriptBin "runCampaign" ''
    #! ${pkgs.nix}/bin/nix-shell
    #! nix-shell -i bash -p git nix gnutar openssh cachix coreutils curl

    export HOME=$(eval echo ~''$USER);
    cd ~/;

    echo "Saving the repository to SWH";
    curl -X POST "https://archive.softwareheritage.org/api/1/origin/save/git/url/''${REPOSITORY}";

    echo "Cloning the campaign repository…";
    git clone ''${REPOSITORY};
    cd $(basename ''${REPOSITORY} .git);

    echo "Building the campaign…";
    nix build -v

    echo "Listing the build artifacts";
    nix-store -qR ./result &> ''${ARTIFACTS_DIRECTORY}/build_artifacts.txt;

    echo "Copying the build artifacts to the binary cache";
    mkdir -p ''${ARTIFACTS_DIRECTORY}/store/
    ${pkgs.nixUnstable}/bin/nix  --experimental-features nix-command copy --to file:''${ARTIFACTS_DIRECTORY}/store/ ./result

    echo "Running the campaign"
    ./result/run &> ''${ARTIFACTS_DIRECTORY}/campaign_run.txt;
  '';
  finalizeCampaign = pkgs.writeScriptBin "finalizeCampaign" ''
    #! ${pkgs.nix}/bin/nix-shell
    #! nix-shell -i bash -p git nix gnutar openssh cachix coreutils

    #${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: value: "export " + name + "=" + value +"\n") customEnvironment)}
    #source /etc/sisyphe_secrets;

    export HOME=$(eval echo ~''$USER);
    cd ~/;

    echo "Entering the campaign repository…";
    cd $(basename ''${REPOSITORY} .git);

    echo "Running the campaign post scripts"
    ./result/finalize &> ''${ARTIFACTS_DIRECTORY}/campaign_post.txt;
  '';
in
{

  environment.systemPackages = [
    pkgs.nix-du
    pkgs.graphviz
    pkgs.curl
    (pkgs.writeShellScriptBin "nixFlakes" ''
      exec ${pkgs.nixUnstable}/bin/nix --experimental-features "nix-command flakes" "$@"
    '')
  ];

  nix = {
    binaryCaches = [
      "https://bincache.grunblatt.org"
    ];

    binaryCachePublicKeys = [
      "bincache.grunblatt.org:ktUnzmIdQUSVIyu3XcgdKP6LtocaDGbWrOpVBJ62T4A="
    ];
  };

  services.openssh = {
    enable = true;
    ports = [ 22 ];
  };

  networking.firewall = {
    allowedTCPPorts = [ 22 ];
    enable = true;
  };

  users.users = {
    "root" = {
      hashedPassword = "$6$DgA6giaB6Jnq$BWvgUiHcgucPwdAR19a88djcySZ0hoKUD/N75AmQzRkiwRpAtGyjSLOpSjXQttpare7FrFnPSezf6jt00PXiz1";
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMoimzzRayQN8PpaoVd6kQC/Xnkv9H1eLcse92Nrk8AT remy@medina"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILjfNIqw1xgnIc9CaBfxhZtIEu7F/sfNENip9Ou5KZm9 remy@sauron"
      ];
    };
  };

  systemd = {
    services."campaign" = {
      enable = true;
      after = [
        "network.target"
        "nix-daemon.service"
        "srv.mount"
      ];
      wantedBy = [ "multi-user.target" ];
      environment = customEnvironment;
      serviceConfig = {
        EnvironmentFile = "/etc/sisyphe_secrets";
        StandardOutput = "file:${sshPath}/campaign.stdout.txt";
        StandardError = "file:${sshPath}/campaign.stderr.txt";
      };
      script = ''
        ${runCampaign}/bin/runCampaign
      '';
    };
    services."campaign-finalize" = {
      enable = true;
      after = [
        "systemd-networkd-wait-online.service"
        "network.target"
        "network-online.target"
        "nss-lookup.target"
        "nix-daemon.service"
        "srv.mount"
      ];
      wantedBy = [ "multi-user.target" ];
      environment = customEnvironment;
      serviceConfig = {
        TimeoutStopSec = "infinity";
        Type = "oneshot";
        RemainAfterExit = true;
        EnvironmentFile = "/etc/sisyphe_secrets";
        StandardOutput = "file:${sshPath}/campaign-finalize.stdout.txt";
        StandardError = "file:${sshPath}/campaign-finalize.stderr.txt";
        ExecStop = "${finalizeCampaign}/bin/finalizeCampaign";
      };
    };
  };

  fileSystems."${sshPath}" = {
    device = "srv";
    fsType = "9p";
    options = [ "trans=virtio" ];
  };
}
