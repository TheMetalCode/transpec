# coding: utf-8

require 'transpec/syntax'
require 'transpec/syntax/mixin/send'

module Transpec
  class Syntax
    class Have < Syntax
      include Mixin::Send

      # String#count is not query method, and there's no way to determine
      # whether a method is query method.
      # Method#arity and Method#parameters return same results
      # for Array#count (0+ args) and String#count (1+ args).
      #
      # So I make #size a priority over #count so that #count won't be chosen
      # for String (String responds to #size).
      QUERY_METHOD_PRIORITIES = [:size, :count, :length].freeze

      attr_reader :expectation

      def self.standalone?
        false
      end

      def self.target_method?(have_node, items_method_name)
        return false unless have_node
        have_receiver_node, have_method_name, *_ = *have_node
        return false if have_receiver_node
        [:have, :have_exactly, :have_at_least, :have_at_most].include?(have_method_name)
      end

      def initialize(node, expectation, source_rewriter = nil, runtime_data = nil, report = nil)
        @node = node
        @expectation = expectation
        @source_rewriter = source_rewriter
        @runtime_data = runtime_data
        @report = report || Report.new
      end

      def register_request_for_dynamic_analysis(rewriter)
        node = @expectation.subject_node

        # `expect(owner).to have(n).things` invokes private owner#things with Object#__send__
        # if the owner does not respond to any of #size, #count and #length.
        #
        # rubocop:disable LineLength
        # https://github.com/rspec/rspec-expectations/blob/v2.14.3/lib/rspec/matchers/built_in/have.rb#L48-L58
        # rubocop:enable LineLength
        key = :subject_is_owner_of_collection?
        code = "respond_to?(#{items_name.inspect}) || " +
               "(methods & #{QUERY_METHOD_PRIORITIES.inspect}).empty?"
        rewriter.register_request(node, key, code)

        key = :available_query_methods
        code = "target = #{code} ? #{items_name} : self; " +
               "target.methods & #{QUERY_METHOD_PRIORITIES.inspect}"
        rewriter.register_request(node, key, code)

        key = :collection_accessor_is_private?
        code = "private_methods.include?(#{items_name.inspect})"
        rewriter.register_request(node, key, code)
      end

      def convert_to_standard_expectation!(parenthesize_matcher_arg = true)
        replace(@expectation.subject_range, replacement_subject_source)
        replace(expression_range, replacement_matcher_source(size_source, parenthesize_matcher_arg))
        register_record
      end

      def have_node
        node.children.first
      end

      def size_node
        have_node.children[2]
      end

      alias_method :items_node, :node

      def have_method_name
        have_node.children[1]
      end

      def items_name
        items_node.children[1]
      end

      def subject_is_owner_of_collection?
        node_data = runtime_node_data(@expectation.subject_node)
        node_data && node_data[:subject_is_owner_of_collection?].result
      end

      def collection_accessor_is_private?
        node_data = runtime_node_data(@expectation.subject_node)
        node_data && node_data[:collection_accessor_is_private?].result
      end

      def query_method
        node_data = runtime_node_data(@expectation.subject_node)
        if node_data
          (QUERY_METHOD_PRIORITIES & node_data[:available_query_methods].result).first
        else
          default_query_method
        end
      end

      def default_query_method
        QUERY_METHOD_PRIORITIES.first
      end

      def replacement_matcher_source(size_source, parenthesize_arg = true)
        case @expectation.current_syntax_type
        when :should
          replacement_matcher_source_for_should(size_source)
        when :expect
          replacement_matcher_source_for_expect(size_source, parenthesize_arg)
        end
      end

      private

      def replacement_subject_source
        source = @expectation.subject_range.source
        if subject_is_owner_of_collection?
          if collection_accessor_is_private?
            source << ".send(#{items_name.inspect})"
          else
            source << ".#{items_name}"
          end
        end
        source << ".#{query_method}"
      end

      def replacement_matcher_source_for_should(size_source)
        case have_method_name
        when :have, :have_exactly then "== #{size_source}"
        when :have_at_least       then ">= #{size_source}"
        when :have_at_most        then "<= #{size_source}"
        end
      end

      def replacement_matcher_source_for_expect(size_source, parenthesize_arg)
        case have_method_name
        when :have, :have_exactly
          if parenthesize_arg
            "eq(#{size_source})"
          else
            "eq #{size_source}"
          end
        when :have_at_least
          "be >= #{size_source}"
        when :have_at_most
          "be <= #{size_source}"
        end
      end

      def size_source
        size_node.loc.expression.source
      end

      def dot_items_range
        map = items_node.loc
        map.dot.join(map.selector)
      end

      def register_record
        @report.records << HaveRecord.new(self)
      end

      class HaveRecord < Record
        def initialize(have)
          @have = have
        end

        def original_syntax
          @original_syntax ||= begin
            syntax = case @have.expectation
                     when Should
                       "#{original_subject}.should"
                     when Expect
                       "expect(#{original_subject}).to"
                     end

            syntax << " #{@have.have_method_name}(n).#{original_items}"
          end
        end

        def converted_syntax
          @converted_syntax ||= begin
            syntax = case @have.expectation.current_syntax_type
                     when :should
                       "#{converted_subject}.should"
                     when :expect
                       "expect(#{converted_subject}).to"
                     end

            syntax << " #{@have.replacement_matcher_source('n')}"
          end
        end

        def original_subject
          if @have.subject_is_owner_of_collection?
            'obj'
          else
            'collection'
          end
        end

        def original_items
          if @have.subject_is_owner_of_collection?
            @have.items_name
          else
            'items'
          end
        end

        def converted_subject
          if @have.subject_is_owner_of_collection?
            if @have.collection_accessor_is_private?
              "obj.send(#{@have.items_name.inspect}).#{@have.query_method}"
            else
              "obj.#{@have.items_name}.#{@have.query_method}"
            end
          else
            "collection.#{@have.default_query_method}"
          end
        end
      end
    end
  end
end
