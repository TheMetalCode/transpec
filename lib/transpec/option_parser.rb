# coding: utf-8

require 'transpec/configuration'
require 'transpec/git'
require 'transpec/version'
require 'optparse'
require 'rainbow'

module Transpec
  class OptionParser
    CONFIG_ATTRS_FOR_KEEP_TYPES = {
              should: :convert_should=,
      should_receive: :convert_should_receive=,
                stub: :convert_stub=,
          have_items: :convert_have_items=,
                 its: :convert_its=,
          deprecated: :convert_deprecated_method=
    }

    VALID_BOOLEAN_MATCHER_TYPES = %w(truthy,falsey truthy,falsy true,false)

    attr_reader :configuration

    def self.available_conversion_types
      CONFIG_ATTRS_FOR_KEEP_TYPES.keys
    end

    def initialize(configuration = Configuration.new)
      @configuration = configuration
      setup_parser
    end

    def parse(args)
      args = args.dup
      @parser.parse!(args)
      args
    end

    def help
      @parser.help
    end

    private

    # rubocop:disable MethodLength
    def setup_parser
      @parser = create_parser

      define_option('-f', '--force') do
        @configuration.forced = true
      end

      define_option('-s', '--skip-dynamic-analysis') do
        @configuration.skip_dynamic_analysis = true
      end

      define_option('-c', '--rspec-command COMMAND') do |command|
        @configuration.rspec_command = command
      end

      define_option('-m', '--generate-commit-message') do
        unless Git.inside_of_repository?
          fail '-m/--generate-commit-message option is specified but not in a Git repository'
        end

        @configuration.generate_commit_message = true
      end

      define_option('-k', '--keep TYPE[,TYPE...]') do |types|
        types.split(',').each do |type|
          config_attr = CONFIG_ATTRS_FOR_KEEP_TYPES[type.to_sym]
          fail ArgumentError, "Unknown syntax type #{type.inspect}" unless config_attr
          @configuration.send(config_attr, false)
        end
      end

      define_option('-n', '--negative-form FORM') do |form|
        @configuration.negative_form_of_to = form
      end

      define_option('-b', '--boolean-matcher TYPE') do |type|
        unless VALID_BOOLEAN_MATCHER_TYPES.include?(type)
          types = VALID_BOOLEAN_MATCHER_TYPES.map(&:inspect).join(', ')
          fail ArgumentError, "Boolean matcher type must be any of #{types}"
        end
        @configuration.boolean_matcher_type = type.include?('truthy') ? :conditional : :exact
        @configuration.form_of_be_falsey = type.include?('falsy') ? 'be_falsy' : 'be_falsey'
      end

      define_option('-p', '--no-parentheses-matcher-arg') do
        @configuration.parenthesize_matcher_arg = false
      end

      define_option('--no-color') do
        Sickill::Rainbow.enabled = false
      end

      define_option('--version') do
        puts Version.to_s
        exit
      end
    end
    # rubocop:enable MethodLength

    def create_parser
      banner = "Usage: transpec [options] [files or directories]\n\n"
      summary_width = 32 # Default
      indentation = ' ' * 2
      ::OptionParser.new(banner, summary_width, indentation)
    end

    def define_option(*options, &block)
      description_lines = descriptions[options.first]
      @parser.on(*options, *description_lines, &block)
    end

    # rubocop:disable MethodLength, AlignHash
    def descriptions
      @descriptions ||= {
        '-f' => [
          'Force processing even if the current Git',
          'repository is not clean.'
        ],
        '-s' => [
          'Skip dynamic analysis and convert with only',
          'static analysis. Note that specifying this',
          'option decreases the conversion accuracy.'
        ],
        '-c' => [
          'Specify command to run RSpec that is used for',
          'dynamic analysis.',
          'Default: "bundle exec rspec"'
        ],
        '-m' => [
          'Generate commit message that describes',
          'conversion summary. Only Git is supported.'
        ],
        '-k' => [
          'Keep specific syntaxes by disabling',
          'conversions.',
          'Available syntax types:',
          "  #{'should'.bright} (to #{'expect(obj).to'.underline})",
          "  #{'should_receive'.bright} (to #{'expect(obj).to receive'.underline})",
          "  #{'stub'.bright}  (to #{'allow(obj).to receive'.underline})",
          "  #{'have_items'.bright} (to #{'expect(obj.size).to eq(x)'.underline})",
          "  #{'its'.bright} (to #{'describe { subject { } it { } }'.underline})",
          "  #{'deprecated'.bright} (e.g. from #{'mock'.underline} to #{'double'.underline})",
          'These are all converted by default.'
        ],
        '-n' => [
          "Specify negative form of #{'to'.underline} that is used in",
          "the #{'expect(...).to'.underline} syntax.",
          "Either #{'not_to'.bright} or #{'to_not'.bright}.",
          "Default: #{'not_to'.bright}"
        ],
        '-b' => [
          "Specify matcher type that #{'be_true'.underline} and",
          "#{'be_false'.underline} will be converted to.",
          "  #{'truthy,falsey'.bright} (conditional semantics)",
          "  #{'truthy,falsy'.bright}  (alias of #{'falsey'.underline})",
          "  #{'true,false'.bright}    (exact equality)",
          "Default: #{'truthy,falsey'.bright}"
        ],
        '-p' => [
          'Suppress parenthesizing argument of matcher',
          'when converting operator to non-operator in',
          "the #{'expect'.underline} syntax. Note that it will be",
          'parenthesized even if this option is',
          'specified when parentheses are necessary to',
          'keep the meaning of the expression.',
          'By default, arguments of the following',
          'operator matchers will be parenthesized.',
          "  #{'== 10'.underline} to #{'eq(10)'.underline}",
          "  #{'=~ /pattern/'.underline} to #{'match(/pattern/)'.underline}",
          "  #{'=~ [1, 2]'.underline} to #{'match_array([1, 2])'.underline}"
        ],
        '--no-color' => [
          'Disable color in the output.'
        ],
        '--version' => [
          'Show Transpec version.'
        ]
      }
    end
    # rubocop:enable MethodLength, AlignHash
  end
end
