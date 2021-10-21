# -*- coding: utf-8 -*-
# Copyright(C) 2009-2020 Anagix Corporation
#require 'rubygems'
#require 'ruby-debug'

module SpiceParser
end

class SPICE_parser
  attr_accessor :exist, :nodes, :sweep

  def initialize testbench_name='', simulator=nil , nodes =["'...'"]
    @tb_name = testbench_name
    @simulator = simulator
    @nodes = nodes || ["'...'"]
    @tb_core_name = testbench_name.dup
    if simulator
      index = testbench_name.downcase.index simulator.downcase
      @tb_core_name[index-1..index+simulator.length] = '' if index # remove _(simulator)_ 
    end
  end

  def plot
    nil
  end

  def batch_script
#    script = File.open(File.join(RAILS_ROOT, 'lib', File.basename(__FILE__))).read + "\n"
    script = copy_file_to_load(File.basename(__FILE__))
  end

  def join nodes
    nodes.map{|a| "'#{a}'"}.join(', ')
  end
end

class SPICE_DC < SPICE_parser
  def parse l
    if l =~ /^ *\.dc ([^ ]+) +/
      @param = $1
      @exist = true
    elsif l =~ /^ *\.print dc (.*) */
      @nodes = $1.split.map{|a| "'#{a}'"}
    end
  end
      
  def postprocess
    pp = "#{@tb_core_name}_dc: dc\n"
    @sweep = (@param.downcase == 'temp')? 'temperature' : @param
    pp << " wave = @#{@simulator}.save 'dc.csv', 'dc', '#{@sweep}', #{@nodes.join(',')}\n"
    return pp
  end

  def plot
    {'name'=>"#{@tb_core_name}_dc", 'file'=>'dc.csv', 'title'=>'dc sweep', 
      'xlabel'=>@param, 'ylabel'=>'output',
      'xscale'=>'linear', 'yscale'=>'linear'}
  end

end

class SPICE_AC < SPICE_parser

  def parse l
    if l =~ /^ *\.ac *([^ ]+)/
      @step = 'linear'
      @step = 'log' if $1 == 'dec' || $1 == 'oct'
      @exist = true
    elsif l =~ /^ *\.print *ac (.*) */
      @nodes = $1.split.map{|a| "'#{a}'"}
    end
  end

  def postprocess
    @sweep = 'frequency'
    puts "*** @nodes: #{@nodes.inspect}"
    nodes_list = "''"
    nodes_list = @nodes.join(', ') if @nodes.size > 0
    pp = "#{@tb_core_name}_gain: ac\n"
    pp << " wave = @#{@simulator}.save 'gain.csv', 'ac', 'frequency', #{nodes_list}\n"
    pp << " # freq = wave.col_vec 0\n"
    pp << " # gain = wave.col_vec 1\n"
    pp << " # phase = wave.col_vec 2\n"
    return pp
  end

  def plot
    {'name'=>"#{@tb_core_name}_gain", 'file'=>'gain.csv', 'title'=>'Frequency response', 
      'xlabel'=>'freq.', 'ylabel'=>'gain',
      'xscale'=>@step, 'yscale'=>'linear'}
  end
end

class SPICE_TRAN < SPICE_parser
  def parse l
    if l =~ /^ *\.tran/
      @exist = true
    elsif l =~ /^ *\.print *tran (.*) */
      @nodes = $1.split.map{|a| "'#{a}'"}
    end
  end

  def postprocess
    @sweep = 'time'
    pp = "#{@tb_core_name}_tran: tran\n"
    pp << " wave = @#{@simulator}.save 'tran.csv', 'tran', 'time', #{@nodes.join(', ')}\n"
    return pp
  end

  def plot
    {'name'=>"#{@tb_core_name}_tran", 'file'=>'tran.csv', 'title'=>'Transient response', 
      'xlabel'=>'time', 'ylabel'=>'output',
      'xscale'=>'linear', 'yscale'=>'linear'}
  end
end

class SPICE_NOISE < SPICE_parser
  
  def parse l
    if l =~ /^ *\.noise +([^ ]+) +([^ ]+) +([^ ]+)/
      @step = 'linear'
      @step = 'log' if $3 == 'dec' || $3 == 'oct'
      @exist = true
    elsif l =~ /^ *\.print noise (.*) */
      @nodes = $1.split.map{|a| "'#{a}'"}
    end
  end

  def postprocess
    @sweep = 'frequency'
    pp = "#{@tb_core_name}_noise: noise\n"
    pp << " wave = @#{@simulator}.save 'noise.csv', 'noise', 'frequency', #{@nodes.join(', ')}\n"
    return pp
  end

  def plot
    {'name'=>"#{@tb_core_name}_noise", 'file'=>'noise.csv', 'title'=>'Noise', 
      'xlabel'=>'freq.', 'ylabel'=>'noise',
      'xscale'=>@step, 'yscale'=>'linear'}
  end
end

class SPICE_TF < SPICE_parser
  def parse l
    if l =~ /^ *\.tf +([^ ]+) +([^ ]+)/
      @exist = true
    end
  end

  def postprocess pp
    @sweep = nil
    pp << " @trans_gain, @input_res, @out_res = #{@simulator}.get_tf\n"
    return nil, pp
  end
end

class SPICE_OP < SPICE_parser
  def parse l
    if l =~ /^dcOp dc/
      @exist = true
    end
  end

  def postprocess pp
    @sweep = nil
    pp << "# @idc, @idc2 = #{@simulator}.get_dc 'v1#p', 'v0#p'\n"
    return nil, pp
  end
end

CONVERSION_SOURCE = {'Ngspice' => ['LTspice', 'Xyce', 'Spectre'], 'Xyce' => ['Spectre', 'LTspice'], 'LTspice' => ['Spectre'], 'QUCS' => ['LTspice', 'Spectre', 'AgilentADS'], 'Spectre' => ['LTspice']} unless defined? CONVERSION_SOURCE

class Converter
  def numeric?(object)
    true if Float(object) rescue false
  end
  
  def unwrap netlist, ignore_comments=true    # line is like:
    puts '*** unwrap *** unwrap *** unwrap *** unwrap *** unwrap *** unwrap ***'
    result = ''         # abc
    breaks = []         #+def   => breaks[0]=[3]
#prof_result = RubyProf.profiler {
    pos = 0
    line = '' 
    bs_breaks = []
    netlist && netlist.each_line{|l|  # line might be 'abc\n' or 'abc\r\n'
      next if ignore_comments && (l[0,1] == '*' || l[0,1] == '/') # just ignore comment lines
#puts l
#      l_chop = l.dup
#      l_chop[-2,2] == '' if l_chop[-2,2] == "\r\n"
#      l_chop[-1,1] == '' if l_chop[-1,1] == "\n"
      l_chop = l.chop
#      if l.chop[-1,1] == "\\"
      if l_chop[-1,1] == "\\"
        line << l_chop
        line[-1,1] = ' '   # replace backslash with space
        bs_breaks << -(line.length-1)   # record by minus number
        next
      end
      line << l
      if /^\+/ =~ line
#        result.chop!          # remove \r and \n
        result[-2,2] = '' if  result[-2,2] == "\r\n"
        result[-1,1] = '' if  result[-1,1] == "\n"
        result << ' ' if result[-1,1] != ' ' && line[1,1] != ' '
        breaks[-1] << result.length - pos
        bs_breaks.each{|bs|
          breaks[-1] << -(result.length + (-bs)-1)  # -1 is to adjust for +
        }
        result << line[1..-1]
      else
        pos = result.length
        result << line
        #      breaks << []
        breaks << bs_breaks
      end
      bs_breaks = []
#puts "line: #{line}"
      line = ''
    }
#}
#puts prof_result
    [result, breaks]
  end

  def remove_unsupported_parameters! description, model_parameters, unsupported, tool='LTspice'
    return description if unsupported.size == 0
    deleted = "*Notice: parameters unsupported by #{LTspice} removed\n"
    i = 0
    unsupported.each{|p|
      next if model_parameters[p].nil?
      description.sub!(" #{p}=#{model_parameters[p]}", '')
      description.sub!("+#{p}=#{model_parameters[p]}", '+')
      if i % 4 == 0
        deleted << "* #{p}=#{model_parameters[p]}" 
      elsif i % 4 == 3
        deleted << " #{p}=#{model_parameters[p]}\n"
      else
        deleted << " #{p}=#{model_parameters[p]}"
      end
      i = i + 1
    }
    if i > 0
      description << deleted +"\n"
    else
      description
    end
  end  

  def replace_model_parameter description, model_parameters, a, b
#      description.sub!(/tref *= *#{model_parameters['tref']}/, "tnom = #{model_parameters['tref']}")
    description.sub!(/#{a} *= *#{model_parameters[a]}/, "#{b} = #{model_parameters[a]}")
  end
end

class Spectre_to_SPICE < Converter
  def convert_model_library description
    description = spectre_to_spice description
    return description
  end

  MODEL_TYPE_TO_SYMBOL = {'diode' => 'd', 'DIODE' => 'D',
    'bjt' => 'q', 'BJT' => 'Q', 'hbt' => 'q', 'HBT' => 'Q',
    'vbic' => 'q', 'VBIC' => 'Q', 'ekv' => 'm', 'EKV' => 'M', 
    'bsim1' => 'm', 'BSIM1' => 'M', 'bsim2' => 'm', 'BSIM2' => 'M', 
    'bsim3' => 'm', 'BSIM3' => 'M', 'bsim3v3' => 'm', 'BSIM3v3' => 'M', 
    'bsim4' => 'm', 'BSIM4' => 'M', 'hvmos' => 'm', 'HVMOS' => 'M',
    'hisim' => 'm', 'HISIM' => 'M', 'bsimsoi' => 'm', 'BSIMSOI' => 'M',
    'jfet' => 'j', 'JFET' => 'J',
    'capacitor' => 'c', 'CAPACITOR' => 'C', 'resistor' => 'r', 'RESISTOR' => 'R'
  } unless defined? MODEL_TYPE_TO_SYMBOL

  def convert_if_else_clause description
    lines = ''
    depth = 0  
    description.each_line{|l|
#debugger if l=~/(ELSE|else)/
      if l =~ /^ *(if|IF)([\( ]+.*) *\{/
        l.sub! $&, ' '*depth + "IF #{$2}"
        puts l
        depth = depth + 1
      elsif depth > 0
        if l =~ /^ *\} *(else|ELSE) +(if|IF)([\( ]+.*) *\{/
          l.sub! $&, ' '*(depth-1) + "ELSE IF #{$3}"
          puts l
        elsif l =~ /^ *\} *(else|ELSE) *\{ *$/
          l.sub! $&, ' '*(depth-1) + 'ELSE'
          puts l
        elsif l =~ /^ *\} *$/
          depth = depth - 1
          l.sub! $&, ' '*depth + 'END'
          puts l
        end
      end
      lines << l
    }
    lines
  end

  def spectre_to_spice description
    return nil unless description
    spice_model = ''
    model_name = nil
    model_type = nil
    subckt_name = nil
    flag = nil  # lang=spice if true
    binflag = nil
    binnumber = 0
#    unwrapped = nil
#    breaks = nil
#result = RubyProf.profiler {
    unwrapped, breaks = unwrap description    # continuation w/ '+' unwrapped    
#}
#puts result
    count = -1
#    unwrapped.gsub(/\\\r*\n/, '').each_line{|l|
    unwrapped.each_line{|l|
      count = count + 1
      wl = wrap(l, breaks[count])
# puts "wl:#{wl.inspect}"
      next if wl =~ /^ *\*/ && !(wl =~ /\n.+$/) ### erase single comment lines 
                                                ### leave comment wrapped inside continuation
      if binflag
        if wl.include? '}' 
          binflag = nil
        elsif wl =~ /^ *\*/
          spice_model << wl
        elsif wl =~ /^ *\/\//
          spice_model << '*' + wl[2..-1]
        else
          # wl is like '0: type=n\n+ lmin=...\n...' 
          binnumber, s = wl.split(/: */)
#          spice_model << ".model #{model_name}.#{binnumber.to_i+1} #{model_type} " + s
          spice_model << ".model #{model_name}.#{binnumber} #{model_type} " + s
        end

      elsif wl =~ /^ *\) *$/            #### very special handling for HSPICE model
        spice_model << wl.sub(/^ */,'+') #### ending the model with only ')' 

      elsif wl =~ /^ *\/\//
        spice_model << '*' + wl[2..-1]
      elsif wl =~ /^ *\.*model +(\w+) +(\w+)/ || wl =~ /^ *\.*MODEL +(\w+) +(\w+)/
        model_name = $1
        model_type = $2
        puts "*** spectre_to_spice for model: #{model_name} type: #{model_type} ***"
        if $2 == 'diode' || $2 == 'DIODE'
          wl.sub!(/#{model_type}/, 'd')
        end
        unless wl.include? '{'
          if flag || wl.downcase =~ /\.model/
            spice_model << wl
          else
            spice_model << wl.sub(/^ */,'.') # what is this for ??? lang=spectre???
          end
        else # binned model (model selection in Spectre)
          binflag = true
        end
      elsif wl =~ /simulator +lang *= *spectre/
        flag = nil
        next
      elsif wl =~ /simulator +lang *= *spice/
        flag = true
        next
      elsif flag
        spice_model << wl
        next
      elsif wl =~ /^ *#/
        spice_model << wl
      elsif wl =~ /^ *parameters/ || wl =~ /^ *PARAMETERS/
        pairs, singles = parse_parameters(l)
        singles && singles.each{|s| wl.sub!(/ #{s} /, " #{s}=0 ")}
        if pairs
          wl.sub!(/ *= */, '=')
#          pairs.each_pair{|k, v|
#            wl.sub!("#{k}=#{v}", "#{k}={#{v}}") unless numeric? v
#          }
        end
	spice_model << wl.sub('parameters', '.param').sub('PARAMETERS', '.PARAM')
      elsif wl =~ /^ *inline +subckt +(\S+)/
        subckt_name = $1
        spice_model << wl.sub(/^ *inline +subckt/, '.subckt').sub(/^ *INLINE +SUBCKT/, '.SUBCKT')
      elsif wl =~ /^ *subckt +/ || wl =~ /^ *parameters +/ || wl =~ /^ *include +/
        spice_model << wl.sub(/^ */,'.')
      elsif wl =~ /^ *ends/ || wl =~ /^ *ENDS/ 
        spice_model << wl.sub(/^ */,'.')
      else
        spice_model << wl
      end
    }
    puts "binnumber = #{binnumber}" if binnumber.to_i > 0
    if binnumber.to_i == 1
      spice_model.sub! ".model #{model_name}.#{binnumber}", ".model #{model_name}" 
    end
    return spice_model unless subckt_name
    new_model = ''
    unwrapped, breaks = unwrap spice_model
    count = -1
    unwrapped.each_line{|l|
      count = count + 1
      wl = wrap(l, breaks[count])
#puts wl
      if l =~ /(^ *)(\S+) (\([^\)]*\)) +#{model_name} +(.*)$/
        parms, = parse_parameters $4
#        wl.sub! $2, MODEL_TYPE_TO_SYMBOL[model_type]+$2
        unless MODEL_TYPE_TO_SYMBOL[model_type].nil?
          wl.sub! $2, MODEL_TYPE_TO_SYMBOL[model_type]+$2  ### what was this for??? for LPNP???
        end
        wl.sub!(/ *= */, '=')
        parms.each_pair{|k, v|
          if k == 'region'
            wl.sub!("#{k}=#{v}", '')
          else
            wl.sub!("#{k}=#{v}", "#{k}={#{v}}") unless numeric?(v)
          end
        }
      end
      new_model << wl
    }
    new_model
  end
end

class SPICE_to_Spectre
  def convert_model_library description
    return description
  end

  def convert_netlist netlist, param_vals=nil
    if netlist && netlist.strip != ''
      "simulator lang=spice\n" + netlist.gsub('{','').gsub('}','')
    end
  end

  def convert_postprocess postprocess
    return nil
  end
          
  def convert_control control
    if control
      spice_control = ''
      spectre_control = ''
      control.each_line{|l|
        if l =~ / *\.tran +(\S+) *\r*$/
          spectre_control << "timeSweep tran stop=#{$1}\n"
        elsif l =~ / *\.ac +(\S+) +(\S+) +(\S+) +(\S+) *\r*$/
          spectre_control << "frequencySweep ac start=#{$3} stop=#{$4} #{$1}=#{$2} annotate=status\n"
        elsif l =~ / *\.dc +(\S+) +(\S+) +(\S+) +(\S+) *\r*$/
          spectre_control << "dcSweep dc dev=#{$1} start=#{$2} stop=#{$3} step=#{$4}\n"
        else
          spice_control << l
        end
      }
      result = spice_control
      result << "simulator lang=spectre\n"
      result << spectre_control
      result << "saveOptions options save=allpub currents=all\n"
      result << "dcOp dc write=\"spectre.dc\" maxiters=150 maxsteps=10000 annotate=status\n" # if control.downcase =~ /^ *\.op *\r*$/
      result
    end
  end
end

class SPICE_to_QUCS < Converter
  def initialize
    require 'qucs'
  end

  def convert_model_library description
    puts "*** convert_model_library called; description=#{description}"
    return description
  end

  def convert_model description
    unwrapped, breaks = unwrap description.upcase
    unwrapped.each_line{|l|
      if l =~ /^ *\.*MODEL +(\w+) +(\w+) +(.*$)/ || l =~ /^ *\.*MODEL +(\w+) +(\w+) *\((.*)\) *$/
        model_name = $1
        model_type = $2
        puts "*** spice_to_QUCS for model: #{model_name} type: #{model_type} ***"
        parms, = parse_parameters $3.gsub(/[\(\)]/,'')
        #        puts "parms=#{parms.inspect} for l=#{l}"
        model = ".Def:#{model_name} "
        case model_type
        when 'D'
        when 'NPN', 'PNP'
          model << "_net1 _net2 _net3 Area=\"1\"\n"
          model << "BJT:Q1 _net1 _net2 _net3 gnd Type=#{model_type}" # 4th port (now temporarily gnd should be handled properly)
          parms.delete_if {|p| %w[VCEO ICRATING MFG].include? p}
          parms = add_defaults parms, 'BJT', model_type, 'capitalize'
        when 'NMOS', 'PMOS'
          model << "_net1 _net2 _net3 L=\"1\" W=\"1\" PS=\"0\" PD=\"0\" AS=\"0\" AD=\"0\" NRS=\"0\" NRD=\"0\"\n"
          p = model_type[0].downcase
          model << "bsim3v34#{p}MOS:BSIM3_1 _net1 _net2 _net3 _net4 L={L} W={W} PS={PS} PD={PD} AS={AS} AD={AD} NRS={NRS} NRD={NRD} Type=#{model_type} "
          parms = add_defaults parms, 'BSIM3V3', model_type, 'upcase'
        end
        parms.each_pair{|p, v|
          model << " #{p}=#{v.downcase}"
        }
        model << "\n.Def:End\n"
        return model
      end
    }
  end

  def add_defaults parms, name, type, case_
    defaults = QucsModel.new(name, type).get_defaults
    parms.each_pair{|p, v|
      pcap = p.send case_ 
      defaults[pcap] = v
    }
    defaults
  end
  private :add_defaults

  def eng_qucs val, multiplier=nil
    if val ### && @param # && @param.include?(val)
      unless numeric?(val)  
        if multiplier == -1
          return "#{convert_to_if val}/m"
        elsif multiplier
          return "#{convert_to_if val}*m" 
        else
          return "#{convert_to_if val}" 
        end
      end
      return val
    end
    '' # changed from nil
  end

  def rest_parms_qucs line, subckt_for_model=nil, valid_params=nil
    return line if line == ''
    puts "line: #{line.downcase}"
    l = line.dup
    l.gsub!(/ *= */, '=')
    p, = parse_parameters l
    flag = subckt_for_model
    p.each_pair{|k, v|
      if valid_params
        if n = valid_params[k.downcase]
          l.sub!("#{k}=#{v}", "#{n}=\"#{eng_qucs(v)}\"")
        else
          l.sub!("#{k}=#{v}", '')
          puts "warning: '#{k}' has been removed because it is not a valid instance parameter"
        end
      end
      if subckt_for_model &&  k == 'm'
        l.sub!("#{k}=#{v}", "#{k.upcase}=\"#{eng_qucs(v, true)}\"")
        flag = nil
      else
        l.sub!("#{k}=#{v}", "#{k.upcase}=\"#{eng_qucs(v)}\"")
      end
    }
    l << ' M="m"' if flag
    l
  end

  def parse_src_qucs desc
    result = ''
    if desc=~/(\S+) *AC(=| ) *(\S+)/
      type = 'ac'
      result << "U=\"#{$3.strip}\""
    elsif desc=~/PULSE *(.*)/
      type = 'rect'
      voff, von, tdelay, tr, tf, ton, width, tperiod = $1.split
      result << "U=\"#{eng_qucs(voff)}\" Td=\"#{eng_qucs(tdelay)}\" Tr=\"#{eng_qucs(tr)}\" Tf=\"#{eng_qucs(tf)}\" TH=\"#{eng_qucs(tperiod)}\" TL=\"#{eng2number(tperiod)-eng2number(width)}\""  # NEED to review
    elsif desc=~/PWL \((.*)\)/
      type = 'pwl'
      result << "PWL (#{$1})"
    elsif desc=~/SINE *(.*)/ ### NEED to revise because Qucs does not seem to have a sine source equivalent
      type = 'sine'
      voffset, vamp, freq, td, theta, phi = $1.split
      result << "SINE #{voffset} #{vamp} #{freq} #{td} #{theta} #{phi}".strip
    elsif desc=~/EXP *(.*)/
      type = 'exp'
      v1, v2, td1, tau1, td2, tau2 = $1.split
      rsult << "EXP #{v1} #{v2} #{td1} #{tau1} #{td2} #{tau2}".strip
    elsif desc=~/(.+)/
      type = 'dc'
      result << "U=\"#{$1.strip}\""
    end
    [type, result.gsub(/ +/, ' ')]
  end

  def parse_options_qucs line
    params, = parse_parameters line
    result = ''
#    result << " temp=#{params['temp']}" if params['temp']
#    result << " tnom=#{params['tnom']}" if params['tnom']
    result << " reltol=\"#{params['reltol']}\"" if params['reltol']
    result << " vntol=\"#{params['vabstol']}\"" if params['vabstol']
    result << " abstol=\"#{params['iabstol']}\"" if params['iabstol']
#    result << " gmin=#{params['gmin']}" if params['gmin']
    result
  end

  def parse_dc_sweep_qucs line
    p = parse line
    if step = p['step']
      points = (eng2number(p['stop']) - eng2number(p['start']))/p['step'].to_f+1
    else
      points = 101
    end
    "Sim=\"DC\" Type=\"lin\" Start=\"#{p['start']}\" Stop=\"#{p['stop']}\" Points=\"#{points}\""
  end

  def parse_ac_sweep_qucs line
    p = parse line
    result = ''
    if p['step']
      points = (eng2number(p['stop']) - eng2number(p['start']))/p['step'].to_f+1
      result << "Type=\"lin\" Points=\"#{points}\"" 
    elsif p['dec']
      points = (Math::log10(eng2number(p['stop'])/eng2number(p['start']))*p['dec'].to_i).to_i+1
      result << "Type=\"log\" Points=\"#{points}\"" 
    elsif p['oct']
      points = (Math::log(eng2number(p['stop']))/Math::log(eng2number(p['start']))).to_i*p['oct'].to_i+1
      result << "Type=\"log\" Points=\"#{points}\"" 
    end
    result << " Start=\"#{eng_qucs p['start']}\" Stop=\"#{eng_qucs p['stop']}\""
  end

  private :eng_qucs, :rest_parms_qucs, :parse_src_qucs, :parse_options_qucs, :parse_dc_sweep_qucs, :parse_ac_sweep_qucs

  @@VALID_PARAMETERS = {
    'MOSFET' => {'m' => 'M',
      'l' => 'L' , 'w' => 'W', 'ad' => 'AD', 'as' => 'AS' ,
      'pd' => 'PD', 'ps' => 'PS', 'nrd' => 'NRD', 'nrs' => 'NRS'},
    'BJT' =>  {'m' => 'Area', 'area'=>'Area'},
    'DIODE' => {'m' => 'Area', 'area'=>'Area'}
  }

  def convert_netlist orig_netlist, param_vals=nil, subckt_for_model=false # converted from class Spectre_to_QUCS
    return nil unless orig_netlist
    new_net = ''
    inside_subckt_flag = nil # avoid to add 'm=1' when .param used outside of subckt
    netlist, breaks = unwrap orig_netlist.downcase
    converted_model = {}
    count = -1
    params_count = 0
    netlist.each_line{|l|
      l.chomp!
      # puts "l:#{l}"
      if l =~ /^model +(\w+) +(\w+)/ # model inside subckt -- not addressed yet
        type = $2
        unless type == 'capacitor' || type == 'resistor'
          new_net << convert_model_sub('.'+l, param_vals) + "\n"
        end
        next
      elsif l =~ /^\.global/ # maybe global is not supported in QUCS yet
        new_net << '# ' + l.sub(' 0 ',' ') + "\n"
      elsif l =~ /^\.parameters/
        params_count = params_count + 1
        pairs, singles = parse_parameters(l)
        @param = pairs.keys
        singles && singles.each{|s| l.sub!(/ #{s} /, " #{s}=0 ")}
        l = subst_values l, l, pairs
        if subckt_for_model && inside_subckt_flag && pairs['m'].nil?
          inside_subckt_flag = nil # to avoid adding m=1 in case of multiple .param statements
          new_net << l.sub('.parameters', ' m="1"') + "\n"  # !!! NOT CONVERTED YET !!!
        else
          new_net << l.sub('.parameters', "Params:param#{params_count}") + "\n"
        end
      elsif l =~ /^\/\// # comment is # in QUCS
        new_net << '#' + l[2..-1] + "\n"
      elsif l =~ /(^ *)(\.subckt) +(\S+)/
        new_net << '.' + l.sub(/#{$2} +#{$3}/, "Def:#{$3.upcase}") + "\n"
        inside_subckt_flag = true 
      elsif l =~ /^\.ends/
        new_net << ".Def:End\n"
      elsif l=~ /(^ *)(d\S*) (\S+ +\S+) +(\S+) +(.*)$/
        new_net << new_wrap("#{$1}Sub:#{$2} #{conv_gnd $3} Type=\"#{$4.upcase}\" #{rest_parms_qucs $5, nil, @@VALID_PARAMETERS['DIODE']}\n")
      elsif l=~ /(^ *)(q\S*) (\S+ +\S+ +\S+) +(\S+) +(.*)$/
        new_net << new_wrap("#{$1}Sub:#{$2} #{conv_gnd $3} Type=\"#{$4.upcase}\" #{rest_parms_qucs $5, nil, @@VALID_PARAMETERS['BJT']}\n")
=begin
        parms, = parse_parameters $5
        l.sub!(/ *= */, '=')
        parms.each_pair{|k, v|
            l.sub!("#{k}=#{v}", "#{k}=\"#{eng_qucs(v)}\"")
        }
        if subckt_for_model # need to check!!!
          if parms['area']
            l.sub! "area=#{parms['area']}", "area={#{parms['area']}*m}"
            l.sub! "area={#{parms['area']}}", "area={#{parms['area']}*m}"
          else
            l.sub! /#{$5}/, "area={m} #{$5}"
          end
        end
=end
      elsif l=~ /(^ *)(m\S*) (\S+ +\S+ +\S+ +\S+) +(\S+) +(.*)$/
        new_net << new_wrap("#{$1}Sub:#{$2} #{conv_gnd $3} Type=\"#{$4.upcase}\" #{rest_parms_qucs $5, nil, @@VALID_PARAMETERS['MOSFET']}\n")
=begin
        name = $2
        model = $4 
        parms, = parse_parameters $5
        l.sub!(/ *= */, '=')
        parms.each_pair{|k, v|
          if @@VALID_MOSFET_PARAMETERS.include? k.downcase
            l.sub!("#{k}=#{v}", "#{k}=\"#{eng_qucs(v)}\"")
          else
            l.sub!("#{k}=#{v}", '')
            puts "warning: '#{k}' has been removed because it is not a valid MOSFET instance parameter"
          end
        }
        if subckt_for_model # --- not implemented yet
          if parms['m']
            l.sub! "m=#{parms['area']}", 'm={m}'
          else
            l.sub! " #{model} ", " #{model} m={m} "
          end
        end
        l.sub!(/region *= *\S+/, '')
        l.sub!(name, "M#{name}") unless name.start_with?('M')||name.start_with?('m')
        new_net << 'Sub:' + new_wrap(l + "\n")
=end
      elsif l=~ /(^ *)(\S*) +(\S+ +\S+) +relay +(.*) */ # TO BE coded
        parms, = parse_parameters $4
        new_net << new_wrap("#{$1}#{prefix($2,'s')} #{conv_gnd $3} #{$2}\n")
        new_net << new_wrap(".model #{$2} SW roff=#{eng_qucs(parms['ropen'])} ron=#{eng_qucs(parms['rclosed'])}")
        new_net << new_wrap(" vt={(#{parms['vt1']}+#{parms['vt2']})/2} vh={(#{parms['vt1']}-#{parms['vt2']})/2}\n")
      elsif l=~ /(^ *)(v\S+) +(\S+ +\S+) +(.*) */ 
        src_type, src_parameters = parse_src_qucs $4
        new_net << new_wrap("#{$1}V#{src_type}:#{$2} #{conv_gnd $3} #{src_parameters}\n")
      elsif l=~ /(^ *)(i\S+) +(\S+ +\S+) +(.*) */ 
        new_net << new_wrap("#{$1}I#{src_type}:#{$2} #{conv_gnd $3} #{src_parameters}\n")
      elsif l=~ /(^ *)(r\S+) +(\S+ +\S+) +(.*) */ 
        new_net << new_wrap("#{$1}R:#{$2} #{conv_gnd $3} R=#{$4.gsub(/[{}]/,'')}\n")
      elsif l=~ /(^ *)(c\S+) +(\S+ +\S+) +(.*) */ 
        new_net << new_wrap("#{$1}C:#{$2} #{conv_gnd $3} C=#{$4.gsub(/[{}]/,'')}\n")
      elsif l=~ /(^ *)(e\S+) +\((.*)\) +vcvs +(.*) */ # TO BE coded
        parms, = parse_parameters $4
        new_line = "#{$1}VCVS:E#{$2} #{conv_gnd $3} "
        if parms['min'] && parms['max'] # --- table may not be supported in qucs 
          new_line << "table=({#{eng(parms['min'])}/#{eng(parms['gain'])}}, {#{eng(parms['min'])}}, "
          new_line << "{#{eng(parms['max'])}/#{eng(parms['gain'])}}, {#{eng(parms['max'])}})\n"
        else
          new_line << "G=\"#{eng(parms['gain'])}\"\n"
        end
        new_net << new_wrap(new_line)
      elsif l=~ /(^ *)(\S+) +\((.*)\) +vccs +gm *= *(\S+) */ # TO BE coded
        new_net << "#{$1}VCCS:G#{$2} #{conv_gnd $3} GM=\"#{eng_qucs $4}\n\"" # --- need to check
      elsif l=~ /(^ *)(\S+) +\((.*)\) +cccs +gain *= *(\S+) +probe *= *(\S+) */ # TO BE coded
        new_net << "#{$1}CCCS:F#{$2} #{conv_gnd $4} G=\"#{eng_qucs $3}\"\n" # --- need to check
      elsif l=~ /(^ *)(\S+) +\((.*)\) +ccvs +rm *= *(\S+) +probe *= *(\S+) */ # TO BE coded
        new_net << "#{$1}CCVS:H#{$2} #{conv_gnd $4} RM=\"#{eng_qucs $3}\"\n" # --- need to check
      elsif l =~ /(^ *)(x\w*) +([^=]*) +(\S+) *$/
        new_net << new_wrap("#{$1}Sub:#{$2} #{conv_gnd $3} Type=\"#{$4.upcase}\"\n")
      elsif l =~ /(^ *)(x\w*) +([^=]*) +(\S+) +(\w+ *= *.*$)/
        new_net << new_wrap("#{$1}Sub:#{$2} #{conv_gnd $3} Type=\"#{$4.upcase}\" #{rest_parms_qucs $5, subckt_for_model}\n")
      elsif l=~ /(^ *)(\S+) +\((.*)\) +(\S+) +l *= *(\S+) *(.*) */
        if $4 == 'inductor'
          new_net << new_wrap("#{$1}L:#{prefix($2,'l')} #{conv_gnd $3} L=\"#{eng_qucs $5}\" #{rest_parms_qucs $6}\n")
        else  # not always inductor: eg. "r12 (n3 n4) rsilpp1 l=2.200e-07 w=w"
          new_net << new_wrap("#{$1}X#{$2} #{conv_gnd $3} #{$4} l=\"#{eng_qucs $5}\" #{rest_parms_qucs $6, subckt_for_model}\n")
        end
      elsif l=~ /(^ *)(\S+) +\(((.*))\) +(\S+) +([cq]) *= *(\S+) *(.*) */ # TO BE coded
        ctype = $6.downcase
        if $5 == 'bsource'
          n1, n2 = $4.strip.split
          new_net << "#{$1}#{$2} #{conv_gnd n1} #{conv_gnd n2} "
          body = "#{$7} #{$8}".gsub(/v\(#{n1}\) *- *v\(#{n2}\)/, 'x')
          if ctype == 'c'
            new_net << "Q=(#{body}*(x)) m={m}\n"
          elsif ctype == 'q'
            new_net << "Q=#{body} m={m}\n"
          end
        elsif $5 == 'capacitor'
          if subckt_for_model
#            new_net << new_wrap("#{$1}#{prefix($2,'c')} #{$3} #{eng_qucs $7, true} #{rest_parms_qucs $8}\n") # this does not work when $7 is not sliced correctly
            new_net << new_wrap("#{$1}C:#{prefix($2,'c')} #{conv_gnd $3} C=\"#{eng_qucs $7+' '+$8}\" m={m}\n") # quick fix!
          else
            new_net << new_wrap("#{$1}C:#{prefix($2,'c')} #{conv_gnd $3} C=\"#{eng_qucs $7}\" #{rest_parms_qucs $8}\n")
          end
        else
          if subckt_for_model
            new_net << new_wrap("#{$1}Sub:#{$2} #{conv_gnd $3} Type=\"#{$4.upcase}\" C=\"#{eng_qucs $7}\" #{rest_parms_qucs $8} m={m}\n")
          else
            new_net << new_wrap("#{$1}Sub:#{$2} #{conv_gnd $3} Type=\"#{$4.upcase}\" C=\"#{eng_qucs $7}\" #{rest_parms_qucs $8}\n")
          end
        end
      elsif l=~ /(^ *)(\S+) +\(((.*))\) +(\S+) +r *= *(\S+) *(.*) */# TO BE coded
        if $5 == 'bsource'
          n1, n2 = $4.strip.split
#          new_net << "#{$1}b#{$2} #{$3} i={v(#{n1},#{n2})/(#{$6} #{$7})}\n"
          new_net << new_wrap("#{$1}b#{$2} #{conv_gnd n1} #{conv_gnd n2} i={(v(#{n1},#{n2})/(#{$6} #{$7}))*m}\n")
        else
          if $5 == 'resistor'
            if subckt_for_model
              new_line = "#{$1}R:#{prefix($2,'r')} #{conv_gnd $3} R=\"#{eng_qucs $6, -1}\" "
            else
              new_line = "#{$1}R:#{prefix($2,'r')} #{conv_gnd $3} R=\"#{eng_qucs $6}\" "
            end
          else
            if subckt_for_model
              new_line = "#{$1}Sub:#{$2} #{conv_gnd $4} Type=\"#{$5.upcase}\" R=\"#{eng_qucs $6, true}\""
            else
              new_line = "#{$1}Sub:#{$2} #{conv_gnd $4} Type=\"#{$5.upcase}\" R=\"#{eng_qucs $6}\""
            end
          end
          rest = $7? $7.sub(/isnoisy *= \S+/, ''):nil
          new_net << new_wrap(new_line + "#{rest_parms_qucs rest}\n")
        end
      elsif l =~ /(^ *)([rcl]\S*) +\(([^\)]*)\) +(\S+) +(.*)$/
        new_net << new_wrap("#{$1}X#{$2} #{conv_gnd $3} #{$4} #{rest_parms_qucs $5, subckt_for_model}\n")
      elsif l =~ /(^ *)([rcl]\S*) +\(([^\)]*)\) +(\S+) *$/ # TO BE coded
        if converted_model[$4] # model is capacitor or resistor
          space, name, net, model = [$1, $2, $3, $4] 
          if prefix = converted_model[model]['prefix'] 
            new_net << converted_model[model]['params'] 
            vsrc = 'v' + net.gsub(/ +/, ',')
            value = converted_model[model]['value'].gsub('#{vsrc}', vsrc) 
            new_net << new_wrap("#{space}#{prefix}#{name} #{conv_gnd net} #{value}\n")
          else
            new_net << converted_model[model]['params'] 
            value = converted_model[model]['value'] 
            new_net << new_wrap("#{space}#{name} #{conv_gnd net} #{value}\n")
          end
        else
          new_net << new_wrap("#{$1}Sub:#{$2} #{conv_gnd $3} Type=\"#{$4.upcase}\"\n")
        end
      else
        new_net << new_wrap(l+"\n")
      end
    }
    new_net
  end

  def conv_gnd nets
    nets.split.map{|a| a == '0' ? 'gnd' : a}.join(' ')
  end

  def prefix s, p
    (s.start_with?(p) || s.start_with?(p.upcase))? s : p.upcase+s
  end

  def convert_postprocess postprocess
    return nil
  end
          
  def convert_control control
    if control
      qucs_control = ''
      control.each_line{|l|
        if l =~ / *\.tran +(\S+) *\r*$/
          qucs_control << ".TR:TR1 Type=\"lin\" Start=\"0\" Stop=\"#{$1}\" Points=\"101\" IntegrationMethod=\"Trapezoidal\" Order=\"2\" InitialStep=\"1 ns\" MinStep=\"1e-16\" MaxIter=\"150\" reltol=\"0.001\" abstol=\"1 pA\" vntol=\"1 uV\" Temp=\"26.85\" LTEreltol=\"1e-3\" LTEabstol=\"1e-6\" LTEfactor=\"1\" Solver=\"CroutLU\" relaxTSR=\"no\" initialDC=\"yes\" MaxStep=\"0\"\n"
        elsif l =~ / *\.ac +(\S+) +(\S+) +(\S+) +(\S+) *\r*$/
          # spectre_control << "frequencySweep ac start=#{$3} stop=#{$4} #{$1}=#{$2} annotate=status\n"
        elsif l =~ / *\.dc +(\S+) +(\S+) +(\S+) +(\S+) *\r*$/
          # spectre_control << "dcSweep dc dev=#{$1} start=#{$2} stop=#{$3} step=#{$4}\n"
          qucs_control << ".DC:DC1 Temp=\"26.85\" reltol=\"0.001\" abstol=\"1 pA\" vntol=\"1 uV\" saveOPs=\"no\" MaxIter=\"150\" saveAll=\"no\" convHelper=\"none\" Solver=\"CroutLU\"\n"
          qucs_control << ".SW:SW1 Sim=\"DC1\" Type=\"lin\" Param=\"Uce\" Start=\"#{$2}\" Stop=\"#{$3}\" Points=\"#{(($3.to_f-$2.to_f)/$4.to_f).to_i}\"\n"
        else
        end
      }
      qucs_control
    end
  end
end

def parse_model description, name=nil
  if name
    parse_model0 extract_model(name, description)
  else
    parse_model0 description
  end
end

def extract_model name, description
  # puts "extract model for #{name} description.size=#{description.size}"
  model = nil
  description.each_line{|l|
    if l.downcase =~ /\.model +(\S+)/
      if $1.downcase == name.downcase
        model = l
      elsif model
        return model
      end
    elsif model
      model << l
    end
  }
  return model
end
  
def parse_model0 description
  params = {}
  return params unless description
#  return params unless a.include?('.model')||a.include?('.param')

  if description =~ /\.(param|PARAM)/
    if description =~ /\.(model|MODEL)/
      a = ''
      flag = nil
      description.each_line{|l|
        if flag || (l =~ /^ *\.(model|MODEL)/)  # ignore .param description in front of .model
          flag = true
          a << l
        end
      }
    else
      a = description.dup
    end
  else  # what is this case? model having .param only?
    a = description.dup.chomp
  end
  return params unless a =~ /\.(model|param|MODEL|PARAM)/
  a.gsub!(/^[\*#].*\n/,'') # remove comment lines
  a.gsub!(/\t/,'')      # remove tabs
  if a =~ /^.*\.(model|MODEL) +\S+ +\S+ *\(/ # remove the unnecessary '('
    a.sub! /\)[^\)]*$/, "\n"           # remove the matching ') at the end'
    a.gsub!(/^.*\.(model|MODEL) +(\S+) +(\S+) *\(/,' ')
  else
    a.gsub!(/^.*\.(model|MODEL) +(\S+) +(\S+) */,' ')  # ' ' should not be '' otherwise \ntype appears
  end
  name = $2
  type = $3
#  a.gsub(/\n *\+/,' ').scan(/([^ =]+) *= *(\'[^\']*\'|\S+)/).each{|pair|
#    params[pair[0]] = pair[1]
#  }
  params, = parse_parameters a.gsub(/\n *\+/,' ')
#if @debug == nil
#  debugger
#end
=begin  
  if type == 'bjt'
    type = params['type']
  end
  if type == 'pnp'
    if params['struct'] 
      type = 'vpnp' if params['struct'] == 'vertical'
      type = 'lpnp' if params['struct'] == 'lateral'
    elsif params['subs']
      type = 'lpnp' if params['subs'].to_i == -1
      type = 'vpnp' if params['subs'].to_i == 1
    end
  end
=end
  return [type, name, params]
end
private :parse_model0

class Spice
  def comment_char
    '*'
  end

  def read_spice_net file, raise_error_if_missing=true
    unless File.exist? file
      raise "#{file} does not exist!" if raise_error_if_missing
      return {} 
    end
    begin
      read_spice_net_core File.open(file, 'r:Windows-1252').read.encode('UTF-8', invalid: :replace).gsub('µ', 'u')
    rescue
      read_spice_net_core File.read(file).gsub('µ', 'u')
    end
  end
  
  def read_spice_net_core netlist
    result = {}
    result[:main] = ''
    result[:subckt] = {}
    result[:control] = ''
    subckt = nil
    old_subckt = nil
    comments = ''

    unwrapped, breaks = unwrap netlist, false # do not ignore comment lines
    count = -1
    unwrapped.each_line{|l|
      count = count + 1
      wl = wrap(l, breaks[count])
      if subckt
        result[:subckt][subckt] << wl
        if l =~ /^ *\.*(ends|ENDS)/
          old_subckt = subckt 
          subckt = nil
        end
      elsif l =~ /^ *\.*(subckt|SUBCKT) +(\S+)/
        subckt = $2.downcase
        result[:subckt][subckt] = comments + wl
        comments = ''
      elsif l =~ /^ *\.*(end|END)/
        result[:control] << '* ' + wl
      elsif l =~ /^ *\.(lib|LIB)/
        result[:control] << '* ' + wl
      elsif l =~ /simulator lang=/ # just ignore
        next
      elsif l =~ /^ *\./ || l.downcase =~ /^ *(include|global|nodeset|simulatorOptions|tran|dc|ac|noise|saveOptions|parameters)/ || l =~ /^ *(\w+) +info +what=/ || l =~ /^ *\S+Options +options/
        result[:control] << wl
        if comments != ''
          result[:control] = comments + result[:control]
          comments = ''
        end
      elsif l =~ /^ *\*/ || l =~ /^ *\/\//# skip comments
        comments << wl
      elsif l.strip == '' && old_subckt
        if comments != ''
          result[:subckt][old_subckt] = result[:subckt][old_subckt] + comments
          comments =''
        end
      else
        result[:main] << wl
        if comments != ''
          result[:main] = comments + result[:main]
          comments = ''
        end
      end
    }
    result[:main] = comments + result[:main] if comments != ''
    result
  end

  def parse_control orig_control
    return nil unless orig_control
    analysis = {}

    control, breaks = unwrap orig_control.downcase
    control.each_line{|l|      
      l.chomp!
      if l =~ /^ *\.dc /
        analysis['dc'] = nil
      elsif l =~ /^ *\.ac /
        analysis['ac'] = nil
      elsif l =~ /^ *\.tran /
        analysis['tran'] = nil
      elsif l =~ /^ *\.noise /
        analysis['noise'] = nil
      elsif l =~/^ *options/
#        opts = parse_options $1
        analysis['options'] = nil
      elsif l =~ /^ *\.op/
        analysis['op'] = nil
      end
    }
    return analysis
  end

  def parse_netlist orig_netlist, cell_map={}
    return nil
  end

  def use_section_in_model_library?
    true
  end

  def convert_section description
    result = ''
    description.each_line{|l|
      l.sub!(/^ *parameters/, '.parameter')
      l.sub!(/^ *\/\//, '*')
      result << l
    }
    result
  end

  def convert_library lib_description, description
    if /^library/ =~ lib_description
      lib_description.sub!(/endlibrary.*$/,'')
      description << "endlibrary\n"
    end
    lib_description + description
  end
end

def Spice.subckt_reference? line 
  return $1 if /^ *[xX].* ([^ ]+) *$/ =~ line.chomp
end

class SPICE_add_Mult < Converter
  def convert_netlist orig_netlist, res_conv=true, cap_conv=true, res_exception=nil, cap_exception=nil
    return nil unless orig_netlist
    res_exception ||=[]
    cap_exception ||=[]
#debugger
    new_net = ''
#prof=RubyProf::profiler {
#      result = RubyProf.profile do
    netlist, breaks = unwrap orig_netlist    # continuation w/ '+' unwrapped    
#      end
#      printer = RubyProf::FlatPrinter.new(result)
#      strio = StringIO.new
#      printer.print(strio)
#      puts strio.string
#}
#debugger
#puts "unwrap ony", prof_result

#    netlist.gsub(/\\\r*\n/, '').each_line{|l|
    netlist.each_line{|l|
      l.chomp!
      if cap_conv &&
          l=~ /(^ *)([Cc]\S*) +\(*(\S+) +(\S+)\)* +(\S+) *(.*) */ && 
          !(cap_exception.include? $2)
#        new_net << "#{$1}#{$2} #{$3} #{add_mult '@cap_mult', $4} #{$5} #{$6}\n"
        new_net << "#{$1}#{$2} #{$3} #{$4} #{add_mult '@cap_mult', $5} #{$6}\n"
        next
      elsif res_conv && 
          l=~ /(^ *)([Rr]\S*) +\(*(\S+) +(\S+)\)* +(\S+) *(.*) */ &&
          !(res_exception.include? $2)
        new_net << "#{$1}#{$2} #{$3} #{$4} #{add_mult '@res_mult', $5} #{$6}\n"
        next
      end
      new_net << l + "\n"
    }
    new_net
  end
  def convert_model description, param_vals=nil
  end
  def convert_postprocess postprocess
  end
  def convert_control orig_control
  end
  private
  def add_mult pname, val
    val = val.strip
    if val[0..0] == '('
      return "(\#{#{pname}}*#{val[1..-2]})"   # strip '(' & ')'
    else
      return "(\#{#{pname}}*#{val})"
    end
  end
end

