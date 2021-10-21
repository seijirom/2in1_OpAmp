# Copyright(C) 2009-2020 Anagix Corporation
if $0 == __FILE__
  $:<< File.dirname(__FILE__) 
  require 'spice_parser'
end
require 'complex'
require 'fileutils'
# require 'ruby-debug'
require 'timeout'

if RUBY_PLATFORM=~/mswin32|mingw|cygwin/ && !defined?(:GetShortPathName)
  require 'Win32API'
  GetShortPathName = Win32API.new('kernel32','GetShortPathName','ppi','i')
  def get_short_path_name(long_name)
    return long_name if RUBY_VERSION == '1.8.7'
    unless File.exist? long_name
      winpath = long_name + '.exe'
      if File.exist? winpath
        long_name = winpath
      else
        return long_name
      end
    end
    len = GetShortPathName.call(long_name, nil, 0)
    raise "File not found: #{long_name}" if len.zero?
    short_name = "\0" * len
    GetShortPathName.call(long_name, short_name, len)
    short_name.gsub!(/\0/, '') # avoid string contains null byte error
    short_name.tr!('/', '\\')
    #    puts "Windows #{RUBY_VERSION}: #{long_name} => #{short_name}"
    return short_name
  end
end

class Xyce < Spice
#  include SpiceParser
  def update_control line, props, lang # lang is not used
# line is like ".ac dec 10 10K 100G\r\n"
# props is {"dec"=>"10", "stop"=>"100g", "start"=>"\#{@freqstart}"}
# APPARENTLY THIS update is not implemented!!!
    props.each_pair{|k, v|
      line.sub!(/ +#{k} *= *\S+/, " #{k}=#{v}")
      line.sub!(/ +#{k} *= *\{\S+\}/, " #{k}={#{v}}")
    }
    line
  end

  def update_element line, props, lang  # lang is not used 
    if line =~ /^ *(V\w* +\S+ +\S+ +)(.*)/ || line =~ /^ *(I\w* +\S+ +\S+ +)(.*)/
      head=$1
      tail=$2
      line.sub!("#{head}#{tail}", "#{head}#{replace_src(tail, props)}")
    else
      props.each_pair{|k, v|
        next if k == 'model' # just ignore
        if (line =~ /^ *(C\w* +\S+ +\S+ +)(\S+)/ && k=='c') ||
            (line =~ /^ *(R\w* +\S+ +\S+ +)(\S+)/ && k=='r')
          line.sub!("#{$1}#{$2}", "#{$1}#{v}")
        else
          unless line.sub!(/ +#{k} *= *\S+/, " #{k}=#{v}") || line.sub!(/ +#{k} *= *\{\S+\}/, " #{k}={#{v}}")
            line << " #{k}={#{v}}"
          end
        end
      }
    end
    line
  end

  def replace_src desc, props
    if desc=~/(\S+) *AC(=| ) *(\S+)/
      return " #{props['dc']} AC=#{props['mag']||$3}"
    elsif desc=~/PULSE *(.*)/
      voff, von, tdelay, tr, tf, ton, tperiod, ncycles = $1.split
      return "PULSE #{props['val0']||voff} #{props['val1']||von} #{props['delay']||tdelay} #{props['rise']||tr} #{props['fall']||tf} #{props['width']||ton} #{props['period']||tperiod} #{ncycles}".strip
    elsif desc=~/PWL \((.*)\)/
      result << "PWL (#{props['wave']}||$1)"
    elsif desc=~/SINE *(.*)/
      voffset, vamp, freq, td, theta, phi, ncycles = $1.split
      return "SINE #{props['sinedc']||voffset} #{props['ampl']||vamp} #{props['freq']||freq} #{props['delay']||td} #{props['damp']||theta} #{props['sinephase']||phi} #{ncycles}".strip
    elsif desc=~/EXP *(.*)/
      v1, v2, td1, tau1, td2, tau2 = $1.split
      return "EXP #{props['val0']||v1} #{props['val1']||v2} #{props['td1']||td1} #{props['tau1']||tau1} #{props['td2']||td2} #{props['tau2']||tau2}".strip
    elsif desc=~/(.+)/
      return " #{props['dc'] ||$1}".strip
    end
  end

  def parse_control orig_control
    return nil unless orig_control
    analysis = {}

    control, breaks = unwrap orig_control.downcase
    count = 0
    control.each_line{|l|      
      count = count + 1
      l.chomp!
      if l =~ /^ *\.(dc|DC) +(\S+) *(.*)/
        analysis['dc'] ||= {}
        analysis['dc'][$2] = {}
        start, stop, step = ($3 && $3.split.map{|a| remove_curly_brackets a})
        analysis['dc'][$2]['start'] = start if start
        analysis['dc'][$2]['stop'] = stop if stop
        analysis['dc'][$2]['step'] = step if step
      elsif l =~ /^ *\.(ac|AC) +(oct|OCT) +(\S+) +(\S+) +(\S+)/
        analysis['ac'] ||= {}
        analysis['ac']['freq'] = {}
        analysis['ac']['freq']['step'] = remove_curly_brackets $3
        analysis['ac']['freq']['start'] = remove_curly_brackets $4
        analysis['ac']['freq']['stop'] = remove_curly_brackets $5
      elsif l =~ /^ *\.(ac|AC) +(dec|DEC) +(\S+) +(\S+) +(\S+)/
        analysis['ac'] ||= {}
        analysis['ac']['freq'] = {}
        analysis['ac']['freq']['dec'] = remove_curly_brackets $3
        analysis['ac']['freq']['start'] = remove_curly_brackets $4
        analysis['ac']['freq']['stop'] = remove_curly_brackets $5
      elsif l =~ /^ *\.(ac|AC) +(lin|LIN) +(\S+) +(\S+) +(\S+)/
        analysis['ac'] ||= {}
        analysis['ac']['freq'] = {}
        analysis['ac']['freq']['lin'] = remove_curly_brackets $3
        analysis['ac']['freq']['start'] = remove_curly_brackets $4
        analysis['ac']['freq']['stop'] = remove_curly_brackets $5
      elsif l =~ /^ *\.(tran|TRAN) +(\S+) +(\S+) +(.*)+ /
        outputstart, maxstep = ($4 && $4.split.map{|a| remove_curly_brackets a})
        analysis['tran'] ||= {}
        analysis['tran']['time'] = {}
        analysis['tran']['time'] = {'step' => remove_curly_brackets($2), 'stop' => remove_curly_brackets($3)}
        analysis['tran']['time']['outputstart'] = outputstart if outputstart
        analysis['tran']['time']['maxstep'] = maxstep if maxstep
      elsif l =~ /^ *\.(tran|TRAN) +(\S+) +(\S+)/
        analysis['tran'] ||= {}
        analysis['tran']['time'] = {}
        if $3 == 'UIC'
          analysis['tran']['time']['stop'] = remove_curly_brackets $2
        else
          analysis['tran']['time'] = {'step' => remove_curly_brackets($2), 'stop' => remove_curly_brackets($3)}
        end
      elsif l =~ /^ *\.(tran|TRAN) +(\S+)/
        analysis['tran'] ||= {}
        analysis['tran']['time'] = {'stop' => remove_curly_brackets($2)}
      elsif l =~ /^ *\.(noise|NOISE) +[Vv]\(.*\) +(\S+) +(oct|OCT) +(\S+) +(\S+) +(\S+)/
        analysis['noise'] ||= {}
        analysis['noise']['freq'] = {}
        analysis['noise']['freq']['step'] = remove_curly_brackets $4
        analysis['noise']['freq']['start'] = remove_curly_brackets $5
        analysis['noise']['freq']['stop'] = remove_curly_brackets $6
      elsif l =~ /^ *\.(noise|NOISE) +[Vv]\(.*\) +(\S+) +(dec|DEC) +(\S+) +(\S+) +(\S+)/
        analysis['noise'] ||= {}
        analysis['noise']['freq'] = {}
        analysis['noise']['freq']['dec'] = remove_curly_brackets $4
        analysis['noise']['freq']['start'] = remove_curly_brackets $5
        analysis['noise']['freq']['stop'] = remove_curly_brackets $6
      elsif l =~ /^ *\.(noise|NOISE) +[Vv]\(.*\) +(\S+) +(lin|LIN) +(\S+) +(\S+) +(\S+)/
        analysis['noise'] ||= {}
        analysis['noise']['freq'] = {}
        analysis['noise']['freq']['lin'] = remove_curly_brackets $4
        analysis['noise']['freq']['start'] = remove_curly_brackets $5
        analysis['noise']['freq']['stop'] = remove_curly_brackets $6
      elsif l =~/^ *\.(opt|OPT)\S+ +(.*) *$/
#        opts = parse_options $1
        analysis['options'] ||= {}
        analysis['options']["line#{count}"] = {}
        pairs, = parse_parameters($2)
        pairs.each_pair{|k, v|
          analysis['options']["line#{count}"][k] = v
        }
      elsif l =~ /^ *\.(op|OP)/
        analysis['op'] ||= {}
        analysis['op']["line#{count}"] = {}
      end
    }
    return analysis
  end

  def parse_netlist orig_netlist, cell_map={}
    return nil unless orig_netlist
    result = {'ports'=>[], 'global'=>[], 'parameters'=>{},
      'instance'=>{}, 'connection'=>{}
    }
    ELEMENTS.each{|e| result[e] = {}}
    nets = []
    flag = nil  # lang=spice if true
    netlist, breaks = unwrap orig_netlist    # continuation w/ '+' unwrapped    
#    netlist.gsub(/\\\r*\n/, '').each_line{|l|
    netlist.each_line{|l|
      l.chomp!
      next if l.strip == '' || l =~/^ *\./ 
      l << ' '
      if l =~ /^ *([^.]\S+) [^=]* (\w+) *$/  # check if $1 is a subckt instance, $2 is a subckt
        s = $2
#debugger if $1.upcase == 'V3'
        if cell_map[s]
          set_instance l, nets, result 
          next
        elsif (not s.start_with?('{')) and (not cell_map.keys.include?(s))
          flag2 = nil 
          cell_map.keys.each{|c|
            if c=~ /#{s}@.*/
              flag2 = true 
              break
            end
          }
          if flag2
            set_instance l, nets, result 
            next
          end
        end
      end
      if l =~ /^\.param/
        pairs, singles = parse_parameters(l)
        pairs.each_pair{|k, v|
          result['parameters'][k] = v
        }
        singles && singles.each{|s|
          result['parameters'][s] = '0.0'
        }
      elsif l =~ /^\*/
      elsif l =~ /(^ *)\.subckt +(\S+) +(.*$)/ || l =~ /^\.ends +(\S+)/
        result['subckt'] = $2
        result['ports'] = $3.split if $3
      elsif l=~ /^ *([Ll]\S*) +\((.*)\) +(\S+) +(.*) */ ||
          l=~ /^ *([Ll]\S*) +(\S+ \S+) +(\S+) +(.*) */ ||
          l=~ /^ *([Ll]\S*) +\((.*)\) *$/ ||
          l=~ /^ *([Ll]\S*) +(\S+ \S+) *$/
        nets << (n2=$2.split)
        result['inductor'][$1] = {'l' => remove_curly_brackets($3)}
        result['connection'][$1] = {'type'=>'inductor', 'nets'=>n2}
        parms, = parse_parameters $4
        parms.each_pair{|k, v|
          result['inductor'][$1][k] = v
        }
      elsif l=~ /^ *([Xx]*[Cc]\S*) +\((.*)\) +(\S+) +(.*) */ ||
          l=~ /^ *([Xx]*[Cc]\S*) +(\S+ \S+) +(\S+) +(.*) */ ||
          l=~ /^ *([Xx]*[Cc]\S*) +\((.*)\) *$/ ||
          l=~ /^ *([Xx]*[Cc]\S*) +(\S+ \S+) *$/
        nets << (n2=$2.split)
        result['capacitor'][$1] = {'c' => remove_curly_brackets($3)}
        result['connection'][$1] = {'type'=>'capacitor', 'nets'=>n2}
        parms, = parse_parameters $4
        parms.each_pair{|k, v|
          result['capacitor'][$1][k] = v
        }
      elsif l=~ /^ *([Xx]*[Rr]\S*) +\((.*)\) +(\S+) +(.*) */ ||
          l=~ /^ *([Xx]*[Rr]\S*) +(\S+ \S+) +(\S+) +(.*) */ ||
          l=~ /^ *([Xx]*[Rr]\S*) +\((.*)\) *$/ ||
          l=~ /^ *([Xx]*[Rr]\S*) +(\S+ \S+) *$/
        nets << (n2=$2.split)
        result['resistor'][$1] = {'r' => remove_curly_brackets($3)}
        result['connection'][$1] = {'type'=>'resistor', 'nets'=>n2}
        parms, = parse_parameters $4
        parms.each_pair{|k, v|
          result['resistor'][$1][k] = v
        }
      elsif l=~ /^ *([Dd]\S*) +\(([^\)]*)\) +(\S+) +(.*) */ ||
          l=~ /^ *([Dd]\S*) +(\S+ \S+) +(\S+) +(.*) */
        nets << (n2=$2.split)
        result['diode'][$1] = {'model'=>$3}
        result['connection'][$1] = {'type'=>'diode', 'model'=>$3, 'nets'=>n2}
        parms, = parse_parameters $4
        parms.each_pair{|k, v|
          result['diode'][$1][k] = v          
        }
      elsif l=~ /^ *([Qq]\S*) +\(([^\)]*)\) +(\S+) +(.*) */ ||
          l=~ /^ *([Qq]\S*) +(\S+ \S+ \S+) +(\S+) +(.*) */
        nets << (n2=$2.split)
        result['bjt'][$1] = {'model'=>$3}
        result['connection'][$1] = {'type'=>'bjt', 'model'=>$3, 'nets'=>n2}
        parms, = parse_parameters $4
        parms.each_pair{|k, v|
          result['bjt'][$1][k] = v          
        }
      elsif l=~ /^ *([Mm]\S*) +\(([^\)]*)\) +(\S+) +(.*) */ ||
          l=~ /^ *([Mm]\S*) +(\S+ \S+ \S+ \S+) +(\S+) +(.*) */
        nets << (n2=$2.split)
        result['mosfet'][$1] = {'model'=>$3}
        result['connection'][$1] = {'type'=>'mosfet', 'model'=>$3, 'nets'=>n2}
        parms, = parse_parameters $4
        parms.each_pair{|k, v|
          result['mosfet'][$1][k] = v          
        }
      elsif l=~ /^ *([Jj]\S*) +\(([^\)]*)\) +(\S+) +(.*) */ ||
          l=~ /^ *([Jj]\S*) +(\S+ \S+ \S+) +(\S+) +(.*) */
        nets << (n2=$2.split)
        result['jfet'][$1] = {'model'=>$3}
        result['connection'][$1] = {'type'=>'jfet', 'model'=>$3, 'nets'=>n2}
        parms, = parse_parameters $4
        parms.each_pair{|k, v|
          result['jfet'][$1][k] = v          
        }
      elsif l=~ /^ *([VvIi])(\S*) +\((.*)\) +(\S+) (AC|ac) *=* *(\S+) *$/ ||
          l=~ /^ *([VvIi])(\S*) +(\S+ \S+) +(\S+) (AC|ac) *=* *(\S+) *$/
        nets << (n3=$3.split)
        vi = $1.downcase
        result[vi+'source'][$1+$2] = {'type' => 'dc', 'dc' => remove_curly_brackets($4), 'mag' => remove_curly_brackets($6)}
        result['connection'][$1+$2] = {'type'=> vi+'source', 'nets'=>n3}
      elsif l=~ /^ *([VvIi])(\S*) +\((.*)\) +(\S+) +(.*) */ || # V5 inp inm SINE 0 AC 1
          l=~ /^ *([VvIi])(\S*) +(\S+ \S+) +(\S+) +(.*) */ ||
          l=~ /^ *([VvIi])(\S*) +\((.*)\) *$/ ||
          l=~ /^ *([VvIi])(\S*) +(\S+ \S+) *$/
        name = $1+$2
        vi = $1.downcase
        nets << (n3=$3.split)
        type = $4 || ''
        params = $5 && $5.strip
        result[vi+'source'][name] ||= {}
        if params =~ /(.*) (AC|ac) *=* *(\S+) *$/
          params = $1
          result[vi+'source'][name]['mag'] = $3
        end
        result[vi+'source'][name]['type'] = type.downcase
        result['connection'][name] = {'type'=> vi+'source', 'nets'=>n3}
        case type.downcase
        when 'pwl'
          result[vi+'source'][name]['wave'] = params
        when 'pulse'
          val0, val1, delay, rise, fall, width, period = (params && params.split.map{|a| remove_curly_brackets a})
          result[vi+'source'][name]['val0'] = val0 if val0
          result[vi+'source'][name]['val1'] = val1 if val1
          result[vi+'source'][name]['delay'] = delay if delay
          result[vi+'source'][name]['rise'] = rise if rise
          result[vi+'source'][name]['fall'] = fall if fall
          result[vi+'source'][name]['width'] = width if width
          result[vi+'source'][name]['period'] = period  if period
        when 'sine'
          sinedc, ampl, freq, delay, damp, sinephase = (params && params.split.map{|a| remove_curly_brackets a})
          result[vi+'source'][name]['sinedc'] = sinedc if sinedc
          result[vi+'source'][name]['ampl'] = ampl if ampl
          result[vi+'source'][name]['freq'] = freq if freq
          result[vi+'source'][name]['delay'] = delay if delay
          result[vi+'source'][name]['damp'] = damp if damp
          result[vi+'source'][name]['sinephase'] = sinephase if sinephase
        when 'exp'
          val0, val1, td1, tau1, td2, tau2 = (params && params.split.map{|a| remove_curly_brackets a})
          result[vi+'source'][name]['val0'] = val0 if val0
          result[vi+'source'][name]['val1'] = val1 if val1
          result[vi+'source'][name]['td1'] = td1 if td1
          result[vi+'source'][name]['tau1'] = tau1 if tau1
          result[vi+'source'][name]['td2'] = td2 if td2
          result[vi+'source'][name]['tau2'] = tau2 if tau2
        else
          result[vi+'source'][name] = {'type' => 'dc', 'dc' => remove_curly_brackets(type)}
        end
      elsif l=~ /^ *([Ee]\S*) +(\(.*\)) +(\S+) +(.*) */ ||
          l=~ /^ *([Ee]\S*) +(\S+ \S+) +(\S+) +(.*) */
        nets << (n2=$2.split)
        result['vcvs'][$1] = {'gain' => remove_curly_brackets($3)}
        result['connection'][$1] = {'type'=> 'vcvs', 'nets'=>n2}
        parms, = parse_parameters $4
        parms.each_pair{|k, v|
          result['vcvs'][$1][k] = v
        }
      elsif l=~ /^ *([Ff]\S*) +(\(.*\)) +(\S+) +(.*) */ ||
          l=~ /^ *([Ff]\S*) +(\S+ \S+) +(\S+) +(.*) */
        nets << (n2=$2.split)
        result['cccs'][$1] = {'gain' => remove_curly_brackets($3)}
        result['connection'][$1] = {'type'=> 'cccs', 'nets'=>n2}
        parms, = parse_parameters $4
        parms.each_pair{|k, v|
          result['cccs'][$1][k] = v
        }
      elsif l=~ /^ *([Gg]\S*) +(\(.*\)) +(\S+) +(.*) */ ||
          l=~ /^ *([Gg]\S*) +(\S+ \S+) +(\S+) +(.*) */
        nets << (n2=$2.split)
        result['vccs'][$1] = {'gm' => remove_curly_brackets($3)}
        result['connection'][$1] = {'type'=> 'vccs', 'nets'=>n2}
        parms, = parse_parameters $4
        parms.each_pair{|k, v|
          result['vccs'][$1][k] = v
        }
      elsif l=~ /^ *([Hh]\S*) +(\(.*\)) +(\S+) +(.*) */ ||
          l=~ /^ *([Hh]\S*) +(\S+ \S+) +(\S+) +(.*) */
        nets << (n2=$2.split)
        result['ccvs'][$1] = {'rm' => remove_curly_brackets($3)}
        result['connection'][$1] = {'type'=> 'ccvs', 'nets'=>n2}
        parms, = parse_parameters $4
        parms.each_pair{|k, v|
          result['ccvs'][$1][k] = v
        }
      elsif set_instance l, nets, result 
      else
        l=~ /^ *(\S+)/
        result['unknown'] ||= {}
        result['unknown'][$1] = {}
      end
    }
    result['nets'] = nets.flatten.uniq.sort
    result
  end

  def set_instance l, nets, result 
    if l=~ /^ *(\S+) +\(([^)=]*)\) +(\S+) *(.*) */ || l=~ /^ *(\S+) +([^=]*) +([^ =]+)( +\S+ *=.*)* *$/
      nets << (n2=$2.split)
      result['instance'] ||= {}
      result['instance'][$1] = {}
      result['connection'][$1] = {'subckt'=>$3, 'nets'=>n2}
      parms, = parse_parameters $4
      parms.each_pair{|k, v|
        result['instance'][$1][k] = v          
      }          
    end
  end

  def use_section_in_model_library?
    false
  end

  NUMBER_OF_FINGERS = 'nf' unless defined? NUMBER_OF_FINGERS # Caution! this name depends on PDK

  def find_mos_models description
    models = {}
    description.downcase.each_line{|l|
      if l =~ /(^ *)([m]\S*) (\([^\)]*\)) +(\S+) +(.*)$/
        parms, = parse_parameters $5
        models[$4] ||= []
        models[$4] << {'l'=> parm_eval(parms['l']),
                       'w'=> parm_eval2(parms['w'], parms[NUMBER_OF_FINGERS])}
      end
    }
    models.each_value{|v| v.uniq!}
  end

  def parm_eval p
    # p is like: "{(2u)*(8)}"
    value = eval p.gsub(/[\{\}]/,'').gsub('m','*1e-3').gsub('u','*1e-6').gsub('n','*1e-9')
    return value.to_s
  end  

  def parm_eval2 p1, p2
    # p is like: "{(2u)*(8)}"
    value1 = eval p1.gsub(/[\{\}]/,'').gsub('m','*1e-3').gsub('u','*1e-6').gsub('n','*1e-9')
    return value1.to_s unless p2
    value2 = eval p2.gsub(/[\{\}]/,'').gsub('m','*1e-3').gsub('u','*1e-6').gsub('n','*1e-9')
    return (value1/value2).to_s
  end  

  private :parm_eval, :parm_eval2

  def set_model_choices cell_netlist, model_choices, lw_correction 
    result = ''
    cell_netlist.each_line{|line|
      if line =~ /^ *([dDqQjJcCrR]\S*) +\([^\)]*\) +(\S+) +(.*)$/
        name = $1
        model = $2
        if model_choices[model] #  if model is subckt
          unless name.start_with?('X')
            line.sub! name, 'X'+name   # this should be peformed before model is changed to new_model 
          end
        end
      elsif line =~ /^ *([^vVeEfFhH]\S*) +\([^\)]*\) +(\S+) +(.*)$/  # mos does not always start with [mM]
        name = $1
        model = $2
        parms, = parse_parameters $3.downcase
        l = parms['l']
        w = parms['w']
        if l  && w 
          if model_choices[model] #  if model is subckt
            unless name.start_with?('X')
              line.sub! name, 'X'+name   # this should be peformed before model is changed to new_model 
            end
          elsif !(name.start_with?('m') || name.start_with?('M'))
            line.sub! name, 'M'+name
          end
          if new_model =  model_choices[{'model'=>model.downcase,
                                          'l'=> parm_eval(l),
                                          'w'=> parm_eval2(w, parms[NUMBER_OF_FINGERS])}]
            line.sub! model, new_model
            model = new_model
          end
          if lw_c = lw_correction[model]
            if xl = lw_c['xl']
              line.sub!(/ l *= *(\S+)/, " l = {#{l}+(#{xl})}")
            end
            if xw = lw_c['xw']
              line.sub!(/ w *= *(\S+)/, " w = {#{w}+(#{xw})}")
              if as = parms['as']
                new_as = "#{as}*(1.0+(#{xw})/#{w})"
                line.sub!(/ as *= *(\S+)/, " as = {#{new_as}}")
              end
              if ad = parms['ad']
                new_ad = "#{ad}*(1.0+(#{xw})/#{w})"
                line.sub!(/ ad *= *(\S+)/, " ad = {#{new_ad}}")
              end
              if ps = parms['ps']
                new_ps = "#{ps}+2.0*(#{xw})"
                line.sub!(/ ps *= *(\S+)/, " ps = {#{new_ps}}")
              end
              if pd = parms['pd']
                new_pd = "#{pd}+2.0*(#{xw})"
                line.sub!(/ pd *= *(\S+)/, " pd = {#{new_pd}}")
              end
            end
          end
        end
      end
      result << line
    }
    return result
  end

  def convert_section description
    result = ''
    flag = nil # used to count the depth of curly brackets
    inline_flag = nil # used to ignore lines between 'inline subckt' and 'ends' except 'include'
    function_flag = nil
    description && description.each_line{|l|
      next if l.include?('simulator lang=') || l.include?('SIMULATOR LANG=')
      if function_flag
        if l =~ /^ *\}/
          function_flag = nil
          result << "}\n"
        elsif l =~ /return +(.*);/
          result << $1
        else
          result << '*' + l # this should not happen though
        end
        next
      elsif l =~ /^real/
        result << '.function ' + l.chomp.gsub!(/real +/, '')
        function_flag = true
        next
      end
      if l =~ /^ *[Ss]etoption[0-9]* +options/
        l.sub! /#{$&}/, '.options'
        result << check_options(l){|p, v|
          l.sub!(/#{p} *= */, "#{p}=")
          l.sub!(" #{p}=#{v}", '') 
          l.sub!("+#{p}=#{v}", '+') 
        }
        next
      end
      l.sub!(/^ *parameters/, '.param')
      l.sub!(/^ *PARAMETERS/, '.PARAM')
      l.gsub!(/^ *\/\//, '*')
      if flag  # ignore statistics block
        flag = flag - l.count('}') + l.count('{')
        flag = nil if flag == 0
        result << l.sub(/^/, '* ')
      elsif l =~ /^ *statistics *\{/ || l =~ /^ *STATISTICS *\{/
        flag ||= 1
        result << l.sub(/^/, '* ')
      elsif l =~ /inline *subckt *(.*)/ || l =~ /INLINE *SUBCKT *(.*)/
        #        result << ".subckt #{$1}\n"
        inline_flag = true
        result << '* ' + l
      elsif l.downcase =~ /ends *(.*)/ && !l.downcase =~ /endsection/
        inline_flag = false
        result << '* ' + l
      elsif inline_flag
        if l =~ /\#\{include_model +/ || l =~ /\#\{INCLUDE_MODEL +/
          result << l 
        else
          result << '* ' + l
        end
      else
        result << l
      end
    }
    result
  end

  def convert_library lib_description, description
    if /^library/ =~ lib_description
      lib_description.sub!(/^library.*$/,'')
      lib_description.sub!(/endlibrary.*$/,'')
    end
    lib_description + description
  end

  @@VALID_OPTIONS = 'abstol baudrate chgtol cshunt cshuntintern defad defas defl defw delay 
                     fastaccess flagloads gmin gminsteps gshunt itl1 itl2 itl4 itl6 srcsteps
                     maxclocks maxstep meascplxfmt measdgt method minclocks mindeltagmin
                     nomarch noopiter numdgt pivrel pivtol reltol srcstepmethod sstol
                     startclocks temp tnom topologycheck trtol trytocompact vntol plotreltol
                     pltvntol plotabstol plotwinsize ptratau ptranmax'

  def check_options l
    params, = parse_parameters l
    params.each_pair{|p, v|
      if p.downcase == 'temp'
        temperature = v
      elsif (not @@VALID_OPTIONS.include? p.downcase)
        yield p, v
        puts "warning: option parameter '#{p}' was removed because it is not valid in Xyce"
      end
    }
    l
  end

  def check_control orig_control
    temperature = nil
    control, breaks = unwrap orig_control
    count = -1
    result = ''
    control.each_line{|l|
      wl = wrap(l, breaks[count])
      if l.downcase =~/^ *\.option/
        check_options(l){
          wl.sub!(/#{p} *= */, "#{p}=")
          wl.sub!(" #{p}=#{v}", '') 
          wl.sub!("+#{p}=#{v}", '+') 
        }
      end
      result << wl
    }
    [control, temperature]
  end

  def initialize input='input.cir'
    @input = input 
    @output = 'Xyce.out'
  end

  def get_dc_op file
    inf = File.open file
    result = {}
    while l=inf.gets
      next if /^#/ =~ l
      k, t, v = l.chop.split(" ")
      result[k] = v.to_f
    end
    #  p result
    result
  end

  def get_dc *nodes
    @dc_op = get_dc_op self.dc_file_name if File.file? self.dc_file_name
    nodes.map{|n| @dc_op[n]}
  end

  def get_tf
    output = File.open(self.tf_file_name).read
    transfer_func = input_imp = out_imp = nil
    output.each_line{|l|
      l.chop!
      if l =~ /Transfer_function transfer[^ ]* +([^ ]+)/
        transfer_func = $1
      elsif l =~ /Input_impedance impedance[^ ]* +([^ ]+)/
        input_imp = $1
      elsif l =~ /output_impedance.* impedance[^ ]* +([^ ]+)/
        out_imp = $1
      end
    }
    return [transfer_func, input_imp, out_imp]
  end

  def comment input, exception=nil
    comment2 input, '\.dc', exception
    comment2 input, '\.ac', exception
    comment2 input, '\.tran', exception
    comment2 input, '\.noise', exception
  end

  def comment2 input, keyword, exception
    unless exception && keyword.include?(exception.downcase)
      input.sub!(/^ *#{keyword} /, "* #{keyword} ")
      input.sub!(/^ *#{keyword.upcase} /, "* #{keyword.upcase} ")
    end
  end

  private :comment, :comment2

  def run atypes, args='', marching=false, display=nil
    File.delete @output if File.exists? @output
    if /mswin32|mingw|cygwin/ =~ RUBY_PLATFORM    
      @p = IO.popen "runxyce #{get_short_path_name @input}", 'r+'
    else
      @p = IO.popen "runxyce #{@input}", 'r+'
    end
    otf = File.open @output, 'w'
    while line=@p.gets
      otf.puts line
      if line.include? '**error**'
        otf.close
        @p.close
        return line
      end
    end
    otf.close
    @p.close
    @dc_op = get_dc_file self.dc_file_name if File.file? self.dc_file_name
    return nil
  end

  def completed? type=nil
    return nil unless File.exists? @output
    File.read(@output).include? '***** Solution Summary *****'
  end

  def name
    self.class.name
  end

  def conv_ith line, instance_name, i
    line.gsub(/#{instance_name[1..-1]}:/, instance_name[1..-1]+i.to_s+':')
  end

  def batch_script types=nil, input=@input
    script = "$batch = true\n"
#    script << File.open(File.join(RAILS_ROOT, 'lib', File.basename(__FILE__))).read
    script << copy_file_to_load(File.basename(__FILE__))
    script << "\n"
    script << "@xyce = Xyce.new '#{input}'\n"
    return script unless types
#    script << "file '#{types[0]}.raw' => '#{input}' do\n"
    script << "file '#{@rawfile}' => '#{input}' do\n"
    script << "  @xyce.run #{'['+types.map{|a| '"'+a+'"'}.join(',')+']'}\n"
    script << "end\n"
  end

  def batch_script2 run_script, dir, output, type=nil
    script = "file '#{dir}/#{output}' => '#{dir}/#{@input}' do\n"
    script << "  FileUtils.copy '#{dir}/#{@input}', '#{@input}'\n" 
    script << "  FileUtils.cp_r '#{dir}/models', '.'\n" 
    script << "  @xyce.run '#{type}'\n"
    script << run_script
    script << "  FileUtils.move '#{output}', '#{dir}/#{output}'\n" 
    script << "end\n"
  end

  def batch_script3 output, type
    "file '#{output}' => '#{type}.raw' do\n"
  end

  def batch_script4 k_file, rawfile
    if k_file
      "file '#{k_file}' => 'input.raw' do\n"
    else
      "task :postprocess => 'input.raw' do\n"
    end
  end

  def get file, type, *nodes
    if File.exist? file
      CSVwave.new file, *nodes
    else
      save file, type, *nodes
    end
  end

  def postprocess2nodes postprocess, no_quote=false
    if postprocess =~ /\.save *'(.*)' *, '(.*)' *, *(.*) *$/ ||
        postprocess =~ /\.save( *'(.*)' *, '(.*)' *, *(.*) *) *$/
      result = $3
      if no_quote
        return result.split(',').map{|a| a.gsub("'", '')}
      else
        return result.split(',')
      end
    end
  end

  def save file, type, *nodes
    if File.exist? @input+'.raw'  # for ASCO
      FileUtils.cp @input+'.raw', type+'.raw'
    end

    unless File.exists?(type+'.raw') && File.stat(type+'.raw').size > 0
      raise "Output raw file '#{type+'.raw'}' is not available"
    end
    tmp_file = type + '.tmp'

#  It is very strange but the behavior of IO.popen is different if it is
#  called from rails. In a standalone mode, it is necessary to wrap nodes
#  with single quote('). In rails, it is unnecessary.
#   Standalone: ltsputil -xoO 'rawfile' 'tmp_file' '%14.6e' ',' '' 'time' 'V(a)'
#   Rails: ltsputil -xoO 'rawfile' 'tmp_file' '%14.6e' ',' '' time V(a)
#  In addition, output from IO.popen is wrapped by a single quote in Rails.
#  So, gsub is used as in: out.puts line.gsub("'",'') to strip single quotes.

##    if $0 == __FILE__ || $batch
#      node_list = nodes.map{|a| "'"+a+"'"}.join(' ')
##    else
##      node_list = nodes.join(' ')
##    end

    if /mswin32|mingw|cygwin/ =~ RUBY_PLATFORM || File.exist?('/dev/cobd0')
      node_list = nodes[0] + ' ' + change_case(nodes[1..-1]).join(' ')	
    else
      node_list = "'#{nodes[0]}' " + change_case(nodes[1..-1]).map{|a| "'#{a}'"}.join(' ')
    end

    ltsputil '-xo', type+'.raw', tmp_file, node_list

    if file
      out = File.open file, 'w'
    else
      out = nil
    end
    if type == 'ac' || type == 'AC'
      out.puts nodes[0]+','+nodes[1..-1].map{|n| "db(#{n}),phase(#{n})"}.join(',') if out
    else
      out.puts nodes.join(',') if out
    end
    data = []
    File.read(tmp_file).encode('UTF-8', invalid: :replace).each_line{|line|
      next if /^#/ =~ line
      line.chomp!
      line.gsub!("'",'')
      if type == 'ac' || type == 'AC'
	linedata = line.split(',').map{|a| a.to_f}
        new_line = [linedata[0]] + ri2dp(linedata[1..-1])
	data <<	new_line
        out.puts new_line.join(',') if out
      else
        data << line.split(',').map{|a| a.to_f}
        out.puts line if out
      end
    }
    out.close if out

    begin
      Dir.glob('tmp*.tmp'){|f| File.delete f}
    rescue => error
      puts error
    end

    if type == 'ac' || type == 'AC'
      new_nodes = []
      new_nodes << nodes[0]
      nodes[1..-1].each{|n|
        new_nodes << "db(#{n})"
        new_nodes << "phase(#{n})"
      }
      return @wavedata=Wave.new(new_nodes, data, file)
    else
      return @wavedata=Wave.new(nodes, data, file)
    end
  end

  def ri2dp data
    new_data = []
    for i in 0..(data.size)/2-1
      ar=data[i*2]
      ai=data[i*2+1]
      a = Complex(ar, ai)
      new_data << 20*Math.log10(a.abs)
      new_data << a.arg*180/(Math::PI)
    end
    new_data
  end
    
  def check_log log_file
    raise "error: simulation log file '#{log_file}' is not available" unless File.exist? log_file
    File.read(log_file).encode('UTF-8').each_line{|l|
      raise l + " --- please check simulation log" if l.include? 'Fatal Error'
    }
  end

  def log_name
    'Xyce.out'
  end

  def netlist_name dummy=nil
    'input.cir'
  end

  def raw_file_name
    'input.raw'
  end

  def dc_file_name
    'Xyce.dc'
  end

  def tf_file_name
    'Xyce.tf'
  end

  def op_file_name
    'Xyce.op'
  end

  def valid_atype? type
    %w[ac dc tran noise hb].include? type
  end

  def rescue_error
  end

  def scan control, tb_name, nodes
    parsers = [ SPICE_DC.new(tb_name, 'xyce', nodes),
                SPICE_AC.new(tb_name, 'xyce', nodes),
                SPICE_TRAN.new(tb_name, 'xyce', nodes),
                SPICE_NOISE.new(tb_name, 'xyce', nodes),
                SPICE_TF.new(tb_name, 'xyce', nodes),
                SPICE_OP.new(tb_name, 'xyce', nodes)]
    Postprocess.new.scan control, parsers
  end

  def step2params net
    return nil if net.nil?
    # .step oct param srhr4k  0.8 1.2 3
    # steps['srhr4k'] = {'type' => 'param', 'step' => 'oct', 'values' => [0.8, 1.2, 3]}
    # .step v1 1 3.4 0.5
    # steps['v1'] = {'type' => nil||'src', 'step' => nil||'linear', 'values'..}
    # .step NPN 2N2222(VAF)
    # steps['2N2222_VAF'] = {'type'=>'model', 'step'=>nil, ...}
    steps = []
    net.each_line{|line|
      next unless line =~ /^ *\.step +(.*)$/
      args = $1.split
      step = args.shift
      unless step =~ /lin|oct|dec/
        args.unshift step
        step = 'lin'
      end
      name = args.shift
      type = nil
      if name == 'param'
        type = 'param'
        name = args.shift
      else
        model = args.shift
        if model  =~ /\S+\((\S+)\)/
          type = 'model'
          name = name + '_' + $1+'_'+$2
        else
          args.unshift model
          type = 'src'
        end
      end
      values = args
      if values[0] == 'list'
        step = 'list'
        values.shift # values = ["list", "0.3u", "1u", "3u", "10u"]
      end
      steps << {'name' =>name, 'type'=>type, 'step'=>step, 'values'=>values}
    }
    steps.reverse
  end

  def replace_steps net, steps
    return nil if net.nil?
    result = ''
    net.each_line{|line|
      if line.downcase =~ /^ *\.step +(.*)\r*$/
        result << '*'  # comment out
      elsif line.downcase =~ /^ *\.param +(.*)\r*$/
        pairs, singles = parse_parameters line
        steps.each{|s|
          next unless s['type'] == 'param' 
          n = s['name']
          if v = pairs[n]
            line.sub! /#{n} *= *#{v}/, "#{n}=\#\{@#{n}}"
          end
        }
      elsif line.downcase =~/^ *\.end *\r*$/
        line = '*' + line
      else  # notice: models in steps are not handled yet
        if line.downcase =~ /^ *([v|i]\S+) +(\S+ +\S+|\(.+\)) +(\S+) *(.*)$/
          name = $1
          value = $3
          steps.each{|s|
            next unless s['type'] == 'src' 
            n = s['name']
            if n.downcase == name.downcase
              line = "#{name} #{$2} \#\{@#{n}} #{$4}\n"
              break;
            end
          }
        end
      end
      result << line
    }
    result
  end

  def params2script params
    parameters = params.map{|p| "@#{p['name']}"}
    pnames = parameters.map{|p| "'#{p}'"}.join(', ')
    script = "@parameters = [#{pnames}]\n"
    script << "@assignments = []\n"
    depth = 0
    params.each{|p|
      name = p['name']
      step = p['step']
      v = p['values'].map{|value| eng2number value}
      script << ' '*depth*2
      depth = depth + 1
      if step == 'lin'
        script << "#{v[0]}.step(#{v[1]},#{v[2]}){|#{name}|\n"
      elsif step == 'oct'
        script << "#{v[0]}.step(#{v[1]},#{v[2]}){|#{name}|\n"
      elsif step == 'dec'
        script << "#{v[0]}.step(#{v[1]},#{v[2]}){|#{name}|\n"
      elsif step == 'list'
        script << "[#{v.join(', ')}].each{|#{name}|\n"
      end
    }
    if params && params.size > 0
      script << ' '*depth*2 + '@assignments << '
      script << "[#{params.map{|p| "#{p['name']}"}.join(', ')}]\n"
      (depth-1).downto(0){|d|
        script << ' '*d*2 + "}\n"
      }
    end
    puts 'script=', script
    eval(script)
    assignments = @assignments
    @assignments = nil
    [parameters, script, assignments]
  end

  def do_eval scr
    @xyce = self
    eval scr
  end

  private

  def sub_middlebrook x, y
    (x*y-1)/(x+y+2)
  end

  def sub_michael_tian ivi_1, ivi_2, vx_1, vx_2
    -1/(1-1/(2*(ivi_1*vx_2-vx_1*ivi_2)+vx_1+ivi_2))
  end

end

class Xyce_add_Mult < SPICE_add_Mult
  private
  def add_mult pname, val
    val = val.strip
    if val[0..0] == '('
      return "{\#{#{pname}}*#{val[1..-2]}}"   # strip '(' & ')'
    else
      return "{\#{#{pname}}*#{val}}"
    end
  end
end

class Xyce_to_Ngspice
  def convert_model description
    new_desc = description
  end

  def convert_model_library description
    new_desc = description
  end
end

class Xyce_to_Spectre < SPICE_to_Spectre
  def convert_postprocess postprocess
    return nil unless postprocess
    type = nil
    pp_name = nil
    new_pp = ''
    postprocess.each_line{|l|
      l.chomp!
      if l =~ /^ *(\S+) *: *(\S+)/
        pp_name = $1
        type = $2
        unless ['ac', 'dc', 'tran'].include? type
          new_pp << l + "\n"
        end
      elsif l =~ /(^.*)@xyce.save\( *(\S+), +(\S+), +(\S+), +(.*)\) *$/ ||
          l =~ /(^.*)@xyce.save +(\S+), +(\S+), +(\S+), +(.*)/
# from:tes2_Spectre_gain: ac
#        wave = @xyce.save 'gain.csv', 'ac', 'frequency', 'V(n002)'
# to: tes2_Spectre_gain: frequencySweep.ac
#         wave = @spectre.get_psf 'gain.csv', 'frequencySweep.ac', 'freq', 'N002'
	lhs = $1
        csv = $2
        sweep = $4
        nodes = convert_nodes $5
        if type == 'ac'
          new_pp << "#{pp_name}: frequencySweep.ac\n"
          new_pp << "#{lhs}@spectre.get_psf #{csv}, 'frequencySweep.ac', 'freq', #{nodes.map{|a| "'#{a}'"}.join(', ')}\n"
        elsif type == 'dc'
          new_pp << "#{pp_name}: dcSweep.dc\n"
          new_pp << "#{lhs}@spectre.get_psf #{csv}, 'dcSweep.dc', 'dc', #{nodes.map{|a| "'#{a}'"}.join(', ')}\n"
        elsif type == 'tran'
          new_pp << "#{pp_name}: timeSweep.tran\n"
          new_pp << "#{lhs}@spectre.get_psf #{csv}, 'timeSweep.tran', 'time', #{nodes.map{|a| "'#{a}'"}.join(', ')}\n"          
        else
          new_pp << "#{pp_name}: anySweep.any\n"
          new_pp << "#{lhs}@spectre.get_psf #{csv}, '#{type}', #{sweep}, #{nodes.map{|a| "'#{a}'"}.join(', ')}\n"
        end
      elsif l=~/(.*)@xyce.get_dc\((.*)\)(.*)$/
        nodes = convert_nodes($2).map{|a| "'#{a}'"}.join(', ')
        new_pp << "#{$1}@spectre.get_dc(#{nodes})#{$3}\n"
      elsif l =~ /@xyce/ 
        new_pp << l.gsub('@xyce', '@spectre') + "\n"
      else
        new_pp << l + "\n"
      end
    }
    new_pp
  end

  def convert_nodes nodes
    nodes.gsub("'",'').gsub(' ','').downcase.split(',').map{|a|
      if a =~ /[vV]\((.*)\)/
        $1.upcase
      elsif a =~ /[iI]\((.*)\)/
        $1.downcase + ':p'
      elsif a =~ /[iI]([a-z])\((.*)\)/
        $3.upcase + ':' + $1
      end
    }
  end
end

if $0 == __FILE__
#  sim = Xyce.new ARGV[0] 
#  sim.run
#  sim.save 'out.csv', 'time', 'V(a)'
#  sim.gain 'out.csv', 'V(a)', 'V(b)'
#  sim.gain 'out.csv', 'V(a)'
#  sim.save 'out.csv', 'time', 'V(6)'
#  sim.middlebrook 'out.csv', 'I(V3)', 'I(V4)', 'V(x)', 'V(y)'
#   sim.gain 'out.csv', 'V(n002)'
#  sim.michael_tian 'out.csv', 'I(Vi)', 'V(x)'
  marching_display = ARGV.pop
  input = ARGV.pop
  sim = Xyce.new input
  sim.run "#{ARGV.join(' ')}", input, marching_display
end
