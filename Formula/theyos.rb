# frozen_string_literal: true

class Theyos < Formula
  desc "theyOS - Multi-tenant AI assistant platform for macOS"
  homepage "https://github.com/soyeht/theyos"
  version "0.1.1"

  on_arm do
    url "https://github.com/soyeht/theyos/releases/download/v0.1.1/theyos-0.1.1-macos-arm64.tar.gz"
    sha256 "af729714d6d6b4edd63ee3eef65e705aed94e08e160dc635bf988a9cd5ea2c7a"
  end

  on_intel do
    odie "theyOS requires Apple Silicon (M1/M2/M3/M4)."
  end

  depends_on macos: :sonoma # VZ Framework requires macOS 14+

  def pre_install
    stop_theyos_service
    terminate_theyos_processes
  end

  def install
    # All real binaries → libexec (not on PATH)
    %w[
      soyeht theyos init_macos_guest
      theyos-admin-host server theyos-ssh
      executor_ipc store-ipc terminal-ipc vmrunner_macos_ipc
      theyos-provision-inject
    ].each { |b| libexec.install b if File.exist?(b) }

    # Frontend assets → libexec/web/
    (libexec/"web").install Dir["web/*"] if Dir.exist?("web")

    # Codesign vmrunner_macos_ipc with Virtualization Framework entitlement
    if File.exist?("vmrunner-macos.entitlements") && (libexec/"vmrunner_macos_ipc").exist?
      system "codesign", "--force", "--entitlements",
             "vmrunner-macos.entitlements", "-s", "-",
             libexec/"vmrunner_macos_ipc"
    end

    # Wrapper scripts in bin/ — set env vars, bootstrap data dir, exec real binary.
    # Uses opt_libexec (stable symlink, survives upgrades).
    # THEYOS_DIR defaults to ~/.theyos only if not already set.
    # First-run bootstrap creates ~/.theyos/.env with random password.
    # Wrapper env vars take precedence over .env (launcher checks process env first).
    wrapper_body = <<~'SH'
      #!/bin/sh
      : "${THEYOS_DIR:=$HOME/.theyos}"
      export THEYOS_DIR
    SH
    wrapper_body += <<~SH
      export THEYOS_BIN_DIR="#{opt_libexec}"
      export WEB_DIR="#{opt_libexec}/web"
      export THEYOS_SSH_CTL="#{opt_libexec}/theyos-ssh"
      export THEYOS_VMRUNNER_MACOS_RS_BIN="#{opt_libexec}/vmrunner_macos_ipc"
    SH
    # First-run bootstrap (runs as real user, no sandbox restrictions)
    wrapper_body += <<~'SH'
      if [ ! -f "$THEYOS_DIR/.env" ]; then
        mkdir -p "$THEYOS_DIR/.run" "$THEYOS_DIR/logs"
        for claw in picoclaw zeroclaw nanobot openclaw nullclaw ironclaw; do
          mkdir -p "$THEYOS_DIR/claws/data/$claw"
        done
        mkdir -p "$HOME/Library/Application Support/theyos/snapshots"
        mkdir -p "$HOME/Library/Application Support/theyos/vms"
        mkdir -p "$HOME/Library/Logs/theyos"
        _PASS=$(openssl rand -hex 16)
        _PEPPER=$(openssl rand -hex 32)
        cat > "$THEYOS_DIR/.env" <<ENVEOF
      SOYEHT_ADMIN_PASSWORD=$_PASS
      THEYOS_SESSION_PEPPER=$_PEPPER
      ENVEOF
        chmod 600 "$THEYOS_DIR/.env"
        echo "[theyos] First-time setup complete."
        echo "[theyos] Admin password: $_PASS"
        echo "[theyos] Config: $THEYOS_DIR/.env"
      fi
    SH
    wrapper_body += <<~'SH'
      if [ ! -f "$THEYOS_DIR/bootstrap-token" ]; then
        openssl rand -base64 32 > "$THEYOS_DIR/bootstrap-token"
        chmod 600 "$THEYOS_DIR/bootstrap-token"
        echo "[theyos] Generated bootstrap token at $THEYOS_DIR/bootstrap-token"
      fi
    SH

    (bin/"soyeht").write(wrapper_body + "exec \"#{opt_libexec}/soyeht\" \"$@\"\n")
    (bin/"soyeht").chmod(0o755)

    (bin/"init_macos_guest").write(wrapper_body + "exec \"#{opt_libexec}/init_macos_guest\" \"$@\"\n")
    (bin/"init_macos_guest").chmod(0o755)

    bin.install_symlink bin/"soyeht" => "theyos"
  end

  # No post_install — Homebrew sandbox blocks $HOME access.
  # Data directory setup happens in wrapper scripts on first run.

  # Launchd service — runs theyos-admin-host directly (resident process).
  # theyos-admin-host loads .env then exec's server (process replacement).
  service do
    run [opt_libexec/"theyos-admin-host"]
    run_type :immediate
    keep_alive crashed: true
    log_path var/"log/theyos.log"
    error_log_path var/"log/theyos.log"
    environment_variables(
      THEYOS_DIR:                    "#{Dir.home}/.theyos",
      THEYOS_BIN_DIR:                opt_libexec.to_s,
      WEB_DIR:                       (opt_libexec/"web").to_s,
      THEYOS_SSH_CTL:                (opt_libexec/"theyos-ssh").to_s,
      THEYOS_VMRUNNER_MACOS_RS_BIN:  (opt_libexec/"vmrunner_macos_ipc").to_s,
      THEYOS_BOOTSTRAP_TOKEN_PATH:   "#{Dir.home}/.theyos/bootstrap-token",
      HOME:                          Dir.home,
    )
  end

  def caveats
    <<~EOS
      theyOS installed successfully.

      First-time setup (one-time, ~30 min):
        soyeht start

      This downloads macOS and creates the base VM image.
      Subsequent starts are instant.

      Requires macOS to be fully up to date (the downloaded IPSW
      must match your macOS version). If you see "software update"
      errors, update your Mac first, then re-run soyeht start.

      Admin panel: http://localhost:8892
      Password:    grep SOYEHT_ADMIN_PASSWORD ~/.theyos/.env

      To auto-start at login (after first-time setup):
        soyeht stop                     # stop manual process first!
        brew services start theyos

      Important: don't mix manual (soyeht start/stop) with
      launchd (brew services start/stop). Pick one.

      Clean uninstall (stops helpers + removes launch agent residue):
        soyeht cleanup-homebrew
        brew uninstall theyos

      Full purge (removes data, VMs, logs, caches, launch agent, ~100GB):
        soyeht cleanup-homebrew --purge-data
        brew uninstall theyos

      If purge hits EACCES in macos-base, fix ownership first:
        sudo chown -R $(whoami):staff ~/Library/Application\\ Support/theyos/vms/macos-base
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/soyeht --version")
    system bin/"soyeht", "--help"
    assert_predicate opt_libexec/"server", :exist?
    assert_predicate opt_libexec/"vmrunner_macos_ipc", :exist?
  end

  private

  def managed_process_names
    %w[
      theyos-admin-host
      server
      executor_ipc
      store-ipc
      terminal-ipc
      vmrunner_macos_ipc
      theyos-provision-inject
    ]
  end

  def stop_theyos_service
    return unless OS.mac?

    system "brew", "services", "stop", name.to_s

    launch_agent_paths.each do |plist|
      next unless plist.exist?

      system "launchctl", "bootout", "gui/#{Process.uid}", plist.to_s
      system "launchctl", "unload", "-w", plist.to_s
    end
  end

  def terminate_theyos_processes
    pids = managed_processes.map(&:first)
    return if pids.empty?

    Process.kill("TERM", *pids)
    sleep 2

    survivors = pids.select { |pid| process_alive?(pid) }
    Process.kill("KILL", *survivors) unless survivors.empty?
  rescue Errno::ESRCH
    nil
  end

  def managed_processes
    IO.popen(["ps", "-axo", "pid=,command="], &:read).each_line.filter_map do |line|
      pid_str, command = line.strip.split(/\s+/, 2)
      next if pid_str.nil? || command.nil?
      next unless managed_command?(command)

      [pid_str.to_i, command]
    end
  end

  def managed_command?(command)
    return false unless command.include?("/libexec/")
    return false unless command.start_with?("#{HOMEBREW_PREFIX}/opt/theyos/",
                                            "#{HOMEBREW_PREFIX}/Cellar/theyos/")

    managed_process_names.any? { |binary| command.include?("/libexec/#{binary}") }
  end

  def process_alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::EPERM
    true
  rescue Errno::ESRCH
    false
  end

  def launch_agent_paths
    [
      Pathname.new("#{Dir.home}/Library/LaunchAgents/homebrew.mxcl.#{name}.plist"),
      Pathname.new("#{HOMEBREW_PREFIX}/opt/homebrew.mxcl.#{name}.plist"),
      prefix/"homebrew.mxcl.#{name}.plist",
    ]
  end
end
