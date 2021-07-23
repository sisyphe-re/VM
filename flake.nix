{
  description = "Base Image for Sisyphe";
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-21.05";
  outputs = { self, nixpkgs }:
    with import nixpkgs { system = "x86_64-linux"; };
    {

      packages.x86_64-linux.iso =
        let
          lib = nixpkgs.lib;
          name = "sisyphe-x86_64";
          systemConfiguration =  ./configuration.nix;
          standalone = {
            config = {
              fileSystems."/" = {
                device = "/dev/disk/by-label/nixos";
                fsType = "ext4";
                autoResize = true;
              };
              boot = {
                kernelParams = [ "console=ttyS0" ];
                loader = {
                  timeout = 0;
                  grub.device = "/dev/xvda";
                  grub.configurationLimit = 0;
                };
                initrd = {
                  network.enable = false;
                  availableKernelModules = [ "virtio_net" "virtio_pci" "virtio_mmio" "virtio_blk" "virtio_scsi" "kvm-amd" "kvm-intel" "xhci_pci" "ehci_pci" "ahci" "usbhid" "usb_storage" "sd_mod" ];
                };
              };
              services = {
                udisks2.enable = false;
              };
              security = {
                polkit.enable = false;
              };
              i18n.supportedLocales = [
                "en_US.UTF-8/UTF-8"
                "fr_FR.UTF-8/UTF-8"
              ];
            };
          };
          evaluated = import "${nixpkgs}/nixos/lib/eval-config.nix" {
            system = pkgs.system;
            modules = [ systemConfiguration ] ++ [ standalone ];
            inherit pkgs;
          };
        in
        import "${nixpkgs}/nixos/lib/make-disk-image.nix" {
          inherit lib name pkgs;
          config = evaluated.config;
          contents = [ ];
          diskSize = 8192;
          format = "qcow2";
        };
      defaultPackage.x86_64-linux = self.packages.x86_64-linux.iso;
    };
}
