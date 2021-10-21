# qucsctl v0.1 Copyright(C) Anagix Corporation
$:.unshift '/home/anagix/work/alb2/lib'
$:.unshift '/home/anagix/work/alb2/ade_express'
load 'alb_lib.rb'
load 'spice_parser.rb'
load 'xyce.rb'
load 'postprocess.rb'
load 'compact_model.rb'
require 'byebug'
require 'fileutils'

class QucsControl
  attr_accessor :elements, :file, :mtime, :pid
  def initialize ckt=nil
    read ckt if ckt
  end
  
  def help
    puts <<EOF
read ckt --- make ckt the current circuit
open ckt --- open circuit editor and read the ckt
view ckt --- just view the circuit
get name, par --- get element value (ex. get('M1:l'), get('M1', 'l'), get('R1'))
set name1: value1, name2:value2, ... --- set element value (ex. set M1: 'l=1u w=1u', R1: '1k'
  set M1: '+m=8' --- adds parameter, '-m=8' --- removes parameter
elements --- show current circuit elements
mtime --- time when elements are modified
show pattern --- show elements matching the pattern
file --- show current circuit file 
simulate  --- generate raw file
sim_log --- show simulation log
info --- show what variables (nodes, currents) are available to plot
save csv_file, *node_list --- save waves in node_list to csv_file
plot *node_list --- plot waves in node_list
EOF
  end
  
  def read ckt=@file
    @file = ckt
    case File.extname ckt 
    when '.sch'
        @elements = read_sch ckt
    when '.net'
        @elements = read_net ckt
    when ''
      if File.exist? ckt+'.sch'
        @elements = read_sch ckt+'.sch'
      elsif File.exist? ckt+'.net'
        @elements = read_net ckt+'.net'
      else
      end
    end
    @mtime = Time.now
    puts "elements updated from #{@file}!"
    @elements
  end

  def read_sch file
    elements = {}
    name = type = value = value2 = nil
    lineno = line1 = line2 = 0 
    #    File.read(file).encode('UTF-8', invalid: :replace).each_line{|l|
    desc = nil
    File.read(file).each_line{|l|
      l.chomp!
      lineno = lineno + 1 
      if l =~ /<Components>/
        desc = ''
      elsif desc
        break if l =~ /<\/Components>/
        if l =~ /<Lib +(\S+) +\S+ +(\S+) +(\S+) +0 +0 +(\S+) +(\S+) +"(\S+)" 0 "(\S+)" 0 "(\S+)"/
        # c = {:type=> $1, :name=>$2, :x=>q2c($3), :y=>q2c($4), :mirror=>$5.to_i, :rotation=>$6.to_i, :lib_path=>$7, :cell_name=>$8} #caution: $ shifted
          name = $1
          cell_name = $7
          value = $8
          elements[name] = {value: value, type: cell_name, lineno: lineno}
          desc << l
        end
      end
    }
=begin
      elsif l =~ /^TEXT .* ([!;](\S+) .*$)/
        read_sch_sub elements, name, type, value, value2, line1, line2 if name
        name = $2[1..-1] # remove dot (.)
        elements[name] ||= []
        elements[name] <<  {control: $1, lineno: lineno}
        name = nil
      end
=end
    elements
  end
  private :read_sch
  
  def read_net file
    sim = Xyce.new
    net = sim.parse_netlist File.read file
  end
  private :read_net

  def get name, par=nil
    id = nil
    if name =~ /(\S+):(\S+)/
      name = $1
      par = $2
    elsif name =~ /([a-z,A-Z]+)_([0-9]+)/
      name = $1
      id = $2
    end
    read @file if File.mtime(@file) > @mtime
    if e = @elements[name]
      if id
        id = id.to_i - 1
        e[id][:control]
      elsif par
        parse_parameters(e[:value])[0][par]
      elsif e.class == Array
        e.map{|c| c[:control]}
      else
        e[:value]
      end
    end
  end
  
  def set pairs
    read @file if File.mtime(@file) > @mtime
    lines = File.read(@file)
    if lines.include? "\r\n"
      lines = lines.split("\r\n")
    else
      lines = lines.split("\n")
    end
    result =pairs.map{|sym, value|
      name = sym.to_s
      puts "set #{name}: #{value}"
      if @elements[name] && lineno = @elements[name][:lineno]
        line = lines[lineno-1]
        line =~ /((<Lib +\S+ +\S+ +\S+ +\S+ +0 +0 +\S+ +\S+ +"\S+") 0 "(\S+)" 0) "\S+"/
        # $3 is old value
        line.sub! $1, "#{$2} 0 "#{value}"
        @elements[name][:value].sub!(substr, value)
      else
        name =~ /(\S+)_(\d+)/ # like dc_1 !;dc temp -40 120 0.1\n.dc temp 120 -40 0.1
        elm = @elements[$1][$2.to_i-1]
        if elm && lineno = elm[:lineno]
          line = lines[lineno-1]
          #if line =~ /^TEXT .*!(\S+ .*)\\/ || line =~ /^TEXT .*!(\S+ .*)$/
          if line =~ /^TEXT .*(![\.;]\S+ .*)$/
            substr = $1
            line.sub! substr, value
            elm[:control] = value
            true
          else
            false
          end
        else
          puts "Error: #{name} was not found in #{@file}"
          false
        end
      end
    }
    update(@file, lines) 
    result
  end
  
  def sub a, b
    (a.split - b.split).join(' ')
  end
  private :sub
  
  def add a, b
    result = a.dup
    pairs = b.scan(/(\S+)=(\S+)/)
    pairs.each{|k, v|
      unless result.sub! /#{k}=(\S+)/, "#{k}=#{v}"
        result << " #{k}=#{v}"
      end
    }
    result
  end
  private :add

  def update file, lines
    File.open(@file, 'w:Windows-1252'){|f| f.puts lines}
    @mtime = File.mtime(@file)          
  end
  private :update

  def wait_for file, error_message=nil
    count = 0
    until File.exist? file do
      # puts "count=#{count}"
      if count == 10
        raise "#{file} is not created #{error_message}" 
        yield
      end
      sleep 1
      count = count +1
    end
  end      
  private :wait_for

  def find_outfile file
    desc = ''
    outfile = nil
    temp_flag = nil
    File.read(file).each_line{|l|
      if l =~ /.dc temp/
        temp_flag = true
      elsif l =~ /\.PRINT +\S+ format=(\S+) +file=(\S+) +(.*$)/
        format = $1
        outfile = $2
        variables = $3
        l.sub! "format=#{format}", 'format=csv'
        l.sub! variables, 'temp '+variables if temp_flag
      end
      desc << l
    }
    File.open(file, 'w'){|f|
      f.puts desc
    }
    outfile
  end

  def simulate
    file = @file.sub('.sch', '.net')
    File.delete file if File.exist? file
    Dir.chdir(File.dirname @file){
      netlister @file, File.basename(file)
      wait_for File.basename(file), 'due to some error'
    }
    if @out_file = find_outfile(file)
      File.delete @out_file if File.exist? @out_file 
    end

    Dir.chdir(File.dirname file){ # chdir or -Run does not work 
      puts "CWD: #{Dir.pwd}"
      run_xyce File.basename(file)
      wait_for(File.basename(@out_file), 'due to simulation error below'){
        puts sim_log()
      }
      puts "#{@out_file} created"
    }
  end

  def sim_log ckt=@file
    File.read(ckt.sub('.sch', '.log')).gsub("\x00", '')
  end
  
  def info
    puts "cwd: #{File.dirname @file}, circuit: #{File.basename @file}"
    variables = []
    Dir.chdir(File.dirname @file){
      File.open(@out_file){|f|
        variables = f.gets.chop.split(',')
      }
    }
    variables
  end
  
  def show pattern=nil
    read @file if File.mtime(@file) > @mtime
    pattern ||= '.*'
    result = ''
    @elements.find_all{|p, v|
      if p =~ /#{pattern}/
        if v.class == Array # control card
          v.each_with_index{|w, i|
            puts "#{w[:lineno]}: #{p}_#{i+1} #{w[:control]}"
            result << "#{w[:lineno]}: #{p}_#{i+1} #{w[:control]}" if pattern != '.*'
          }
        else
          if v[:type]
            puts "#{v[:lineno]}: #{p} #{v[:value]} (type: #{v[:type]})" 
          else
            puts "#{v[:lineno]}: #{p} #{v[:value]}" 
          end
        end
      end
    }
    result
  end

  def get_models
    cwd = get_cwd()
    include_files = get('include').map{|l|
      l =~ /include \"\.\/(\S+)\"/
      File.join cwd, $1
    }
    @models = []
    model_files(include_files).map{|f|
      m = CompactModel.new f
      @models << m
      eval "$#{m.name} = m"
      eval "@#{m.name} = m.model_params" 
      '$'+m.name
    }
  end

  def update_models
    @models.each{|m|
      m.update
    }
  end

  def activate_model inputs # this is a sample to be defined for each case
    puts "inputs=#{inputs}"
    # a=1, b=2, c=3
    @nch['VTH0'] = inputs[:a]
    @nch['U0'] = inputs[:b] + inputs[:c]
    update_models
  end

  def shift360 p
    if p > 30
      p = p -360
    end
    p
  end
  private :shift360

  def plot *node_list
    require 'rbplotly'
    vars, traces = get_traces *node_list
      
    layout = {title: "#{vars[1..-1].join(',')} vs. #{vars[0]}",
              yaxis: {title: vars[1..-1].join(',')},
              xaxis: {title: vars[0]}}
    if vars[0] == 'frequency'
      layout[:xaxis][:type] = 'log'
      db = traces.map{|trace| {x: trace[:x], y: trace[:y].map{|a| 20.0*Math.log10(a.abs)}}}
      phase = traces.map{|trace| {x: trace[:x], y: trace[:y].map{|a| shift360(a.phase*(180.0/Math::PI))}}}
      layout[:title] = vars[1..-1].map{|v| "20log10(#{v})"}.join(',')
      layout[:yaxis][:title] = vars[1..-1].map{|v| "#{v}[dB]"}.join(',')
      pl_db = Plotly::Plot.new data: db, layout: layout
      pl_db.show
      layout[:title] = vars[1..-1].map{|v| "phase of #{v}"}.join(',')
      layout[:yaxis][:title] = vars[1..-1].map{|v| "#{v}[deg]"}.join(',')
      pl_phase = Plotly::Plot.new data: phase, layout: layout
      pl_phase.show
    else
      pl = Plotly::Plot.new data: traces, layout: layout
      pl.show
    end
    nil
  end

=begin
  def plot2 *node_list
    require 'rbplotly'
    vars, traces = get_traces *node_list
    vars, traces = split_and_merge  vars, traces
    
    layout = {title: "#{node_list.reverse.join(' vs. ')}",
              yaxis: {title: node_list[1]},
              xaxis: {title: node_list[0]},
              showlegend: false
             }
    pl = Plotly::Plot.new data: traces, layout: layout
    pl.show
  end

  def plot3 sim_origvars, sim_originals, meas_traces
    require 'rbplotly'
    sim_vars, sim_traces = split_and_merge sim_origvars, sim_originals
    layout = {title: 'Simulation vs. measurement',
              showlegend: false}
    pl = Plotly::Plot.new data: sim_traces+meas_traces, layout: layout
    pl.show
  end
=end

  def plot_id_vds sim_origvars, sim_originals, title,  meas_file, indices, skip=0
    require 'rbplotly'
    trace_names = control2steps()
    sim_vars, sim_traces = split_and_merge sim_origvars, sim_originals, trace_names
    df = csvread_id_vds meas_file
    meas_traces = traces_from_df(df, indices, trace_names, skip)
    layout = {title: title, yaxis: {title: 'Id'}, xaxis: {title: 'Vds'},
              width: 600, height: 400} 
    #              showlegend: false}
    pl = Plotly::Plot.new data: sim_traces+meas_traces, layout: layout
    pl.show
    nil
  end
  
  def plot_id_vgs sim_origvars, sim_originals, title,  meas_file, indices, skip=0
    require 'rbplotly'
    trace_names = control2steps()
    sim_vars, sim_traces = split_and_merge sim_origvars, sim_originals, trace_names
    df = csvread_id_vgs meas_file, 'vbs'
    meas_traces = traces_from_df(df, indices, trace_names, skip)
    layout = {title: title, yaxis: {title: 'Id'}, xaxis: {title: 'Vgs'},
              width: 600, height: 400} 
    #              showlegend: false}
    pl = Plotly::Plot.new data: sim_traces+meas_traces, layout: layout
    pl.show
    nil
  end
  
  def tmp_info file
    File.read(file).each_line{|l|
      if l =~ /#Variables\(rc\): (.*)/
        return $1.split
      end
    }
    []
  end
      
  def included_in_tmp? node_list
    tmp_list = tmp_info(@file.sub(/\..*/, '.tmp'))
    node_list.each{|n| return false unless tmp_list.include? n}
    true
  end

  def get_traces *node_list
    node_list ||= info()
    indices = []
    vars = []
    traces = []
    File.open(@out_file){|f|
      variables = f.gets.chop.split(',')
      variables[1..-1].each_with_index{|name, i|
        if node_list.include? name
          indices << i
          vars << name
          trace = {x: [], y: []}
          traces << trace
        end
      }
      while line=f.gets
        values = line.chop.split(',')
        indices.size.times{|i|
          trace = traces[i]
          trace[:x] << values[indices[0]]
          trace[:y] << values[indices[i]]
        }
      end
    }
    [vars, traces]
  end

  def control2steps
    control = self.elements['dc'][0][:control]
    control =~ /\.dc \S+ \S+ \S+ \S+ (\S+) (\S+) (\S+) (\S+)/
    $2.to_f.step($3.to_f, $4.to_f).map{|f| "#{$1}=#{f}"}
  end

  def split_and_merge origvars, originals, trace_names = []
    vars = [origvars[0]]
    vgs = nil
    vds = originals[0][:x]
    id1 = originals[0][:y]
    traces = []
    count = 0
    trace = {x: Array_with_interpolation.new,
             y: Array_with_interpolation.new,
             name: trace_names[count]}
    prev = -1e36
    vds.each_with_index{|v, i|
      if v < prev
        vars << origvars[1] + i.to_s
        traces << trace
        count = count + 1
        trace = {x: Array_with_interpolation.new,
                 y: Array_with_interpolation.new,
                 name: trace_names[count]}
      end
      trace[:x] << v
      trace[:y] << id1[i]
      prev = v
    }
    traces << trace
    [vars, traces]
  end

  def open file=@file
    view file
    read file
  end

  def view file
    Dir.chdir(File.dirname file){
      puts command = "#{qucsexe} #{File.basename(file)}"
      # system command
      #IO_popen command
      if /mswin32|mingw/ =~ RUBY_PLATFORM
        system 'start "dummy" ' + command # need a dummy title
      else
        @pid = fork do
          exec command
        end
      end
    }
  end

  def actual_process? pid
    if RUBY_VERSION >= '4.1' 
      pid.class == Integer
    else
      pid.class == Fixnum
    end
  end
  private :actual_process?

  def netlister input, output
    puts command = "#{qucsexe} #{input} -o #{output} -n --xyce" 
    # system command
    IO_popen command
  end

  def run_xyce input
    log_file = input.sub('.net', '.log')
    IO_popen "/usr/local/bin/Xyce -l #{log_file} #{input}"
  end
#  private :netlister, :run_xyce

  def close
    if @pid
      puts "** Process to kill = #{@pid}"
      if not actual_process?(@pid) # this is for killing flow assistant?
        @pid.close
      elsif @pid > 0
        Process.detach(@pid)
        if /mswin32|mingw/ =~ RUBY_PLATFORM
          system "taskkill /pid #{@pid}"
        else
          cpid = `pgrep -P #{@pid}` # child process ID
          if cpid != ''
            Process.kill :TERM, cpid.chop.to_i # kill child process
          else
            Process.kill :TERM, @pid
          end
        end
      end
    end
  end

  def qucs_path
    if ENV['QUCS_path'] 
      return ENV['QUCS_path'] 
    elsif File.exist?( path =  "#{ENV['ProgramFiles(x86)']}\\Qucs-S\\bin\\qucs-s.exe")
      raise 'Cannot find QUCS executable. Please set QUCS_path'
    end                     
  end
  private :qucs_path

  def qucs_path_WSL
    if File.exist? path='/mnt/c/Program Files (x86)/Qucs-S/bin/qucs-s.exe'
      return "'#{path}'"
    end
    nil
  end
  private :qucs_path_WSL

  def qucsexe
    if /mswin32|mingw/ =~ RUBY_PLATFORM
      command = "\"" + qucs_path() + "\""
    elsif command = `which qucs-s` # use linux version even under WSL
      command = "#{command.chop!}"
    elsif File.directory? '/mnt/c/Windows/SysWOW64/'
      command = qucs_path_WSL() 
    else
      return 'error: wine is not install' if `which wine`==''
      command = "wine '#{qucs_path_wine}'"
    end
    command + ' -i'
  end
  private :qucsexe

  def set_input_variables inputs
    File.open('/tmp/text', 'w'){|f|
      inputs.each_pair{|k, v|
        f.puts "#{k} = #{v}"
      }
    }
  end

  def set_equations equations
    File.open('/tmp/text', 'w'){|f|
      f.puts equations
    }
  end

  def start_model_activator equations
    include_line = show 'include'
    include_line =~ /\.include +\"(\S+)\"/
    command "start_model_activator \"#{File.join(get_cwd(), $1)}\""
    set_equations equations
    command "set_equations"
  end

  def alta_activate_model inputs
    set_input_variables inputs
    command "activate_model"
  end
end
