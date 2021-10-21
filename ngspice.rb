# coding: utf-8
# Copyright(C) 2009-2020 Anagix Corporation
#require 'rubygems'
#require 'ruby-debug'

require 'pp'
#require './invoker.rb'
require 'ffi'

module Invoker
  extend FFI::Library
  if /mswin32|mingw|cygwin/ =~ RUBY_PLATFORM
    # ffi_lib "c:/'Program Files'/KiCad/bin/libngspice-0.dll"
    Dir.chdir("c:/Program Files/KiCad/bin"){ 
      ffi_lib "libngspice-0.dll"
    }
  else
    ffi_lib '/usr/local/lib/libngspice.so'
  end

  callback :SendChar, [:string, :int, :pointer], :int
  callback :SendStat, [:string, :int, :pointer], :int
  callback :ControlledExit, [:int, :bool, :bool, :int, :pointer], :int
  callback :SendData, [:pointer, :int, :int, :pointer], :int
  callback :SendInitData, [:pointer, :int, :pointer], :int
  callback :BGThreadRunning, [:bool, :int, :pointer], :int
  attach_function :ngSpice_Init, [:SendChar, :SendStat, :ControlledExit,
                    :SendData, :SendInitData, :BGThreadRunning, :pointer], :int
  attach_function :ngSpice_Command, [:string], :int
  attach_function :ngSpice_Circ, [:pointer], :int
  attach_function :ngSpice_running, [ ], :bool
end

module Ngspice

  @@send_char_proc = Proc.new{ |str, id, user_data|
    if @@send_char_buffer
      @@send_char_buffer << str
    else
      send_char(str, id, user_data)
    end
  }
  @@send_char_buffer = nil

  module_function
  def init
    Invoker.ngSpice_Init(@@send_char_proc, nil, nil, nil, nil, nil, nil)
    Invoker.ngSpice_Command('set nomoremode')
  end

  def send_char(str, id, user_data)
    puts(str)
  end

  def circ(circuit_string)
    # 行ごとの文字列に分割し、それぞれの先頭ポインタを持つ配列(char**)にする
    lines = circuit_string.split("\n")
    pointerArray = FFI::MemoryPointer.new(:pointer, lines.size + 1)
    strPointers = lines.collect { |s| FFI::MemoryPointer.from_string(s) }
    strPointers << nil # NULLの番兵
    pointerArray.put_array_of_pointer(0, strPointers)

    Invoker.ngSpice_Circ(pointerArray)
  end

  def command(str)
    Invoker.ngSpice_Command(str)
  end

  def info
    command 'display'
  end

  def get_result variables = nil
    @@send_char_buffer = []
    begin
      begin
        # puts "print #{(variables && variables.size>0) ? variables.join(' ') : 'all'}"
        Invoker.ngSpice_Command("print #{variables ? variables.join(' ') : 'all'}")
      rescue => ex
        ex.to_s
      end
      all_tokens = @@send_char_buffer.collect{|line| line.split() }
      header = all_tokens.find_all{|t| t.size >= 2 && t[1] == 'Index' }.first
      values = all_tokens.find_all{|t| t.size >= 2 && t[1] =~ /\d+/ }
      data = []
      values.each do |line_values|
        line = {}
        for i in 1...header.size
          line[header[i]] = line_values[i]
        end
        data << line
      end
      data
    ensure
      @@send_char_buffer = nil
    end
  end

end

class NGspice < Spice

# ruby ngspice.rb input 

# ngspice = NGspice.new
# ngspice.run
# ngspice.command 'print line v(11) v.x0.v1#branch v.x0.v2#branch v.x0.v3#branch v.x0.v4#branch v.x0.v5#branch'
# ngspice.quit

  def name
    self.class.name
  end

  def run input, args=nil, marching=false, display=nil
    @p = IO.popen "ngspice -i -a #{input}", 'r+'
    #  p 'port=', p
    #  p.puts 'echo TEST TEST TEST'
    @p.puts 'set nomoremode'
    @p.close
    nil
  end
  
  def command string
    @p.puts string
    result = nil
    @p.puts 'echo EOF'
    while line=@p.gets
      break if /EOF/ =~ line
      if /([^ ]+) =/ =~ line
        result ||= ''
        line.gsub!($1, "'#{$1}'").gsub!('=', '=>')
      elsif /No. of Data Rows/ =~ line
        result = ''
        line = ''
      end
      result << line if result
    end
    result.gsub!(/^.*->/,'{').gsub!(' ( ',' [ ').gsub!("\t)",' ],')
    result.gsub!("\t",',').gsub!("\n",'')
    result = result + '}'
    return eval(result)
  end

  def end
    @p.puts 'quit'
    @p.puts 'yes'
    while line=@p.gets
      #    print "[#{line.chop}]\n"
    end
    @p.close
  end

  def save file, *nodes
    result = command('print line ' + nodes.join(' '))
    out = File.open file, 'w'
    out.puts nodes.join(',')
    result[nodes.first].size.times{|i|
      out.puts nodes.map{|node|
        result[node][i]}.join(',')
    }
    out.close
  end

  def valid_atype? type
    %w[ac dc tran noise].include? type
  end

  def rescue_error
  end

  def do_eval scr
    @ngspice = self
    eval scr
  end
end

if $0 == __FILE__
  sim = NGspice.new
  sim.run ARGV[0]
  result = sim.command 'print line v(11) v.x0.v1#branch v.x0.v2#branch v.x0.v3#branch v.x0.v4#branch v.x0.v5#branch'
  result2 = sim.command 'print line v(21)'
  p result['v(11)']
  p result2
  sim.save 'out.csv', 'v(11)', 'v.x0.v5#branch'
  sim.end
end
