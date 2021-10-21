# ltspctl v0.5 Copyright(C) Anagix Corporation
if $0 == __FILE__
  $: << '.'
  $: << '/home/anagix/work/alb2/lib'
  $: << '/home/anagix/work/alb2/ade_express'
end
load 'alb_lib.rb'
load 'spice_parser.rb'
load 'ltspice.rb'
load 'postprocess.rb'
load 'compact_model.rb'
require 'byebug'
require 'fileutils'

class LTspiceControl
  attr_accessor :elements, :file, :mtime, :pid, :traces, :default, :node_list, :ltspice

  def initialize ckt=nil
    if ENV['USE_PYCALL']
      require 'pycall'
      PyCall.exec 'import ltspice'
    end

    @default = [0, 0]
    read ckt if ckt
  end
  
  def help
    puts <<EOF
read ckt --- make ckt the current circuit
open ckt --- open circuit editor and read the ckt
view ckt --- just view the circuit
get name, par --- get element value (ex. get('M1:l'), get('M1', 'l'), get('R1'))
set name1: value1, name2:value2, ... --- set element value (ex. set M1: 'l=1u w=1u', R1: '1k')
  set M1: '+m=8' --- adds parameter, '-m=8' --- removes parameter
comment name --- comment SPICE directive
uncomment name --- uncomment SPICE directive
elements --- show current circuit elements
mtime --- time when elements are modified
show pattern --- show elements matching the pattern
file --- show current circuit file 
simulate [variables,][analysis] --- generate raw file  (ex. simulate 'I(V1)', tran: '1n 10n')
sim_log --- show simulation log
info --- show what variables (nodes, currents) are available to plot
save csv_file, *node_list --- save waves in node_list to csv_file
plot *node_list --- plot waves in node_list
get_traces *node_list --- get simulation data for post processing
default= --- set default trace
x --- x array of default trace
y --- y array of default trace
EOF
  end
  
  def read ckt=@file
    raise "Error: '#{ckt}' does not exist" unless File.exist? ckt 
    @file = ckt
    case File.extname ckt 
    when '.asc'
        @elements = read_asc ckt
    when '.net'
        @elements = read_net ckt
    when ''
      if File.exist? ckt+'.asc'
        @elements = read_asc ckt+'.asc'
      elsif File.exist? ckt+'.net'
        @elements = read_net ckt+'.net'
      else
      end
    end
    @mtime = Time.now
    puts "elements updated from #{@file}!"
    @elements
  end

  def save ckt=@file
    lines = File.open(@file, 'r:Windows-1252').read.encode('UTF-8', invalid: :replace)
    @file = ckt
    update(@file, lines)
  end

  def read_asc file
    elements = {}
    name = type = value = value2 = nil
    lineno = line1 = line2 = 0 
    #    File.read(file).encode('UTF-8', invalid: :replace).each_line{|l|
    File.open(file, 'r:Windows-1252').read.encode('UTF-8', invalid: :replace).each_line{|l|
      l.chomp!
      lineno = lineno + 1 
      if l =~ /SYMATTR InstName (.*)$/
        name = $1
      elsif l =~ /SYMBOL (\S+)/
        new_type = $1
        read_asc_sub elements, name, type, value, value2, line1, line2
        type = new_type
        name = value = value2 = nil
      elsif l =~ /SYMATTR Value (.*)$/
        value = $1; line1 = lineno
      elsif l =~ /SYMATTR Value2 (.*)$/
        value2 = $1; line2 = lineno
      elsif l =~ /^TEXT .* +([!;](\S+) .*$)/
        # puts "l=#{l}"
        control = $1
        keep = $2
        # puts "contro: #{control}"
        # puts "keep: #{keep}"        
        read_asc_sub elements, name, type, value, value2, line1, line2 if name
        name = keep.gsub! /[\.\*]/, '' 
        elements[name] = []
        # puts "elements[name] = #{elements[name]}"
        if control[0] == '!'
          elements[name] <<  {control: control[1..-1], lineno: lineno}
        else
          elements[name] <<  {comment: control[1..-1], lineno: lineno}
        end
        name = nil
      end
    }
    read_asc_sub elements, name, type, value, value2, line1, line2 if name
    elements
  end
  private :read_asc
  
  def read_asc_sub elements, name, type, value, value2, line1, line2  
    if value
      if value2
        elements[name+'_1'] = {value: value, type: type, lineno: line1}
        elements[name+'_2'] = {value: value2, type: type, lineno: line2}
      else
        elements[name] = {value: value, type: type, lineno: line1}
      end
    else
      elements[name] = {value: value2, type: type, lineno: line2}
    end
  end
  private :read_asc_sub

  def read_net file
    sim = LTspice.new
    net = sim.parse_netlist File.read file
  end
  private :read_net

  def get sym, par=nil
    name = sym.to_s
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
      # puts "e=#{e}"
      if id
        id = id.to_i - 1
        e[id][:control]
      elsif par
        parse_parameters(e[:value])[0][par]
      elsif e.class == Array
        # e.map{|c| c[:control]}
        e[0][:control] || ';'+e[0][:comment]
      else
        e[:value]
      end
    end
  end
  
  def set pairs
    read @file if File.mtime(@file) > @mtime
    lines = File.open(@file, 'r:Windows-1252').read.encode('UTF-8', invalid: :replace)
    if lines.include? "\r\n"
      lines = lines.split("\r\n")
    else
      lines = lines.split("\n")
    end
    result =pairs.map{|sym, val|
      value = val.to_s
      name = sym.to_s
      # puts "set #{name}: #{value}"
      if @elements[name] && @elements[name].class == Hash
        lineno = @elements[name][:lineno]
        line = lines[lineno-1]
        if line =~ /SYMATTR Value (.*)$/
          substr = $1
          line.sub! substr, value
          @elements[name][:value].sub!(substr, value)
        elsif line =~ /SYMATTR Value2 (.*)$/
          substr = $1
          if value[0] == '-'
            value = sub substr, value[1..-1]
          elsif value[0] == '+'
            value = add substr, value[1..-1]
          end
          line.sub! substr, value
          @elements[name][:value].sub!(substr, value)
        end
        true
      else
        # puts "name=#{name.inspect}" 
        name =~ /(\S+)_(\d+)/ # like dc_1 !;dc temp -40 120 0.1\n.dc temp 120 -40 0.1
        if $2
          nth = $2.to_i-1
          name = $1
        else
          nth = 0
        end
        # puts "elm=#{elm.inspect} for @elements[#{name}][#{nth}]"
        if @elements[name] && (elm=@elements[name][nth]) && (lineno = elm[:lineno])
          line = lines[lineno-1]
          puts "line='#{line}'"
          if line =~ /^TEXT .*([!;][\*\.;]\S+ .*)$/
            substr = $1
            puts "line.sub! '#{substr}', '#{value}'"
            if value == 'comment'
              # puts 'YES!!!'
              value = substr[1..-1]
              line.sub! substr, ';' + value
              elm.delete :control
              elm[:comment] = value
            elsif value == 'uncomment'
              value = substr[1..-1]
              line.sub! substr, '!' + value
              elm.delete :comment
              elm[:control] = value
            else
              line.sub! substr, '!' + value
              elm[:control] = value
              elm.delete :comment
            end
          else
            return
          end
        elsif value == 'comment' || value == 'uncomment'
          return
        elsif value[0] != '.' # control command line .tran, .lib, etc 
          puts "Error: #{name} was not found in #{@file}"
        else
          ypos = xpos = -999999
          lines.each{|l|
            if l =~ /^TEXT +(\S+) +(\S+)/ || l =~ /^SYMBOL +\S+ +(\S+) +(\S+)/
              ypos = [$2.to_i, ypos].max
              xpos = $1 if $2.to_i == ypos
            end
          }
          lines << "TEXT #{xpos} #{ypos + 50} Left 2 !#{value}"
          @elements[name] = []
          @elements[name][nth] = {}
          @elements[name][nth][:control] = value
          @elements[name][nth][:lineno] = lines.size
        end
      end
    }
    update(@file, lines) 
    result
  end
  
  def comment name
    set name => :comment
    get name
  end

  def uncomment name
    set name => :uncomment
    get name
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

  def wait_for file, start, error_message=nil
    count = 0
    until !File.exist?(file) || (File.mtime(file) >= start) do
      puts "mtime: #{File.mtime(file)} vs. #{start}" if File.exist? file
      # puts "count=#{count}"
      if count == 20
        puts "#{file} is not created #{error_message}" 
        yield
        return
      end
      puts "count: #{count} while waiting for '#{file}'"
      count = count +1
      sleep 0.2
    end
  end      
  private :wait_for
  
  def fix_net file, analysis, extra_commands = ''
    contents = File.read(file).sub(/^\.lib .*standard.mos/, "*\\0")
    File.open(file, 'w'){|f|
      contents.each_line{|l|
        l.strip!
        if l =~ /^ *\.ac|\.tran|\.dc/
          f.puts "*#{l}"
        else
          f.puts l unless l =~ /^\.end$/
        end
      }
      analysis.each_pair{|k, p|
        extra_commands << ".#{k} #{p}\n"
      }
      extra_commands << '.end' 
      extra_commands.each_line{|l| f.puts l}
    }
    [contents, extra_commands].join "\n"
  end
  private :fix_net

  def simulate *variables
    simulate0 variables
  end

  def parse file, analysis
    netlist = ''
    File.read(file).each_line{|l|        
      l.chomp!
      if l =~ /^ *\.ac +(.*)/
        analysis[:ac] = $1
      elsif l =~ /^ *\.tran +(.*)/
        analysis[:tran] = $1
      elsif l =~ /^ *\.dc +(.*)/
        analysis[:dc] = $1
      else
        netlist << l + "\n"
      end
    }
    netlist
  end
  private :parse

  def simulate0 variables
    # system "unix2dos #{@file}" if on_WSL?() # LTspiceXVII saves asc file in LF, but -netlist option needs CRLF!
    file = @file.sub('.asc', '.net')
    analysis = {}
    # delete_file_with_retry file
    FileUtils.touch file unless File.exist? file
    Dir.chdir(File.dirname @file){ # chdir or -netlist does not work 
      ascfile = File.basename @file
      FileUtils.cp ascfile, ascfile.sub('.asc', '.tmp')
      start = Time.now
      run '-netlist', ascfile.sub('.asc', '.tmp') # creates #{file} = xxx.net
      wait_for(file, start, 'due to some error')
    }
    puts netlist = parse(file, analysis)
    puts "analysis directives in netlist: #{analysis.inspect}" unless analysis.empty?
    extra_commands = ''
    variables.each{|v|
      if v.class == Hash
        analysis = {v.first[0] => v.first[1]}
        puts "analysis set: #{analysis.inspect}"
      else
        extra_commands << ".save #{v}\n"
      end
    }
    fix_net file, analysis, extra_commands
    Dir.chdir(File.dirname @file){ # chdir or -Run does not work 
      puts "CWD: #{Dir.pwd}"
      ascfile = File.basename @file
      raw_file = ascfile.sub('.asc', '.raw')
      # delete_file_with_retry raw_file
      FileUtils.touch raw_file unless File.exist? raw_file
      start = Time.now
      run '-b -Run', file # file is xxx.net
      wait_for(raw_file, start, 'due to simulation error below'){
        wait_for start, raw_file.sub('raw', 'log')
        puts sim_log(ascfile)
      }
      puts 'execute sim_log() to show simulation log'
    }
  end
  
  def delete_file_with_retry raw_file
    num_attempts = 0
    begin
      File.delete raw_file if File.exist? raw_file 
    rescue Exception, RuntimeError, SyntaxError => e
      if num_attempts <= 10
        sleep 1
        num_attempts = num_attempts + 1
        puts "Retry(#{num_attempts}) due to #{e}"
        retry
      else
        puts e
      end
    end
  end
  
  def sim_log ckt=@file
    File.read(ckt.sub('.asc', '.log')).gsub("\x00", '')
  end
  
  def raw2tmp *node_list
    node_list = ['*'] if node_list == []
    raw_file = @file.sub(/\..*/, '.raw')
    tmp_file = @file.sub(/\..*/, '.tmp')
    sim = LTspice.new
    sim.ltsputil '-xo', raw_file, tmp_file, node_list.map{|a| "'#{a}'"}.join(' ') 
    if File.exist? tmp_file
      puts "#{tmp_file} created" 
      info
    end
  end

  def info
    puts "cwd: #{File.dirname @file}, circuit: #{File.basename @file}"
    raw_file = @file.sub(/\..*/, '.raw')
    flag = false
    variables = []
    File.open(raw_file, 'r:Windows-1252').read.each_line{|l|
      l.chomp!
      l.gsub!(0.chr,'')
      if l =~ /^Binary:/
        break 
      elsif flag
        l =~ /\s+\d+\s+(\S+)/
        variables << $1
      elsif l =~ /^Variables:/
        flag = true
      end
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

  def plot *node_list
    plot0 node_list, '.raw'
  end

  def fft_plot *node_list
    plot0 node_list, '.fft'
  end

  def plot0 node_list, extname
    node_list = @node_list if node_list.size == 0
    @node_list = node_list
    require 'rbplotly'
    if node_list[0].class == Hash
      pl=Plotly::Plot.new data: node_list, layout: node_list[0][:layout]
      pl.show
      return
    end
    vars, traces = get_traces0 node_list, extname
    # puts "vars=#{vars}, traces=#{traces}"
    return if vars.nil?
      
    layout = {title: "#{vars[1..-1].join(',')} vs. #{vars[0]}",
              yaxis: {title: vars[1..-1].join(','), linewidth:1, mirror: true},
              xaxis: {title: vars[0], linewidth:1, mirror: true}}
    # puts layout
    if vars[0].downcase == 'frequency'
      layout[:xaxis][:type] = 'log'
      db = traces.map{|trace| {name: trace[:name], x: trace[:x], y: trace[:y].map{|a| 20.0*Math.log10(a.abs)}}}
      phase = traces.map{|trace| {name: trace[:name], x: trace[:x], y: trace[:y].map{|a| shift360(a.phase*(180.0/Math::PI))}}}
      layout[:title] = vars[1..-1].map{|v| "20log10(#{v})"}.join(',')
      if extname == '.raw'
        layout[:yaxis][:title] = vars[1..-1].map{|v| "#{v}[dB]"}.join(',')
      else
        layout[:yaxis][:title] = 'Voltage spectrum [dBV]'
      end
      pl_db = Plotly::Plot.new data: db, layout: layout
      pl_db.show
      if extname == '.raw'
        layout[:title] = vars[1..-1].map{|v| "phase of #{v}"}.join(',')
        layout[:yaxis][:title] = vars[1..-1].map{|v| "#{v}[deg]"}.join(',')
        pl_phase = Plotly::Plot.new data: phase, layout: layout
        pl_phase.show
      end
    else
      pl = Plotly::Plot.new data: traces, layout: layout
      pl.show
    end
    nil
  end
  private :plot0

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

  def plot_id_vds sim_vars, sim_originals, title,  meas_file, indices, skip=0, polarity=0b0000
    require 'rbplotly'
    trace_names = control2steps()
    if meas_file =~ /\.csv/
      sim_vars, sim_traces = split_and_merge sim_origvars, sim_originals, trace_names
      df, ind = csvread_id_vds meas_file
      # puts "ind=#{ind}"
    elsif meas_file =~ /\.xlsx/
      sim_traces = sim_originals.map.with_index{|trace, i| {x: trace[:x], y: trace[:y], name: trace_names[i]}}
      sheet, size = indices
      df, indices = xslread_id_vds meas_file, sheet, size
      # puts "indices=#{indices}"
      # puts "df.size = #{df.size}"
    end
    # puts "df = #{df}"
    meas_traces = traces_from_df(df, indices, [], skip)
    layout = {title: title, yaxis: {title: 'Id'}, xaxis: {title: 'Vds'},
              width: 600, height: 400} 
    #              showlegend: false}
    pl = Plotly::Plot.new data: reverse(sim_traces, polarity[3], polarity[2])+reverse(meas_traces, polarity[1], polarity[0]), layout: layout
    pl.show
    nil
  end

  def plot_id_vgs sim_origvars, sim_originals, title,  meas_file, indices, skip=0, polarity=0b0000
    require 'rbplotly'
    trace_names = control2steps()
    if meas_file =~ /\.csv/
      sim_vars, sim_traces = split_and_merge sim_origvars, sim_originals, trace_names
      df = csvread_id_vgs meas_file, 'vbs'
    elsif meas_file =~ /\.xlsx/
      sim_traces = sim_originals
      sheet, size = indices
      df, indices = xslread_id_vgs meas_file, sheet, size
      # puts "indices=#{indices}"
      # puts "df.size = #{df.size}"
    end
    meas_traces = traces_from_df(df, indices, [], skip)
    layout = {title: title, yaxis: {title: 'Id'}, xaxis: {title: 'Vgs'},
              width: 600, height: 400, showlegend: false} 
    pl = Plotly::Plot.new data: reverse(sim_traces, polarity[3], polarity[2])+reverse(meas_traces, polarity[1], polarity[0]), layout: layout
    pl.show
    nil
  end

  def inverse traces, pol_x, pol_y, skip=0
    new_traces = []
    0.step(traces.size-1, 1+skip){|i|
      trace = traces[i].dup
      x = (pol_x == 0)? trace[:x] : trace[:x].map{|a| -a.to_f}
      y = (pol_y == 0)? trace[:y] : trace[:y].map{|a| -a.to_f}
      trace[:x] = x
      trace[:y] = y
      new_traces << trace
    }
    new_traces
  end
  alias :reverse :inverse
  private :reverse, :inverse # reverse was used mistakenly
  
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

=begin
  def get_traces *node_list
    tmp_file = @file.sub(/\..*/, '.tmp')
    raw_file = tmp_file.sub('.tmp', '.raw')
    if File.exist? raw_file
      unless File.exist?(tmp_file) and File.mtime(raw_file) <  File.mtime(tmp_file) and
            included_in_tmp?(node_list) # node_list includes more nodes than in tmp_file
        node_list = ['*'] if node_list == []
        raw2tmp *node_list
      end
    else
      puts "Caution! The latest simulation result #{raw_file} is not available."
      unless File.exist?(tmp_file) && included_in_tmp?(node_list)
        raise "Plot data for #{node_list} from OLD simulation is not available!"
      end
      puts 'So, the plot below is from OLD simulation!'
    end
    indices = []
    vars = []
    traces = []
    flag_data = false
    rc = false # is not real and complex
    File.read(tmp_file).each_line{|l|
      if flag_data
        values = l.split(',')
        if node_list.size > 0
          plot_data = []
          indices.each{|i|
            plot_data << values[i]
          }
        else
          plot_data = values
        end
        # puts plot_data.join(',')
        # data << plot_data
        traces_size = rc ? (traces.size-1)/2+1 : traces.size
        traces_size.times{|i|
          traces[i][:x] << plot_data[0].to_f
          # puts "traces#{i}:"; puts plot_data.inspect
          if rc
            traces[i][:y] << Complex(plot_data[2*i+1], plot_data[2*i+2])
          else
            traces[i][:y] << plot_data[i+1].to_f
          end
        }
      elsif l=~ /^#Variables\((.*)\): (.*)/
        # rc = ($1 == 'rc') # useless
        if node_list.size > 0
          variables = $2.split
          rc = true if variables[0] == 'frequency'
          variables.each_with_index{|name, i|
            if node_list.include? name
              if i > 0 && rc
                indices << 2*i + 1
                indices << 2*i + 2
              else
                indices <<  i
              end
              vars << name
            end
          }
        else
          vars = $2.split
        end
        traces = Array.new(vars.size-1)
        traces.size.times{|i|
          traces[i] = {x: Array_with_interpolation.new, y: Array_with_interpolation.new}
        }
        # return indices
      elsif l=~/^#Values:/
        flag_data = true 
        puts node_list.join(',')
      end
    }
    [vars, traces]
  end
=end

=begin
  def get_traces *node_list
    raw_file = @file.sub(/\..*/, '.raw')
    PyCall.exec "l=ltspice.Ltspice('#{raw_file}')"
    PyCall.exec "l.parse()"
    # x_data = PyCall.eval "l.getData('#{node_list[0]}')"
    var0 = PyCall.eval "l._variables[0]"
    # puts "var0='#{var0}'"
    if node_list[0] == var0.to_s
      x_data = PyCall.eval "l.time_raw"
      # puts "x_data = #{x_data}"
    end
    #x_data = PyCall.eval "l.getTime()"
    num_cases = PyCall.eval "l.getCaseNumber()"
    traces = []
    num_cases.times{|i|
      traces << node_list[1..-1].map{|y|
        trace = {x: Array_with_interpolation.new, y: Array_with_interpolation.new, name: y}
        y_data = PyCall.eval "l.getData('#{y}', #{i})"
        x_data.size.times{|i|
          trace[:x] << x_data[i]
          trace[:y] << y_data[i]
        }
        trace
      }
    }
    [node_list, traces.flatten]
  end
=end  

  def x
    @traces[@default[0]][@default[1]][:x]
  end

  def y
    @traces[@default[0]][@default[1]][:y]
  end

  def get_traces *node_list
    get_traces0 node_list, '.raw'
  end

  def get_fft_traces *node_list
    get_traces0 node_list, '.fft'
  end
  
  def get_traces0 node_list, extname
    raw_file = @file.sub(/\..*/, extname)
    if ENV['USE_PYCALL']
      PyCall.exec "l=ltspice.Ltspice('#{raw_file}')"
      PyCall.exec "l.parse()"
      variables = PyCall.eval "l._variables"
    else
      @ltspice = Ltspice.new raw_file
      @ltspice.parse()
      variables = @ltspice._variables
    end
    # x_data = PyCall.eval "l.getData('#{node_list[0]}')"
    
    # puts "var0='#{var0}'"
    if node_list[0].downcase == 'frequency' 
      if ENV['USE_PYCALL']
        x_data = PyCall.eval("list(l.getFrequency())").to_a
      else
        x_data = @ltspice.getFrequency()
      end
      if x_data.nil? || x_data.size == 0
        puts 'Error: AC analysis results are not available'
        return
      end
    elsif node_list[0] == variables[0].to_s
      if ENV['USE_PYCALL']
        x_data = PyCall.eval "list(l.time_raw)"
      else
        x_data = @ltspice.time_raw
      end
      x_data = x_data.map{|a| a.to_f.abs}
      # puts "x_data = #{x_data}"
    else
      if ENV['USE_PYCALL']
        x_data = PyCall.eval "list(l.getData('#{node_list[0]}'))"
      else
        x_data = @ltspice.getData(node_list[0]).to_a
      end
    end

    equations = node_list[1..-1].map{|a|a.dup}
    vars = variables.select{|v| equations.join(',').include? v}
    equations.each{|eq|
      vars.each_with_index{|v, i|
        eq.gsub! v, "values[#{i}][j]"
      }
    }
    #puts "#{node_list[1..-1]} => #{equations}"

    if ENV['USE_PYCALL']
      num_cases = PyCall.eval "l.getCaseNumber()"
    else
      num_cases = @ltspice.getCaseNumber()
    end
    @traces = []
    num_cases.times{|i|
      @traces << node_list[1..-1].map.with_index{|y, k|
        trace = {x: Array_with_interpolation.new, y: Array_with_interpolation.new, name: y}
        # y_data = PyCall.eval "l.getData('#{y}', #{i})"
        values = []
        vars.each{|v|
          if ENV['USE_PYCALL']
            value = PyCall.eval("l.getData('#{v}', #{i}).tolist()")
          else
            value = @ltspice.getData(v, i).to_a
          end
          if node_list[0].downcase == 'frequency'
            values << value.map{|a| Complex(a.real.to_f, a.imag.to_f)}
          else
            values << value
          end
        }
        #puts "equations[#{k}] = '#{equations[k]}'"
        @pass_values = {cur_x: nil, prev_x: nil, prev_y: [], count: 0}
        x_data.each_with_index{|v, j|
          @pass_values[:count] = 0
          @pass_values[:prev_x] = @pass_values[:cur_x]
          @pass_values[:cur_x] = v
          if val = eval(equations[k])
            trace[:x] << v
            trace[:y] << val
          end
        }
        trace
      }
    }
    [node_list, @traces.flatten]
  end
  private :get_traces0

  def deriv value
    result = nil
    count = @pass_values[:count]
    #puts "count: #{count}"
    if @pass_values[:prev_x]
      #puts "value: #{value}"
      #puts "@pass_values[:prev_y][#{count}]) = #{@pass_values[:prev_y][count]}"
      #puts "@pass_values[:cur_x] = #{@pass_values[:cur_x]}"
      #puts "@pass_values[:prev_x] = #{@pass_values[:prev_x]}"
      #puts "@pass_values[:prev_x] isn't nil!!!"
      result = (value-@pass_values[:prev_y][count])/(@pass_values[:cur_x] - @pass_values[:prev_x])
    else
      #puts "@pass_values[:prev_y] = #{@pass_values[:prev_y] .inspect}"
      @pass_values[:prev_y] << nil
    end
    #puts "@pass_values=#{@pass_values}"
    @pass_values[:prev_y][count] = value
    @pass_values[:count] = @pass_values[:count] + 1
    #puts "=> @pass_values=#{@pass_values}"
    result
  end
  alias :d :deriv

  def control2steps
    control = (self.elements['dc'] || self.elements['.dc'])[0][:control]
    # puts "control='#{control}'"
    control =~ /[^*]*\.dc +\S+ +\S+ +\S+ +\S+ +(\S+) +(\S+) +(\S+) +(\S+)/ ||
      control =~ /[^*]*\.dc +(\S+) +(\S+) +(\S+) +(\S+)/
    $2.to_f.step($3.to_f, $4.to_f).map{|f| "#{$1}=#{f.round(4)}"}
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
      # system command
      #IO_popen command
      if /mswin32|mingw/ =~ RUBY_PLATFORM
        puts command = "#{ltspiceexe} #{File.basename(file)}"
        system 'start "dummy" ' + command # need a dummy title
      else
        puts command = "#{ltspiceexe} '#{File.basename(file)}'"
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

  def run arg, input
    if /mswin32|mingw/ =~ RUBY_PLATFORM
      puts command = "#{ltspiceexe} #{arg} #{input}"
    else
      puts command = "#{ltspiceexe} #{arg} '#{input}'" # '#{ltspiceexe}' does not work!
    end
    system command
    # IO_popen command
  end

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

  def ltspice_path
    if ENV['LTspice_path'] 
      return ENV['LTspice_path'] 
    elsif File.exist?( path =  "#{ENV['PROGRAMFILES']}\\LTC\\LTspiceXVII\\XVIIx64.exe")
      return path
    elsif File.exist?( path =  "#{ENV['PROGRAMFILES']}\\LTC\\LTspiceXVII\\XVIIx86.exe")
      return path
    elsif File.exist?( path =  "#{ENV['ProgramFiles(x86)']}\\LTC\\LTspiceIV\\scad3.exe")
      raise 'Cannot find LTspice executable. Please set LTspice_path'
    end                     
  end
  private :ltspice_path

  def ltspice_path_WSL
    ['/mnt/c/Program Files/LTC/LTspiceXVII/XVIIx64.exe',
     '/mnt/c/Program Files (x86)/LTC/LTspiceIV/scad3.exe'].each{|path|
      return "'#{path}'" if File.exist? path
    }
    nil
  end
  private :ltspice_path_WSL

  def ltspiceexe
    if /mswin32|mingw/ =~ RUBY_PLATFORM
      command = "\"" + ltspice_path() + "\""
    elsif File.directory? '/mnt/c/Windows/SysWOW64/'
      command = ltspice_path_WSL()
    else
      return 'error: wine is not install' if `which wine`==''
      command = "wine '#{ltspice_path_wine}'"
    end
    command
  end
  private :ltspiceexe

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
