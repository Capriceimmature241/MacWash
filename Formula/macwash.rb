class Macwash < Formula
  desc "Clean, optimize and speed up your Mac. Free and open source — clean, uninstall, analyze, optimize and monitor from the terminal"
  homepage "https://github.com/toolka/MacWash"
  url "https://github.com/toolka/MacWash/archive/refs/tags/v1.0.0.tar.gz"
  # sha256 will be filled in after the v1.0.0 release is published on GitHub
  # sha256 "PLACEHOLDER_RUN: curl -fsSL <tarball_url> | shasum -a 256"
  license "MIT"
  version "1.0.0"

  def install
    bin.install "macwash"
    (prefix/"lib").install Dir["lib/*"]
    (prefix/"bin").install Dir["bin/*"]

    # Create symlink so `macwash` resolves correctly to its lib directory
    (bin/"macwash").chmod 0755
  end

  def post_install
    # Patch SCRIPT_DIR inside the installed macwash binary to point to prefix
    inreplace bin/"macwash", /^SCRIPT_DIR=.*/, "SCRIPT_DIR=\"#{prefix}\""
  end

  test do
    output = shell_output("#{bin}/macwash --version")
    assert_match "MacWash", output
  end
end
