# Copyright(C) 2009-2020 Anagix Corporation
if $0 == __FILE__
  $:<< File.dirname(__FILE__) 
  require 'spice_parser'
end
require 'complex'
require 'fileutils'
require 'rubygems'
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

def wine_path
  [File.join(ENV['HOME'],'.wine','drive_c'),
   File.join(ENV['HOME'],'.wine','drive_c'),
   File.join(ENV['HOME'],'Wine Files','drive_c')].each{|path|
    return path if File.directory? path
  }
  nil
end
private :wine_path

def ltspice_path_wine
  if wp = wine_path()
    ['/Program Files/LTC/LTspiceXVII/XVIIx64.exe',
     '/Program Files/LTC/LTspiceXVII/XVIIx86.exe',
     '/Program Files (x86)/LTC/LTspiceIV/scad3.exe',
     '/Program Files/LTC/LTspiceIV/scad3.exe'].each{|path|
      ltspice_path = File.join wp, path
      return ltspice_path if File.exist? ltspice_path
    }
  end
  nil
end

def ltspice_path_WSL
  if File.directory? '/mnt/c/Windows/SysWOW64/'
    ['/mnt/c/Program Files/LTC/LTspiceXVII/XVIIx64.exe',
     '/mnt/c/Program Files/LTC/LTspiceXVII/XVIIx86.exe',
     '/mnt/c/Program Files (x86)/LTC/LTspiceIV/scad3.exe'].each{|path|
      return path if File.exist? path
    }
  end
  nil
end

def model_files include_files
  model_files = []
  include_files.each{|f|
    File.read(f).each_line{|l|
      if l =~ /include \"\.\/(\S+)\"/
        model_files << File.join(File.dirname(f), $1)
      end
    }
  }
  if model_files.size > 0
     model_files
  else
    [include_files[0]]
  end
end

if /mswin32|mingw/ =~ RUBY_PLATFORM
  ENV['HOME'] ||= ENV['HOMEPATH'] || ENV['HOMESHARE']
elsif ($LTspice_path = ENV['LTspice_path']).nil?
  $LTspice_path = ltspice_path_WSL() || ltspice_path_wine()
  ENV['LTspice_path'] = $LTspice_path
end

class LTspice < Spice
  def get_cells_and_symbols
    symbols = Dir.glob("*.asy").map{|a| a.sub('.asy','')}
    cells = Dir.glob("*.asc").map{|a| a.sub('.asc','')}
    cells = cells + Dir.glob('*.net').map{|a| a.sub('.net','')}
    [cells, symbols]
  end

  def search_symbols cell
    symbols = []
    #  File.exist?(cell) && File.read(cell).each_line{|l|
    File.exist?(cell+'.asc') && File.open(cell+'.asc', 'r:Windows-1252').read.encode('UTF-8', invalid: :replace).each_line{|l|
      if l =~ /SYMBOL +(\S+) +/
        symbols << $1
      end
    }
    symbols.uniq
  end

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
      result << "PWL (#{props['wave']||$1})"
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
        puts "warning: option parameter '#{p}' was removed because it is not valid in LTspice"
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

# ruby ltspice.rb input 

  def initialize input=self.netlist_name, remote_host=nil
    @resultsDir = Dir.pwd + '/'
    @input = input 
    @rawfile = input.sub(File.extname(input),'') +'.raw' if input
    @remote_host = remote_host
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
    display ||= ENV['DISPLAY']||'localhost:1'
    puts "run: display = #{display}"
#    File.delete @rawfile if File.exists? @rawfile
    File.delete 'rawfiles' if File.exist? 'rawfiles'
    marching_display = ''
    marching_display = display||ENV['DISPLAY']||'localhost:1' if marching
    begin
      input = File.open(@input){|inf| inf.read.encode('UTF-8')}
      input_copy = input.dup
      if /^( *\.op[^t])/ =~ input ||  /^( *\.OP[^T])/ =~ input
        input_copy.sub!($1, '* '+$1)
        input.sub!(/^ *\.TF /,'* .TF '); input.sub!(/^ *\.tf /,'* .tf ')
        comment input
        File.open('input.op', 'w'){|otf| otf.print input}
        dc_op 'input.op', self.dc_file_name
        @dc_op = get_dc_op self.dc_file_name if File.file? self.dc_file_name
        FileUtils.copy 'input.log', self.op_file_name   # easiest fix to show log for .OP
      end
      input = input_copy
      if /^( *\.tf)/ =~ input ||  /^( *\.TF)/ =~ input
        input_copy = input.dup
        input_copy.sub!($1, '* '+$1)
        comment input
        File.open('input.tf', 'w'){|otf| otf.print input}
        dc_op 'input.tf', self.tf_file_name
        @tf = get_dc_op self.tf_file_name if File.file? self.tf_file_name
      end
      atypes = [atypes] if atypes.class == String
      atypes.each{|type|           # ['ac', 'dc', 'tran'] 
        next unless valid_atype? type
        input = input_copy.dup
        comment input, type
        File.open('input.'+type, 'w'){|otf| otf.print input}
	File.delete 'input.op.raw' if File.exist? 'input.op.raw'
        File.delete type+'.raw' if File.exist? type+'.raw'
        puts "Execute #{type} analysis: scad3 #{args} input.#{type}"
        execute args, "input.#{type}", marching_display # @rawfile='input.raw' is deleted
        check_log(log_name())
        if File.exist? @rawfile
          File.rename @rawfile, type+'.raw' 
          rawfiles = split_stepped_file type+'.raw' # if simulation is stepped
        end
	if File.exist? 'input.op.raw'
          dc_op_conv 'input.op.raw', dc_file_name()
        elsif File.exist? 'dc.raw'
          dc_op_conv 'dc.raw', dc_file_name()
        end
      }
      @rawfile = nil unless File.exists? @rawfile
      return nil
    rescue => error
      puts error; puts error.backtrace
      return error
    end
  end
  
  def get_cpu pid
    result = `ps auwx|grep "^\`whoami\` *#{pid}"`  
    raise if result.include? 'defunct'
    result.split[2].to_f   # [username, processid, %cpu, ...] 
  end

  def execute arg, input, marching_display=''
    if marching_display == ''
      display = ENV['DISPLAY']||'localhost:1'
    else
      display = marching_display
    end

    File.delete 'completed' if File.exist? 'completed'
    rawfile = input.sub(File.extname(input),'') +'.raw'
    File.delete rawfile if File.exist? rawfile
    File.delete 'wine.log' if File.exist?('wine.log')
    if /mswin32|mingw|cygwin/ =~ RUBY_PLATFORM
      command = get_short_path_name(ltspice_path())
      puts "execute under win: #{command} #{arg} #{input}"
      @p = IO.popen "#{command} #{arg} #{input}"
      while line=@p.gets
        puts line
      end
      @p.close
    elsif ltspice_path_WSL()
      command = "'#{ltspice_path()}' #{arg} '#{input}' > WSL.log"
      puts "execute under WSL: #{command}" 
      system command
    else
      if $0 == __FILE__
        ltspice arg, input, marching_display
      else
        puts "display=#{display}, marching_display=#{marching_display}"
        if (defined? RAILS_ROOT) && !(__FILE__.include? RAILS_ROOT)  # from inside ALB 
          puts "From inside ALB execute:"
          puts "DISPLAY=#{display} LTspice_path='#{ltspice_path()}' ruby #{File.join(RAILS_ROOT, __FoILE__)} #{arg} #{input} '#{marching_display}'" 
          system "DISPLAY=#{display} LTspice_path='#{ltspice_path()}' ruby #{File.join(RAILS_ROOT, __FILE__)} #{arg} #{input} '#{marching_display}'" 
       else  # ltspice.rb executed standalone
          puts "ltspice.rb executed standalone, arg='#{arg}'"
          if @remote_host
            system "ssh #{@remote_host} \"cd #{Dir.pwd}; export DISPLAY=#{display}; ruby #{__FILE__} #{arg} #{input} '#{marching_display}'\""
          else
            system "export DISPLAY=#{display}; ruby #{__FILE__} #{arg} #{input} '#{marching_display}'"
          end
        end
        sleep 2
      end
    end
    unless File.exist? rawfile
      if File.exist?('wine.log') && File.stat('wine.log').size > 0
        raise File.read('wine.log') 
      elsif File.exist?('WSL.log') && File.stat('WSL.log').size > 0
        raise File.read('WSL.log') 
      else
        raise "LTspice error: #{rawfile} has not been created" 
      end
    end
    File.open('completed','w'){}
  end

  def ltspice arg, input, marching_display=''
#    if marching_display != ''
#      exec 'wine', command, '-wine', arg, input
#      return
#    end
#    puts "Current directory in def ltspice is: #{Dir.pwd}"
    start_time = Time.now

    puts "simulator started running at #{start_time}"
    if ENV['LTSPICE_is_old']
      pid = fork do
        exec "wine '#{ltspice_path()}' -wine #{arg} '#{input}'"
      end
      begin
        while Time.now - start_time < 10  # keep checking for 10 sec
          sleep 1
          cpu1 = get_cpu pid  # raise error if the process becomes zombi
          sleep 1
          cpu2 = get_cpu pid
          puts "cpu1=#{cpu1}->cpu2=#{cpu2}; waited #{Time.now - start_time} sec."
          if cpu2 < 1 && cpu2 < cpu1
            Process.kill 9, pid 
            puts "process #{pid} killed to avoid waiting forever for user intervention"
            break
          end
        end
      rescue
        puts "simulation execution #{pid} already finished waiting to be buried with due ceremony"
      end
      Process.wait
    end
    puts "ltspice_path = #{ltspice_path()} #{arg} '#{input}'"
    if ltspice_path_WSL()
      system "'#{ltspice_path()}' #{arg} '#{input}' > WSL.log"
    elsif ltspice_path_wine()
      exec "wine '#{ltspice_path()}' -wine #{arg} '#{input}' 2>&1|tee wine.log"
    end
    puts "simulation finished after #{Time.now - start_time} sec. at #{Time.now}"
  end

  def get_size rawdata
    rawdata.each_line{|l|
      if /^No\. Variables: (\d*)/ =~ l 
        return $1.to_i 
    end
    }
    nil
  end
  
  def get_key_variables rawdata, nv
    data = []
    flag = false
    rawdata.each_line{|l|
      if flag
        data << l.chomp.split(' ')
        nv = nv - 1
        flag = false if nv == 0
      else
        flag = true if l.index('Variables') == 0
      end
    }
    data
  end

  def get_key_values rawdata, nv, sweep_no=0
#    count = 0
    data = []
    flag = false
    rawdata.each_line{|l|
#      puts "#{count}: #{l}"
#      count = count + 1 
      if flag
        data << l.strip
        nv = nv - 1
        flag = false if nv == 0
      elsif l =~ /^#{sweep_no}\s+(\S+)$/
        data << $1.strip
        nv = nv - 1
        flag = true
      end
    }
    data
  end

#  private :get_size, :get_key_varables, :get_key_values

  def dc_op input='input.cir', output=self.dc_file_name
    puts "Execute DCOP analysis: #{ltspice_path()} -b #{input}"
    execute '-ascii -b', input # note: execute is a defined method

    check_log(log_name())

    rawfile = input.sub(File.extname(input),'') +'.raw'
    File.rename rawfile, 'op.raw' if File.exist? rawfile
    dc_op_conv 'op.raw', output
  end

  def dc_op_conv input, output, sweep_no=0
    if File.extname(input) == '.raw'
      ltsputil_sub '-coa', input, input.sub('.raw','.ascii')
      input = input.sub('.raw','.ascii')
    end
    Dir.glob('tmp*.tmp'){|f| File.delete f}
    rawdata = File.read input
    File.open(output, 'w'){|otf|
      if nv = get_size(rawdata)   # nv was nil when sleep 1 was absent
        variables = get_key_variables rawdata, nv
        values = get_key_values rawdata, nv, sweep_no
        for i in 0..nv-1
          otf.print "#{variables[i][1]} #{variables[i][2]} "
          otf.printf "%14.6g\n", values[i] # values[i][0] was wrong --- where was it from?
        end
      end
    }
  end

  def completed? type=nil
    File.exists? 'completed'
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
    script << "@ltspice = LTspice.new '#{input}'\n"
    return script unless types
#    script << "file '#{types[0]}.raw' => '#{input}' do\n"
    script << "file '#{@rawfile}' => '#{input}' do\n"
    script << "  @ltspice.run #{'['+types.map{|a| '"'+a+'"'}.join(',')+']'}\n"
    script << "end\n"
  end

  def batch_script2 run_script, dir, output, type=nil
    script = "file '#{dir}/#{output}' => '#{dir}/#{@input}' do\n"
    script << "  FileUtils.copy '#{dir}/#{@input}', '#{@input}'\n" 
    script << "  FileUtils.cp_r '#{dir}/models', '.'\n" 
    script << "  @ltspice.run '#{type}'\n"
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

  def change_case node_list
    puts "node_list:#{node_list.inspect}"
    node_list.map{|name|
      if name.nil?
        nil
      elsif name =~ /^[Vv]\(([^:]+)\)/     # voltage like V(n001)
        "V(#{$1.downcase})"
      elsif name =~ /^[Vv]\((.+)\)/  # voltage V(x1:n9), V(q:i85:qa1:1#baseBP)
        nodes = $1.split(':')
        last = nodes[-1]
        last = last.upcase unless last.include?('#')
        "V(#{(nodes[0..-2].map{|n| n.downcase} + [last]).join(':')})"
      elsif name =~ /^([Ii])\((.+)\)/ || # device current like I(x1:i505:c2:C), I(V1)
          name =~ /^([Ii]x)\((.+)\)/ || # subckt current like Ix(x1:r43:N), Ix(i91:ADJA[4]), Ix(rc36:r11:1)
          name =~ /^([Ii].)\((.+)\)/ # device current Ig(x1:M13)	
        i = $1.capitalize
        nodes = $2.split(':')
        "#{i}(#{(nodes[0..-2].map{|n| n.downcase} + [nodes[-1].capitalize]).join(':')})"
      else
        name.downcase
      end
    }
  end

  def ltsputil arg, input, output, node_list
    @p = ltsputil_sub arg, input, output, node_list
    while line=@p.gets
      print line
      raise line + @p.gets if line.include? 'ERROR'
    end
    @p.close
#    system '/bin/rm tmp*.tmp'
    Dir.glob('tmp*.tmp'){|f| File.delete f}
  end

  def on_WSL?
    File.exist?('/proc/version') && `grep -E "(MicroSoft|Microsoft|WSL)" /proc/version` != ''
  end
  private :on_WSL?

  def ltsputil_sub arg, input, output=nil, node_list=nil # node_list must be like: "'temperature' 'V(b)' 'V(a)'"
    node_list = "'%14.6e' ',' '' " + node_list if node_list && arg =~ /-xo/
    ltspice_dir = File.dirname(ltspice_path_wine || ltspice_path())
    flag17 = false
    if File.exist?(File.join(ltspice_dir, 'XVIIx64.exe')) || File.exist?(File.join(ltspice_dir, 'XVIIx86.exe'))
      raise "Error: ltsputil17raw4.exe is missing under #{ltspice_dir}" unless File.exist? File.join(ltspice_dir, 'ltsputil17raw4.exe')
      flag17 = true
      FileUtils.mv input, input+'_KEEP'
    end
    if /mswin32|mingw|cygwin/ =~ RUBY_PLATFORM || on_WSL?()
      # node_list = nodes.map{|a| "'"+a+"'"}.join(' ') if  /cygwin/ =~ RUBY_PLATFORM
      command = File.join ltspice_dir, 'ltsputil17raw4.exe'
      command = on_WSL?() ? "'#{command}'" : get_short_path_name(command)
      if flag17
        Dir.chdir(File.dirname input){
          inp2 = File.basename input
          puts "command: #{command} #{inp2+'_KEEP'} #{inp2}"
          system "#{command} #{inp2+'_KEEP'} #{inp2}"
          start = Time.now
          until File.exist? inp2
            raise "#{inp2} was not created " if Time.now - start > 10
          end
        }
      end
      command = File.join ltspice_dir, 'ltsputil.exe'
      command = on_WSL?() ? "'#{command}'" : get_short_path_name(command)
      Dir.chdir(File.dirname input){
        puts "command: #{command} #{arg} #{File.basename input} #{File.basename output} #{node_list}"
        @p = IO.popen "#{command} #{arg} #{File.basename input} #{File.basename output} #{node_list}", 'r+'
      }
    else
      command = ltspice_path_wine() ? 'wine ' : ''
      system command + "'#{File.join ltspice_dir, 'ltsputil17raw4.exe'}' #{input+'_KEEP'} #{input}" if flag17
      command << "'#{File.join ltspice_dir, 'ltsputil.exe'}' #{arg} #{input} #{output} #{node_list}"
      puts "command: #{command}"
      @p = IO.popen command, 'r+'
    end
    sleep 0.5 # Very weird but without sleep 0.2, @p.gets chokes in ltsputil
    FileUtils.mv input+'_KEEP', input, :force => true if flag17
    @p
  end

  def is_stepped? file
    @p = ltsputil_sub '-i', file
    result = false
    while line=@p.gets
      puts line
      result = true if line =~ /Flags:.*stepped/
      if result == true && line =~/Num. of .*sweeps : (\d+)/
        result = $1.to_i
      end
    end
    @p.close
    return result
  end
  private :is_stepped?

  def rawfiles type = nil
    if @rawfiles
      return @rawfiles
    elsif File.exist? 'rawfiles'
      nr = File.read('rawfiles').to_i
      return nil if nr == 0
    else
      return nil
    end
    @rawfiles = Array.new(nr){|i| type + (i+1).to_s}
  end

  def split_stepped_file file
    return nil unless File.exist? file
    return nil unless nsteps = is_stepped?(file)
    ltsputil_sub '-i', file, file
    extname = File.extname(file)
    rootname = file.sub(extname, '')
    @rawfiles = []
    for i in 1 .. nsteps
      @rawfiles << "#{rootname}#{i}"
    end
    puts "#{file} split to #{@rawfiles.inspect}"
    File.open('rawfiles', 'w'){|f| f.puts rawfiles.nil?? '0' : rawfiles.size.to_s}
    @rawfiles
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
    
  def gain file, node_ao, node_bo=nil
    node_a, node_b = change_case [node_ao, node_bo]
    if File.exist? @input+'.raw'  # for ASCO
      FileUtils.cp @input+'.raw', 'ac.raw'
    end

    return nil unless File.exists? 'ac.raw'
    tmp_file = 'ac.tmp'
    if !File.exist?('/dev/cobd0') && ($0 == __FILE__ || $batch || !(/mswin32|mingw|cygwin/ =~ RUBY_PLATFORM))
      node_list = "'frequency' '"+node_a+"'"
      node_list << " '"+node_b+"'" if node_b
    else
      node_list = 'frequency ' + node_a
      node_list << ' ' + node_b if node_b
    end
    ltsputil '-xorc', 'ac.raw', tmp_file, node_list

    if file
      out = File.open file, 'w'
    else
      out = nil
    end
    if node_b
      out.puts 'freq, ' + node_a + '/' + node_b + ', phase' if out
      nodes = ['freq', node_a + '/' + node_b, 'phase']
    else
      out.puts 'freq, ' + node_a + ', phase' if out
      nodes = ['freq', node_a, 'phase']
    end
    data = []
    File.read(tmp_file).encode('UTF-8', invalid: :replace).each_line{|line|
      next if /^#/ =~ line
      line.chomp!.gsub!("'",'')
      line << ',1,0' unless node_b
      freq, ra, ia, rb, ib = line.split(',')
      a = Complex(ra.to_f, ia.to_f)
      b = Complex(rb.to_f, ib.to_f)
      gain = a/b
      db= 20*Math.log10( [gain.abs, 1e-100].max )
      phase = gain.arg*180/(Math::PI)
      out.printf "%14.6e,%14.6e,%14.6e\n", freq, db, phase  if out
      data << [freq.to_f, db, phase]
    }
    out.close if out
    Dir.glob('tmp*.tmp'){|f| File.delete f}
    return Wave.new(nodes, data, file)
  end

  def middlebrook file, iv3, iv4, vx, vy
    return nil unless @rawfile && File.exists?(@rawfile)
    tmp_file = @rawfile.sub(File.extname(@rawfile), '.tmp')
    if $0 == __FILE__ || $batch || !(/mswin32|mingw|cygwin/ =~ RUBY_PLATFORM)
      node_list = "'frequency' '#{iv3}' '#{iv4}' '#{vx}' '#{vy}'"
    else
      node_list = "frequency #{iv3} #{iv4} #{vx} #{vy}"
    end
    ltsputil '-xorc', @rawfile, tmp_file, node_list

    out = File.open file, 'w'
    out.puts 'freq, db, phase'
    File.read(tmp_file).encode('UTF-8', invalid: :replace).each_line{|line|
      next if /^#/ =~ line
      line.chomp!.gsub!("'",'')
      freq, riv3, iiv3, riv4, iiv4, rvx, ivx, rvy, ivy = line.split(',')
      iv3 = Complex(riv3.to_f, iiv3.to_f)      
      iv4 = Complex(riv4.to_f, iiv4.to_f)      
      vx = Complex(rvx.to_f, ivx.to_f)      
      vy = Complex(rvy.to_f, ivy.to_f)      
      gi = iv3/iv4
      gv = -vx/vy
      v = sub_middlebrook(gi, gv)
      out.printf "%14.6e,%14.6e,%14.6e\n", freq, 20*Math.log10(v.abs), v.arg*180/(Math::PI)
    }
    return file
  end

  def michael_tian file, ivi, vx
    return nil unless @rawfile && File.exists?(@rawfile)
    tmp_file = @rawfile.sub(File.extname(@rawfile), '.tmp')
    if $0 == __FILE__ || $batch || !(/mswin32|mingw|cygwin/ =~ RUBY_PLATFORM)
      node_list = "'frequency' '#{ivi}' '#{vx}'"
    else
      node_list = "frequency #{ivi} #{vx}"
    end
    ltsputil '-xorc', @rawfile, tmp_file, node_list

    out = File.open file, 'w'
    out.puts 'freq, db, phase'
    inf = File.open(tmp_file.sub('.tmp', '1.tmp'))
    inf2 = File.open(tmp_file.sub('.tmp', '2.tmp'))
    while line = inf.gets
      line2 = inf2.gets
      next if /^#/ =~ line
      line.chomp!.gsub!("'",'')
      line2.chomp!.gsub!("'",'')
      freq, rivi_1, iivi_1, rvx_1, ivx_1 = line.split(',')
      ivi_1 = Complex(rivi_1.to_f, iivi_1.to_f)      
      vx_1 = Complex(rvx_1.to_f, ivx_1.to_f)      
      freq2, rivi_2, iivi_2, rvx_2, ivx_2 = line2.split(',')
      ivi_2 = Complex(rivi_2.to_f, iivi_2.to_f)      
      vx_2 = Complex(rvx_2.to_f, ivx_2.to_f)      
      if freq != freq2
        print_message 'two sweep results do not match', '*error*'
        print "freq = #{freq}, freq2=#{freq2}\n"
        return
      end
      v = sub_michael_tian(ivi_1, ivi_2, vx_1, vx_2)
      out.printf "%14.6e,%14.6e,%14.6e\n", freq, 20*Math.log10(v.abs), v.arg*180/(Math::PI)
    end
    return file
  end

  def check_log log_file
    raise "error: simulation log file '#{log_file}' is not available" unless File.exist? log_file
    File.read(log_file).encode('UTF-8', invalid: :replace).each_line{|l|
      raise l + " --- please check simulation log" if l.include? 'Fatal Error'
    }
  end

  def log_name
    'input.log'
  end

  def netlist_name dummy=nil
    'input.cir'
  end

  def raw_file_name
    'input.raw'
  end

  def dc_file_name
    'LTspice.dc'
  end

  def tf_file_name
    'LTspice.tf'
  end

  def op_file_name
    'LTspice.op'
  end

  def valid_atype? type
    %w[ac dc tran noise].include? type
  end

  def rescue_error
  end

  def scan control, tb_name, nodes
    parsers = [ SPICE_DC.new(tb_name, 'ltspice', nodes),
                SPICE_AC.new(tb_name, 'ltspice', nodes),
                SPICE_TRAN.new(tb_name, 'ltspice', nodes),
                SPICE_NOISE.new(tb_name, 'ltspice', nodes),
                SPICE_TF.new(tb_name, 'ltspice', nodes),
                SPICE_OP.new(tb_name, 'ltspice', nodes)]
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
    @ltspice = self
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

class LTspice_add_Mult < SPICE_add_Mult
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

class LTspice_to_Spectre < SPICE_to_Spectre
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
      elsif l =~ /(^.*)@ltspice.save\( *(\S+), +(\S+), +(\S+), +(.*)\) *$/ ||
          l =~ /(^.*)@ltspice.save +(\S+), +(\S+), +(\S+), +(.*)/
# from:tes2_Spectre_gain: ac
#        wave = @ltspice.save 'gain.csv', 'ac', 'frequency', 'V(n002)'
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
      elsif l=~/(.*)@ltspice.get_dc\((.*)\)(.*)$/
        nodes = convert_nodes($2).map{|a| "'#{a}'"}.join(', ')
        new_pp << "#{$1}@spectre.get_dc(#{nodes})#{$3}\n"
      elsif l =~ /@ltspice/ 
        new_pp << l.gsub('@ltspice', '@spectre') + "\n"
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

class LTspice_to_Xyce < Converter
  def convert_postprocess postprocess
    return nil unless postprocess
    @type = @csv = nil
    pp_name = nil
    new_pp = ''
    postprocess.each_line{|l|
      l.chomp!
      if l =~ /^ *(\S+) *: *(\S+)/
        pp_name = $1
        @type = $2
        unless ['ac', 'dc', 'tran'].include? @type
          new_pp << l + "\n"
        end
      elsif l =~ /(^.*)@ltspice.save\( *(\S+), +(\S+), +(\S+), +(.*)\) *$/ ||
          l =~ /(^.*)@ltspice.save +(\S+), +(\S+), +(\S+), +(.*)/
	lhs = $1
        @csv = $2
        sweep = $4
        nodes = $5
        @nodes = []
        if @type == 'dc' 
          if sweep == "'temperature'"
            @nodes = ["'temp'"]
          end
        end
        if @type == 'tran'
          sweep = ["'time'"]
        elsif @type == 'ac'
          sweep = ["'freq'"]
        else
          sweep = []
        end
        if @type == 'noise'
          nodes =~ /'V\((.*)\)'/
          @nodes << $1 # ex. @nodes = ['onoise']
        else
          @nodes << nodes.split(',').map{|a| a.strip}
        end
        if ['ac', 'dc', 'tran'].include? @type
          new_pp << "#{pp_name}: #{@type}\n"
          new_pp << "#{lhs}@xyce.get #{@csv}, #{(sweep + @nodes).join(', ')}\n"
        end
      elsif l=~/(.*)@ltspice.get_dc\((.*)\)(.*)$/
        nodes = $2.split(',').map{|a| a.strip}
        new_pp << "#{$1}@xyce.get_dc(#{nodes})#{$3}\n"
      elsif l =~ /@ltspice/ 
        new_pp << l.gsub('@ltspice', '@xyce') + "\n"
      else
        new_pp << l + "\n"
      end
    }
    new_pp
  end

  def convert_netlist orig_netlist
    new_net = ''
    orig_netlist && orig_netlist.each_line{|l|
      if l =~ /^ *[vV]/
        l.sub!('SINE', 'SIN') || l.sub!('sine', 'sin')
      end
      new_net << l    # .gsub(/[{}]/, '')
    }
    new_net
  end

  def convert_control control
    ['options', 'backanno'].each{|str|
      control.gsub!(/^\.(#{str})/, '*.\1')
    }
    control.gsub!(/^\.fourier/, '.four')
    control.gsub!(/^\.params/, '.param')
    control = fix_tran control
    if @csv
      control << "\n.print #{@type} file=#{@csv} format=csv #{@nodes.join(' ')}\n".gsub("'", '')
    else
      control
    end
  end

  def fix_tran control
    ctrl=''
    control.each_line{|l|
      if l =~ /\.tran +(\S+) *\r*\n$/
        tstop = eng2number $1
        tstep = tstop/100
        ctrl << ".tran #{tstep} #{tstop}\n"
      else
        ctrl << l
      end
    }
    ctrl
  end
  private :fix_tran

  def convert_model description
    downcase_flag = false
    downcase_flag = true if description == description.downcase
    type, name, model_parameters = parse_model description.downcase!
    if type == 'nmos' || type == 'pmos'
      if (level=model_parameters['level'])=='8'
        result = description.gsub(/level *= *#{level}/, 'level = 49')
        return downcase_flag && result || result.upcase
      end
    end
    return downcase_flag && description || description.upcase
  end

  def convert_model_library description
    new_desc = ''
    description.each_line{|l|
      if l =~ /\.include "(.*)"/
        new_desc << ".include \"./models/#{$1}\"\n"
      elsif l =~ /\#\{include_model '(\S+)'\}/
        new_desc << "\#\{include_model './models/#{$1}'\}\n"
      end
    }
    new_desc
  end
end

class LTspice_to_Ngspice
  def convert_model description
    new_desc = description
  end

  def convert_model_library description
    new_desc = description
  end
end

class LTspice_to_QUCS < SPICE_to_QUCS
end

if $0 == __FILE__
#  sim = LTspice.new ARGV[0] 
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
  sim = LTspice.new input
  sim.execute "#{ARGV.join(' ')}", input, marching_display
end

require 'numo/narray'
class Ltspice
  attr_accessor :tags, :title, :date, :plot_name, :time_raw, :flags, :_point_num, :_case_num, :_variables, :_types
  def initialize(file_path)
    @file_path = file_path
    @dsamp = 1
    @tags = ["Title:", "Date:", "Plotname:", "Flags:", "No. Variables:", "No. Points:"]
    @time_raw = []
    @data_raw = []
    @_case_split_point = []
    @title = ""
    @date = ""
    @plot_name = ""
    @flags = ""
    @_point_num = 0
    @_case_num = 0
    @_variables = []
    @_types = []
    @_mode = "Transient"
  end
  def parse(dsamp: 1)
    @dsamp = dsamp
    size = File.size(@file_path) # os.path.getsize(@file_path)
    tmp = ''.b
    lines = []
    line = ""
    data = nil
    File.open(@file_path, "rb") {|f|
      data = f.read()
      f.close()
    }
#    data = File.open(@file_path, 'rb').read
    bin_index = 0
    while !line.include?("Binary")
      tmp = tmp + data[bin_index].b # bytes([data[bin_index]])
      if data[bin_index].b == "\n".b #  == b'\n'
        bin_index = bin_index + 1
        tmp = tmp + data[bin_index].b
        # line = tmp[0..-3].force_encoding('UTF-16LE')   # = tmp, encoding: "UTF16".to_s
        line = tmp.gsub(0.chr,'')
        lines.push(line)
        tmp = ''
      end
      bin_index = bin_index + 1
    end
    vindex = 0
    lines.each_with_index{|line, index|  # for (index, line) in enumerate(lines)
      if line.include?(@tags[0])
        @title = line[@tags[0].size..-1]
      end
      if line.include?(@tags[1])
        @date = line[@tags[1].size..-1]
      end
      if line.include?(@tags[2])
        @plot_name = line[@tags[2].size..-1]
      end
      if line.include?(@tags[3])
        @flags = line[@tags[3].size..-1]
      end
      if line.include?(@tags[4])
        @_variable_num = (line[@tags[4].size..-1]).to_i
      end
      if line.include?(@tags[5])
        @_point_num = (line[@tags[5].size..-1]).to_i
      end
      if line.include?("Variables:")
        vindex = index
      end
    }
    for j in @_variable_num.times
      vdata = (lines[(vindex + j) + 1]).split()
      @_variables.push(vdata[1])
      @_types.push(vdata[2])
    end
    if @plot_name.include?("FFT")
      @_mode = "FFT"
    else
      if @plot_name.include?("Transient")
        @_mode = "Transient"
      else
        if @plot_name.include?("AC")
          @_mode = "AC"
        end
      end
    end
    if (@_mode == "FFT") || (@_mode == "AC") # is_bool(@_mode == "FFT" || @_mode == "AC")
      # @data_raw = Numo::NArray.cast data[bin_index..-1].unpack 'd*' # np.frombuffer(data[bin_index..-1], dtype: np.complex128)
      raw_data = data[bin_index..-1].unpack 'd*'
      c = []
      (raw_data.size/2).times{|i| c << Complex(raw_data[2*i], raw_data[2*i+1])}
      @data_raw = Numo::NArray.cast c
      d = []
      @data_raw.each_with_index{|v, i| d << v if i % @_variable_num == 0}
      @time_raw = Numo::NArray.cast(d).abs # np.abs(self.data_raw[::self._variable_num])
      @data_raw = @data_raw.reshape @_point_num, @_variable_num #np.reshape(@data_raw, [@_point_num, @_variable_num])
    else
      if @_mode == "Transient"
        expected_data_len = (@_point_num * (@_variable_num + 1)) * 4
        if data.size - bin_index == expected_data_len
          @data_raw = data[bin_index..-1].unpack 'f*'  # np.frombuffer(data[bin_index..-1], dtype: Numo::SFloat)
          @time_raw = Numo::DFloat.zeros(@_point_num)
          for i in @_point_num.times
            d = data[bin_index + ((i * (@_variable_num + 1)) * 4)..(bin_index + ((i * (@_variable_num + 1)) * 4)) + 8]
            @time_raw[i] = d.unpack("d*")[0] # struct.unpack("d", d)[0]
          end
        end
        @data_raw = Numo::NArray.cast(@data_raw).reshape @_point_num, @_variable_num + 1 # np.reshape(Numo::NArray.cast(@data_raw), [@_point_num, @_variable_num + 1])
      end
    end
    @_case_num = 1
    @_case_split_point.push(0)
    start_value = @time_raw[0]
    for i in (@_point_num - 1).times
      if (@time_raw[i] > @time_raw[i + 1] || @time_raw[i] < @time_raw[i + 1]) && (@time_raw[i + 1] == start_value)
        @_case_num += 1
        @_case_split_point.push(i + 1)
      end
    end
    @_case_split_point.push(@_point_num)
  end
  def getData(variable, case_=0, time=nil) # variable, case=0, time=None):
    if variable.include?(",")
      variable_names = re.split_p(",|\\(|\\)", variable)
      return (getData(("V(" + variable_names[1]) + ")", case_, time)) - (getData(("V(" + variable_names[2]) + ")", case_, time))
    else
      variables_lowered = @_variables.map{|v| v.downcase()}
      if !variables_lowered.include?(variable.downcase())
        return nil
      end
      variable_index = variables_lowered.index(variable.downcase())
      if @_mode == "Transient"
        variable_index += 1
      end
      data = @data_raw[@_case_split_point[case_]..@_case_split_point[case_ + 1]-1, variable_index]
      if time === nil
        return data
      else
        return np.interp(time, getTime(case_), data)
      end
    end
  end
  def getTime( case_=0)  #  case: 0
    if @_mode == "Transient"
      return Numo::NArray.cast(@time_raw[@_case_split_point[case_]..@_case_split_point[case_ + 1]-1]).abs()
    else
      return nil
    end
  end
  def getFrequency(case_=0) # case: 0
    if @_mode == "FFT" || @_mode == "AC"
      return Numo::NArray.cast(@time_raw[@_case_split_point[case_]..@_case_split_point[case_ + 1]-1]).abs()
    else
      return nil
    end
  end
  def getVariableNames(case_=0) # case: 0
    return @_variables
  end
  def getVariableTypes(case_=0) # case: 0
    return @_types
  end
  def getCaseNumber()
    return @_case_num
  end
  def getVariableNumber()
    return @_variables.size
  end
end
def integrate(time, var, interval: nil)
  if interval.is_a? Array
    if interval.size == 2
      if time.max < interval.max
        return 0
      else
        # pass
      end
    else
      return 0
    end
  else
    if interval === nil
      interval = [0, time.max]
    else
      return 0
    end
  end
  begin_ = np.searchsorted(time, interval[0]) # begin
  end_ = np.searchsorted(time, interval[1])   # end
  if time.size - 1 < end_
    end_ = time.size - 1
  end
  result = np.trapz(var[begin_..end_], x: time[begin_..end_])
  return result
end
