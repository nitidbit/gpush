require "spec_helper"
require_relative "../src/ruby/version_checker"

RSpec.describe VersionChecker do
  describe ".print_message_if_new_version" do
    context "with local-development version" do
      it "skips version check" do
        expect(described_class).not_to receive(:homebrew_installed?)
        expect(described_class).not_to receive(:get_latest_version)

        expect {
          described_class.print_message_if_new_version("local-development")
        }.not_to output.to_stdout
      end
    end

    context "when Homebrew is not installed" do
      before do
        allow(described_class).to receive(:homebrew_installed?).and_return(
          false,
        )
      end

      it "skips version check" do
        expect(described_class).not_to receive(:get_latest_version)

        expect {
          described_class.print_message_if_new_version("1.0.0")
        }.not_to output.to_stdout
      end
    end

    context "when Homebrew is installed" do
      before do
        allow(described_class).to receive(:homebrew_installed?).and_return(true)
      end

      context "when unable to get latest version" do
        before do
          allow(described_class).to receive(:get_latest_version).and_return(nil)
        end

        it "skips version check" do
          expect {
            described_class.print_message_if_new_version("1.0.0")
          }.not_to output.to_stdout
        end
      end

      context "when latest version is available" do
        before do
          allow(described_class).to receive(:get_latest_version).and_return(
            "2.6.3",
          )
        end

        context "with older version" do
          it "prints update message" do
            expect {
              described_class.print_message_if_new_version("1.0.0")
            }.to output(
              /A new version of gpush is available: 2\.6\.3/,
            ).to_stdout
          end
        end

        context "with same version" do
          it "doesn't print update message" do
            expect {
              described_class.print_message_if_new_version("2.6.3")
            }.not_to output.to_stdout
          end
        end

        context "with newer version" do
          it "doesn't print update message" do
            expect {
              described_class.print_message_if_new_version("3.0.0")
            }.not_to output.to_stdout
          end
        end

        context "with empty version" do
          it "skips version check" do
            expect(described_class).not_to receive(:newer_version_available?)

            expect {
              described_class.print_message_if_new_version("")
            }.not_to output.to_stdout
          end
        end

        context "with nil version" do
          it "skips version check" do
            expect(described_class).not_to receive(:newer_version_available?)

            expect {
              described_class.print_message_if_new_version(nil)
            }.not_to output.to_stdout
          end
        end

        context "with invalid version format" do
          it "handles the error and doesn't print update message" do
            expect {
              described_class.print_message_if_new_version("abc")
            }.not_to output.to_stdout
          end
        end
      end
    end
  end

  describe ".homebrew_installed?" do
    it "returns true if brew is installed" do
      allow(described_class).to receive(:system).with(
        "which brew > /dev/null 2>&1",
      ).and_return(true)
      expect(described_class.homebrew_installed?).to be true
    end

    it "returns false if brew is not installed" do
      allow(described_class).to receive(:system).with(
        "which brew > /dev/null 2>&1",
      ).and_return(false)
      expect(described_class.homebrew_installed?).to be false
    end
  end

  describe ".get_latest_version" do
    context "when brew info returns valid JSON" do
      before do
        valid_json = '[{"versions":{"stable":"2.6.3"}}]'
        allow(described_class).to receive(:`).with(
          "brew info gpush --json=v1 2>/dev/null",
        ).and_return(valid_json)
      end

      it "returns the stable version" do
        expect(described_class.get_latest_version).to eq("2.6.3")
      end
    end

    context "when brew info returns invalid JSON" do
      before do
        allow(described_class).to receive(:`).with(
          "brew info gpush --json=v1 2>/dev/null",
        ).and_return("invalid json")
      end

      it "returns nil" do
        expect(described_class.get_latest_version).to be_nil
      end
    end

    context "when brew info returns empty string" do
      before do
        allow(described_class).to receive(:`).with(
          "brew info gpush --json=v1 2>/dev/null",
        ).and_return("")
      end

      it "returns nil" do
        expect(described_class.get_latest_version).to be_nil
      end
    end
  end

  describe ".valid_version?" do
    it "returns true for valid version strings" do
      expect(described_class.valid_version?("1.0.0")).to be true
    end

    it "returns false for nil" do
      expect(described_class.valid_version?(nil)).to be false
    end

    it "returns false for empty string" do
      expect(described_class.valid_version?("")).to be false
    end
  end

  describe ".newer_version_available?" do
    it "returns true when latest version is newer" do
      expect(
        described_class.newer_version_available?("1.0.0", "2.0.0"),
      ).to be true
    end

    it "returns false when latest version is the same" do
      expect(
        described_class.newer_version_available?("2.0.0", "2.0.0"),
      ).to be false
    end

    it "returns false when latest version is older" do
      expect(
        described_class.newer_version_available?("3.0.0", "2.0.0"),
      ).to be false
    end

    it "returns false when versions can't be parsed" do
      expect(
        described_class.newer_version_available?("invalid", "2.0.0"),
      ).to be false
    end
  end
end
