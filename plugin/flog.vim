" File:        flog.vim
" Description: Ruby cyclomatic complexity analizer
" Author:      Max Vasiliev <vim@skammer.name>
" Author:      Jelle Vandebeeck <jelle@fousa.be>
" Licence:     WTFPL
" Version:     0.0.2

if !has('signs') || !has('ruby')
  finish
endif

let s:low_color        = "#a5c261"
let s:medium_color     = "#ffc66d"
let s:high_color       = "#cc7833"
let s:background_color = "#323232"
let s:medium_limit     = 10
let s:high_limit       = 20

if exists("g:flog_low_color")
  let s:low_color = g:flog_low_color
endif

if exists("g:flog_medium_color")
  let s:medium_color = g:flog_medium_color
endif

if exists("g:flog_high_color")
  let s:high_color = g:flog_high_color
endif

if exists("g:flog_background_color")
  let s:background_color = g:flog_background_color
endif

if exists("g:flog_medium_limit")
  let s:medium_limit = g:flog_medium_limit
endif

if exists("g:flog_high_limit")
  let s:high_limit = g:flog_high_limit
endif

ruby << EOF

require 'rubygems'
require 'flog'

module RubyParserStuff

  def handle_encoding str
    str = str.dup
    ruby19 = str.respond_to? :encoding
    encoding = nil

    header = str.lines.first(2)
    header.map! { |s| s.force_encoding "ASCII-8BIT" } if ruby19

    first = header.first || ""
    encoding, str = "utf-8", str[3..-1] if first =~ /\A\xEF\xBB\xBF/

    encoding = $1.strip if header.find { |s|
      s[/^#.*?-\*-.*?coding:\s*([^ ;]+).*?-\*-/, 1] ||
      s[/^#.*(?:en)?coding(?:\s*[:=])\s*([\w-]+)/, 1]
    }

    if encoding then
      if ruby19 then
        encoding.sub!(/utf-8-.+$/, 'utf-8') # HACK for stupid emacs formats
        hack_encoding str, encoding
      else
        # Turn off the warning for the magic encoding comment
        #     It blows up the command buffer in VIM
        #warn "Skipping magic encoding comment"
      end
    else
      # nothing specified... ugh. try to encode as utf-8
      hack_encoding str if ruby19
    end

    str
  end
end

class Flog
  def in_method(name, file, line, endline=nil)
    endline = line if endline.nil?
    method_name = Regexp === name ? name.inspect : name.to_s
    @method_stack.unshift method_name
    @method_locations[signature] = "#{file}:#{line}:#{endline}"
    yield
    @method_stack.shift
  end

  def process_defn(exp)
    in_method exp.shift, exp.file, exp.line, exp.last.line do
      process_until_empty exp
    end
    s()
  end

  def process_defs(exp)
    recv = process exp.shift
    in_method "::#{exp.shift}", exp.file, exp.line, exp.last.line do
      process_until_empty exp
    end
    s()
  end

  def return_report
    complexity_results = {}
    max = option[:all] ? nil : total * THRESHOLD
    each_by_score max do |class_method, score, call_list|
      location = @method_locations[class_method]
      if location then
        line, endline = location.match(/.+:(\d+):(\d+)/).to_a[1..2].map{|l| l.to_i }
        # This is a strange case of flog failing on blocks.
        # http://blog.zenspider.com/2009/04/parsetree-eol.html
        line, endline = endline-1, line if line >= endline
        complexity_results[line] = [score, class_method, endline]
      end
    end
    complexity_results
  ensure
    self.reset
  end
end

def show_complexity(results = {})
  return if Vim::Buffer.current.name.match("_spec")
  VIM.command ":silent sign unplace file=#{VIM::Buffer.current.name}"
  results.each do |line_number, rest|
    medium_limit = VIM::evaluate('s:medium_limit')
    high_limit = VIM::evaluate('s:high_limit')
    complexity = case rest[0]
      when 0..medium_limit          then "low_complexity"
      when medium_limit..high_limit then "medium_complexity"
      else                               "high_complexity"
    end
		value = rest[0].to_i
		value = "9+" if value >= 100
		VIM.command ":sign define #{value.to_s} text=#{value.to_s} texthl=#{complexity}"
    VIM.command ":sign place #{line_number} line=#{line_number} name=#{value.to_s} file=#{VIM::Buffer.current.name}"
  end
end

EOF

function! s:UpdateHighlighting()
  exe 'hi low_complexity    guifg='.s:low_color
  exe 'hi medium_complexity guifg='.s:medium_color
  exe 'hi high_complexity   guifg='.s:high_color
  exe 'hi SignColumn        guifg=#999999 guibg='.s:background_color.' gui=NONE'
endfunction

function! ShowComplexity()

ruby << EOF

options = {
      :quiet    => true,
      :continue => true,
      :all      => true
    }

begin
  flogger = Flog.new options
  flogger.flog ::VIM::Buffer.current.name
  show_complexity flogger.return_report
end

EOF

call s:UpdateHighlighting()

endfunction

call s:UpdateHighlighting()

sign define low_color    text=XX texthl=low_complexity
sign define medium_color text=XX texthl=medium_complexity
sign define high_color   text=XX texthl=high_complexity


if !exists("g:flow_enable") || g:flog_enable
  autocmd! BufReadPost,BufWritePost,FileReadPost,FileWritePost *.rb call ShowComplexity()
endif
