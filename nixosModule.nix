{ lib, pkgs, config, ... }:
let
  # Overrides a derivation to include new CFLAGS alongside existing CFLAGS
  # flags is a list of a strings representing the CFLAGS to be set
  optimizeWithFlags = pkg: flags:
    pkgs.lib.overrideDerivation pkg (old:
      let
        newflags = pkgs.lib.foldl' (acc: x: "${acc} ${x}") "" flags;
        oldflags =
          if (pkgs.lib.hasAttr "NIX_CFLAGS_COMPILE" old)
          then "${old.NIX_CFLAGS_COMPILE}"
          else "";
      in
      {
        NIX_CFLAGS_COMPILE = "${oldflags} ${newflags}";
      });

  # Harden the code to make it less likely to be expoloited
  compileTimeHardening = pkg:
    optimizeWithFlags pkg [
      # Optimize using specific microcode and ISA implementations for this machine
      "-march=native"
      # No relative pointer index offets (Position Independent Code)
      "-fPIC"
      # Warn when printf/scanf don't use string literals
      "-Wformat"
      "-Wformat-security"
      "-Werror=format-security"
      # Add overwrite canaries to buffers greater than 4 bytes
      "-fstack-protector-strong"
      "--param ssp-buffer-size=4"
      # Add buffer overflow checks at compile and at runtime; no using %n in
      # string formatting functions (e.g. printf()) unless they are read only
      "-O2"
      "-D_FORTIFY_SOURCE=2"
      # No relative pointer index offets (Position Independent Code) and makes
      # ASLR possible
      "-fPIC"
      # Adds interger overflow checking to prevent errors
      "-fno-strict-overflow"
    ];
  harden = pkg: (if config.defaults.packages.harden then (compileTimeHardening pkg) else pkg);

  # Audit Specific
  auditCheck = config.security.auditing.enable;
  auditIsLockedBehindReboot = config.security.auditing.requireReboot;
in
{
  # Add in an option for enabling system wide auditing
  options = {
    security = {
      auditing = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable logging syscalls using autitd.";
        };
        requireReboot = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Require a reboot to change rules.";
        };
      };
    };
  };

  config = lib.mkIf auditCheck {
    # You must reboot to delete or change a rule 
    # Recommend you turn this off while testing new configs, but do not forget
    # to enable it again!
    boot.kernelParams = lib.mkIf auditIsLockedBehindReboot [ "audit=1" ];

    # Have journald capture logs
    services.journald.extraConfig = ''
      Audit=yes
      MaxlevelAudit=info
    '';

    # Add in tooling to control and search through the audit logs generated
    # Notably:
    # - auditctl: for changing auditd's function (although mostly useless
    # because we use NixOS to declaritively set rules, as well as prevent
    # rule changes without a reboot)
    # - ausearch: for searching through audit logs
    # - aureport: generate audit log summaries
    environment.systemPackages = [
      (harden pkgs.audit)
    ];

    security = {
      # Enable Linux Kernel Auditing
      auditd = {
        enable = lib.mkDefault true;
        settings = {
          # Number of log files to keep
          num_logs = lib.mkDefault 8;
          # Maximum logfile size, in MiB
          max_log_file = lib.mkDefault 32;
          # What to do when we're out of log files
          max_log_file_action = lib.mkDefault "rotate";
        };
      };

      audit = {
        enable = lib.mkDefault true;
        rules = [
          ################
          # SSH AUDITING #
          ################
          # Track changes to SSH configuration
          "-w /etc/ssh/ssh_config -p wa -k ssh_config"
          "-w /etc/ssh/sshd_config -p wa -k sshd_config"
          "-w /etc/ssh/sshd_config.d/ -p wa -k ssh_config_dir"
          # "-w /etc/ssh/sshd_config.d/*.conf -p wa -k ssh_config_files"

          # Monitor SSH host key access
          "-w /etc/ssh/ssh_host_rsa_key -p rx -k ssh_key_access"
          "-w /etc/ssh/ssh_host_ecdsa_key -p rx -k ssh_key_access"
          "-w /etc/ssh/ssh_host_ed25519_key -p rx -k ssh_key_access"

          # Monitor SSH authentication logs
          "-w /var/log/auth.log -p wa -k auth_log"
          "-w /var/log/secure -p wa -k secure_log"

          # Monitor PAM configuration for SSH
          "-w /etc/pam.d/sshd -p wa -k pam_sshd"
          "-w /etc/pam.d/ -p wa -k pam_config"

          # Monitor when sshd is run
          "-w /run/current-system/sw/bin/sshd -p x -k sshd_execution"
          # Use this version if you want to see which arguments are passed
          # "-a exit,always -F arch=b64 -S execve -F path=/run/current-system/sw/bin/sshd -k sshd_execve"

          # Track when sshd accepts incoming connections
          "-a exit,always -F arch=b64 -S accept4 -F exe=/run/current-system/sw/bin/sshd -k sshd_accept"

          ###############
          # USER LOGINS #
          ###############
          # Track successful logins via PAM 
          "-a always,exit -F arch=b64 -S openat -F path=/var/run/utmp -F success=1 -k login_success"
          "-w /var/run/utmp -p wa -k utmp_changes"
          "-a always,exit -F arch=b64 -S openat -F path=/var/log/btmp -F success=1 -k login_failure"
          "-w /var/log/btmp -p wa -k btmp_changes"
          "-a always,exit -F arch=b64 -S openat -F path=/var/log/wtmp -F success=1 -k login_record"
          "-w /var/log/wtmp -p wa -k wtmp_changes"
          "-w /var/log/lastlog -p wa -k lastlog_changes"

          # Monitor user/group changes 
          "-w /etc/passwd -p wa -k user_changes"
          "-w /etc/group -p wa -k group_changes"
          "-w /etc/shadow -p wa -k shadow_changes"
          "-w /etc/sudoers -p wa -k sudoers_changes"
          "-w /etc/sudoers.d/ -p wa -k sudoers_dir"
        ];
      };
    };
  };
}
