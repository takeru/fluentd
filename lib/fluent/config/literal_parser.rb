#
# Fluentd
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.
#

module Fluent
  module Config

    require 'yajl'
    require 'fluent/config/basic_parser'
    require 'irb/ruby-lex'  # RubyLex

    class LiteralParser < BasicParser
      def self.unescape_char(c)
        case c
        when '"'
          '\"'
        when "'"
          "\\'"
        when '\\'
          '\\\\'
        when "\r"
          '\r'
        when "\n"
          '\n'
        when "\t"
          '\t'
        when "\f"
          '\f'
        when "\b"
          '\b'
        else
          c
        end
      end

      def initialize(strscan, eval_context)
        super(strscan)
        @eval_context = eval_context
      end

      def parse_literal(string_boundary_charset = LINE_END)
        spacing_without_comment

        scan_string(string_boundary_charset)
      end

      def scan_string(string_boundary_charset = LINE_END)
        if skip(/\"/)
          return scan_double_quoted_string
        elsif skip(/\'/)
          return scan_single_quoted_string
        else
          return scan_nonquoted_string(string_boundary_charset)
        end
      end

      def scan_double_quoted_string
        string = []
        while true
          if skip(/\"/)
            return string.join
          elsif s = scan(/\\./)
            string << eval_escape_char(s[1,1])
          elsif skip(/\#\{/)
            string << eval_embedded_code(scan_embedded_code)
            skip(/\}/)
          elsif s = scan(/./)
            string << s
          else
            parse_error! "unexpected end of file in a double quoted string"
          end
        end
      end

      def scan_single_quoted_string
        string = []
        while true
          if skip(/\'/)
            return string.join
          elsif s = scan(/\\'/)
            string << "'"
          elsif s = scan(/\\\\/)
            string << "\\"
          elsif s = scan(/./)
            string << s
          else
            parse_error! "unexpected end of file in a signle quoted string"
          end
        end
      end

      def scan_nonquoted_string(boundary_charset = LINE_END)
        charset = /(?!#{boundary_charset})./

        string = []
        while true
          if s = scan(/\#/)
            string << '#'
          elsif s = scan(charset)
            string << s
          else
            break
          end
        end

        if string.empty?
          return nil
        end

        string.join
      end

      def scan_embedded_code
        rlex = RubyLex.new
        src = '"#{'+@ss.rest+"\n=end\n}"

        input = StringIO.new(src)
        input.define_singleton_method(:encoding) { external_encoding }
        rlex.set_input(input)

        tk = rlex.token
        code = src[3,tk.seek-3]

        if @ss.rest.length < code.length
          @ss.pos += @ss.rest.length
          parse_error! "expected end of embedded code but $end"
        end

        @ss.pos += code.length

        code
      end

      def eval_embedded_code(code)
        if @eval_context.nil?
          parse_error! "embedded code is not allowed in this file"
        end
        @eval_context.instance_eval(code)
      end

      def eval_escape_char(c)
        case c
        when '"'
          '"'
        when "'"
          "'"
        when "r"
          "\r"
        when "n"
          "\n"
        when "t"
          "\t"
        when "f"
          "\f"
        when "b"
          "\b"
        when /[a-zA-Z0-9]/
          parse_error! "unexpected back-slash escape character '#{c}'"
        else  # symbols
          c
        end
      end
    end
  end
end
