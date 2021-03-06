# coding: utf-8

require 'transpec/syntax'
require 'transpec/syntax/mixin/send'
require 'transpec/syntax/mixin/monkey_patch'
require 'transpec/syntax/mixin/expectizable'
require 'transpec/syntax/mixin/have_matcher'
require 'transpec/util'
require 'transpec/syntax/operator_matcher'

module Transpec
  class Syntax
    class Should < Syntax
      include Mixin::Send, Mixin::MonkeyPatch, Mixin::Expectizable, Mixin::HaveMatcher, Util

      attr_reader :current_syntax_type

      def self.target_method?(receiver_node, method_name)
        !receiver_node.nil? && [:should, :should_not].include?(method_name)
      end

      def initialize(node, source_rewriter = nil, runtime_data = nil, report = nil)
        super
        @current_syntax_type = :should
      end

      def register_request_for_dynamic_analysis(rewriter)
        register_request_of_syntax_availability_inspection(
          rewriter,
          :expect_available?,
          [:expect]
        )

        operator_matcher.register_request_for_dynamic_analysis(rewriter) if operator_matcher
        have_matcher.register_request_for_dynamic_analysis(rewriter) if have_matcher
      end

      def expect_available?
        check_syntax_availability(__method__)
      end

      def positive?
        method_name == :should
      end

      def expectize!(negative_form = 'not_to', parenthesize_matcher_arg = true)
        unless expect_available?
          fail InvalidContextError.new(selector_range, "##{method_name}", '#expect')
        end

        if proc_literal?(subject_node)
          replace_proc_selector_with_expect!
        else
          wrap_subject_in_expect!
        end

        replace(should_range, positive? ? 'to' : negative_form)

        @current_syntax_type = :expect
        register_record(negative_form)

        operator_matcher.convert_operator!(parenthesize_matcher_arg) if operator_matcher
      end

      def operator_matcher
        return @operator_matcher if instance_variable_defined?(:@operator_matcher)

        @operator_matcher ||= begin
          if OperatorMatcher.target_node?(matcher_node, @runtime_data)
            OperatorMatcher.new(matcher_node, @source_rewriter, @runtime_data, @report)
          else
            nil
          end
        end
      end

      def matcher_node
        arg_node || parent_node
      end

      private

      def replace_proc_selector_with_expect!
        send_node = subject_node.children.first
        range_of_subject_method_taking_block = send_node.loc.expression
        replace(range_of_subject_method_taking_block, 'expect')
      end

      def should_range
        if arg_node
          selector_range
        else
          selector_range.join(expression_range.end)
        end
      end

      def register_record(negative_form_of_to)
        if proc_literal?(subject_node)
          original_syntax = 'lambda { }.should'
          converted_syntax = 'expect { }.'
        else
          original_syntax = 'obj.should'
          converted_syntax = 'expect(obj).'
        end

        if positive?
          converted_syntax << 'to'
        else
          original_syntax << '_not'
          converted_syntax << negative_form_of_to
        end

        @report.records << Record.new(original_syntax, converted_syntax)
      end
    end
  end
end
