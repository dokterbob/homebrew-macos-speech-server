class MacosSpeechServer < Formula
  desc "Local speech-to-text and text-to-speech server (OpenAI API + Wyoming)"
  homepage "https://github.com/dokterbob/macos-speech-server"
  license "AGPL-3.0-only"
  head "https://github.com/dokterbob/macos-speech-server.git", branch: "main"

  # The binary runs on macOS 14+, but building needs a Swift 6.2 toolchain (Xcode 26 or the
  # matching Command Line Tools), which only exists for macOS 15+. `depends_on xcode:` is
  # deliberately omitted: the Command Line Tools `swift` is sufficient, and the xcode
  # requirement would reject machines that only have the CLT installed.
  depends_on macos: :sonoma

  def install
    # Homebrew builds against the Command Line Tools SDK whenever the CLT are installed.
    # Swift 6.2's standard library (e.g. Span, used by swift-collections) needs the macOS 26
    # SDK, so when Xcode 26 or newer is present build with its toolchain and SDK instead of a
    # possibly older CLT SDK.
    if MacOS::Xcode.installed? && MacOS::Xcode.version >= "26"
      ENV["DEVELOPER_DIR"] = MacOS::Xcode.prefix.to_s
      ENV["HOMEBREW_DEVELOPER_DIR"] = MacOS::Xcode.prefix.to_s
      ENV["SDKROOT"] = MacOS::Xcode.sdk_path.to_s
      ENV["HOMEBREW_SDKROOT"] = MacOS::Xcode.sdk_path.to_s
    end

    # std_swift_args adds --disable-sandbox on macOS; Homebrew's sandbox allows network so
    # SwiftPM can fetch the pinned dependencies from Package.resolved.
    system "swift", "build", *std_swift_args
    bin.install ".build/release/speech-server"
    # InstallRenamed: an existing speech-server.yaml is kept and the new example is written
    # as speech-server.yaml.default, so upgrades never clobber user edits.
    (etc/"speech-server").install "speech-server.yaml.example" => "speech-server.yaml"
  end

  service do
    run [opt_bin/"speech-server", "serve"]
    keep_alive true
    working_dir var/"speech-server"
    environment_variables SPEECH_SERVER_CONFIG: etc/"speech-server/speech-server.yaml"
    log_path var/"log/speech-server.log"
    error_log_path var/"log/speech-server.log"
  end

  def caveats
    <<~EOS
      Configuration: #{etc}/speech-server/speech-server.yaml
      Logs:          #{var}/log/speech-server.log
      After editing the configuration, run: brew services restart #{name}

      On first start the server downloads speech models (roughly 700 MB with the
      default engines) into ~/Library/Application Support/FluidAudio and
      ~/.cache/fluidaudio. This takes several minutes and prints nothing at the
      default log_level (notice); set log_level: info to watch progress.
      The server is ready when this returns audio:
        curl -sf -X POST http://127.0.0.1:8080/v1/audio/speech \\
          -H 'Content-Type: application/json' \\
          -d '{"model":"tts-1","input":"Hello"}' -o /tmp/hello.wav

      Per-user service (starts at login):
        brew services start #{name}

      System service (starts at boot, runs as a dedicated role account):
        # pick an unused UID in 450-499: dscl . -list /Users UniqueID | awk '$2 >= 450 && $2 <= 499'
        sudo sysadminctl -addUser _speech-server -fullName "Speech Server" -UID 450 -roleAccount
        sudo dscl . -create /Users/_speech-server NFSHomeDirectory #{var}/speech-server
        sudo mkdir -p #{var}/speech-server
        sudo chown -R _speech-server #{var}/speech-server
        brew services stop #{name} 2>/dev/null || true
        sudo brew services start #{name} --sudo-service-user _speech-server
      Do not run both services at once (they share ports 8080 and 10300).
    EOS
  end

  test do
    # ServerConfig.load() runs before any model download; an unknown engine makes the
    # process fail immediately. The binary currently dies via an uncaught top-level error
    # (signal, not exit 1), so only assert "did not exit 0" plus the decoding error text.
    (testpath/"bad.yaml").write <<~YAML
      stt:
        engine: not-an-engine
    YAML
    ENV["SPEECH_SERVER_CONFIG"] = (testpath/"bad.yaml").to_s
    output = shell_output("#{bin}/speech-server serve 2>&1; echo \"exit=$?\"")
    refute_match(/exit=0\s*\z/, output)
    assert_match "not-an-engine", output
  end
end
