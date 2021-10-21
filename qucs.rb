# -*- coding: utf-8 -*-
# Copyright Anagix Corporation 2009-2017

require 'rubygems'
require 'byebug'
# require 'ruby-debug'
require 'fileutils'
require 'yaml'

def c2q str
  i = str.to_i
  i*10/16
end

def q2c str
  i=str.to_i
  i*16/10
end

def q2e str
  i = str.to_i
  i*5
end

def e2q str
  i = str.to_i
  i/5
end

def q2x str
  i = str.to_i
end

def x2q str
  f = str.to_f
  f.to_i
end

class QucsComponent
  attr_accessor :name, :description, :model, :symbol

  def initialize name
    @name = name
  end

  def cdraw_comp_in
    @symbol = QucsSymbol.new @name
    @model, @params = @symbol.cdraw_symbol_in
  end

  def qucs_comp_in desc
    @symbol = QucsSymbol.new @name
    @symbol.qucs_symbol_in desc['Symbol']
  end
  
  def eeschema_comp_in desc
    @symbol = QucsSymbol.new @name
    @symbol.eeschema_symbol_in desc
  end

  def xschem_comp_in
    @symbol = QucsSymbol.new @name
    desc = File.read(@name+'.sym')
    @symbol.xschem_symbol_in desc
  end

  def qucs_comp_out lib, model_script
    result = "<Description>\n#{@description}</Description>\n"
    @model = @spice = @params = nil
    case @symbol.prefix
    when 'V'
      case @name
      when 'vdc'
        @spice = ".subckt #{lib}_#{@name} gnd _net1 _net2 vdc=0\n"
        @spice << "V1 _net1 _net2 {vdc}\n"
        @spice << ".ends #{lib}_#{@name}\n"
        @params = [['vdc', '0']]
      when 'vac'
        @spice = ".subckt #{lib}_#{@name} gnd _net1 _net2 dc=0 mag=1\n"
        @spice << "V1 _net1 _net2 {dc} AC {mag}\n"
        @spice << ".ends #{lib}_#{@name}\n"
        @params = [['dc', '0'], ['mag', '1']]
      when 'vsin'
        @spice = ".subckt #{lib}_#{@name} gnd _net1 _net2 sinedc=0 ampl=1 freq=1KHz delay=0 damp=0 sinephase=0\n"
        @spice << "V1 _net1 _net2 SIN ({sinedc} {ampl} {freq} {delay} {damp} {sinephase})\n"
        @spice << ".ends #{lib}_#{@name}\n"
        @params = [['sinedc', '0'], ['ampl', '1'], ['freq', '1Khz'], ['delay', '0'], ['damp', '0'], ['sinephase', 0]]
      when 'vpulse'
        @spice = ".subckt #{lib}_#{@name} gnd _net1 _net2 val0=0 val1=1 delay='' rise='' fall='' width='' period=''\n"
        @spice << "V1 _net1 _net2 PULSE ({val0} {val1} {delay} {rise} {fall} {width} {period})\n"
        @spice << ".ends #{lib}_#{@name}\n"
        @params = [['val0', '0'], ['val1', '1'], ['delay', '0'], ['rise', '0'], ['fall', '0'], ['width', '0'], ['period', '0']]
      end
      @model = ".Def:#{lib}_#{@name} _net1 _net2 U=1.0\n"
      @model << "Vdc:V1 _net1 _net2 U={U}\n"
      @model << ".Def:End\n"
      @params ||= [['U', '1']]
    when 'R', 'res'
#      @model = ".Def:#{lib}_#{@name} _net1 _net2 R=\"1 K\"\n"
      @model = ".Def:#{lib}_#{@name} _net1 _net2 R=1K\n"
#      @model << "R:R1 _net1 _net2 R=\"R\"\n"
      @model << "R:R1 _net1 _net2 R={R}\n"
      @model << ".Def:End\n"
#      @params = " \"1=R=R==\""
      @params = [['R', '1']]
    when 'C', 'cap'
#      @model = ".Def:#{lib}_#{@name} _net1 _net2 C=\"1 p\"\n"
      @model = ".Def:#{lib}_#{@name} _net1 _net2 C=1p\n"
#      @model << "C:C1 _net1 _net2 C=\"C\"\n"
      @model << "C:C1 _net1 _net2 C={C}\n"
      @model << ".Def:End\n"
#      @params = " \"1=C=C==\""
      @params = [['C', '1']]
    when 'S', 'SW'
      @spice = ".subckt #{lib}_#{@name} gnd _net1 _net2 _net3 _net4\n"
      @spice << "SW _net1 _net2 _net3 _net4 #{self.symbol.value}\n"
      @spice << ".ends #{lib}_#{@name}\n"
      @model = ".Def:#{lib}_#{@name} _net1 _net2 _net3 _net4\n"
      @model << "SW:S1 _net1 _net2 _net3 _net4 #{self.symbol.value}\n"
      @model << ".Def:End\n"
    when 'M', 'MP', 'MN'
#      @model = pick_model(model_script, self.symbol.value) || '!!! no model found !!!'
#      
#      @model.gsub /\.Def:\S+/, ".Def:#{lib}_#{@name}"
      @spice = ".subckt #{lib}_#{@name} gnd _net1 _net2 _net3 _net4 L=1u W=1u\n"
      @spice << "M1 _net1 _net2 _net3 _net4 #{self.symbol.value} L={L} W={W}\n"
      @spice << ".ends #{lib}_#{@name}\n"
      @model = ".Def:#{lib}_#{@name} _net1 _net2 _net3 _net4 L=1u W=1u\n"
      @model << "MOSFET:M1 _net2 _net1 _net3 _net4 #{self.symbol.value} L=\"L\" W=\"W\"\n"
      @model << ".Def:End\n"
      @params = [['L', '1'], ['W', '1']] # , ['PS', '0'], ['PD', '0'], ['AS', '0'], ['AD', '0'], ['NRS', '0'], ['NRD', '0']]
    when 'Q', 'QP', 'QN'
#      @model = pick_model(model_script, self.symbol.value) || '!!! no model found !!!'
#      @model.gsub /\.Def:\S+/, ".Def:#{lib}_#{@name}"
      @model = ".Def:#{lib}_#{@name} _net1 _net2 _net3 AREA=1\n"
      @model << "BJT:Q1 _net2 _net1 _net3 #{self.symbol.value} {AREA}\n"
      @model << ".Def:End\n"
      @params = [['AREA', '1']]
    when 'J'
      @model = ".Def:#{lib}_#{@name} _net1 _net2 _net3 AREA=1\n"
      @model << "JFET:J1 _net2 _net1 _net3 #{self.symbol.value} {AREA}\n"
      @model << ".Def:End\n"
      @params = [['AREA', '1']]
    when 'D'
      @model = ".Def:#{lib}_#{@name} _net1 _net2 AREA=1\n"
      @model << "Diode:D1 _net2 _net1 #{self.symbol.value} {AREA}\n"
      @model << ".Def:End\n"
      @params = [['AREA', '1']]
    when 'X'
    end
    result << "<Spice>\n#{@spice}</Spice>\n" if @spice
    result << "<Model>\n#{@model}</Model>\n" if @model
    result << "<Symbol>\n#{@symbol.qucs_symbol_out @params}</Symbol>\n"
  end
  
  def eeschema_comp_out lib, model_script
    result = "DEF #{@name} #{@symbol.prefix||'U'} 0 40 N Y 1 F N\n"
    if @symbol.name_pos
      name_x = q2e(@symbol.name_pos[0] || 0)
      name_y = -q2e(@symbol.name_pos[1] || 0)    
    else
      name_x = name_y = 0
    end
    result << "F0 \"#{@symbol.prefix||'U'}\" #{name_x} #{name_y} 50 H V L CNN\n"
    if @label_pos
      label_x = q2e(@symbol.label_pos[0] || 0)
      label_y = -q2e(@symbol.label_pos[1] || 0)    
      result << "F1 \"#{@name}\" #{label_x} #{label_y} 50 H V L CNN\n"
    end
    @model = @spice = @params = nil
    result << @symbol.eeschema_symbol_out(@params)
    result << "ENDDEF\n"
  end

  def xschem_comp_out sym_file
    File.open(sym_file, 'w'){|f|
      f.puts @symbol.xschem_symbol_out
    }
  end

  def cdraw_comp_out asy_file
    File.open(asy_file, 'w'){|f|
      f.puts @symbol.cdraw_symbol_out
    }
  end

  def pick_model model_script, name
    model = nil
    model_script && model_script.each_line{|l|
      l.chomp!
      if model
        model << l + "\n"
        if l =~ /^ *\.Def:End/
          return model
        elsif l =~ /^ *(\S+): *(\S+)/
          type = $1 # not used
        end
      elsif l =~ /^ *\.Def:(\S+)/
        model = l + "\n" if $1 == name
      end
    }
    nil
  end
end

class QucsLibrary
  attr_accessor :components
  def initialize name, target_dir=File.join(ENV['HOME'], '.qucs')
    @target_dir = target_dir
    @qucs_lib_dir = File.join(target_dir, 'user_lib')
    @qucs_lib = File.join @qucs_lib_dir, name + '.lib'
    @lib_name = name
    @components = []
    @component_is_symbol = {}
  end

  def cdraw_lib_in lib
    symbol_info = {}
    Dir.chdir(lib){
      symbols = Dir.glob('*.asy').map{|a| a.sub('.asy','')}
      cells = Dir.glob('*.asc').map{|a| a.sub('.asc','')}
      cells.delete_if {|c|
        puts "File: '#{c}.asc'"
        # asc_contents = File.open(c + '.asc', 'r:Windows-1252').read.encode('UTF-8').gsub('µ', 'u')
        mu = 181.chr(Encoding::UTF_8)
        asc_contents = File.open(c + '.asc', 'r:UTF-8').read.gsub(mu, 'u').scrub
        not asc_contents.include?('SYMBOL') # asc actually had nothing like a 'gnd'
      }
      topcells = cells - symbols
      symbols = symbols - cells
      cells = cells - topcells
      puts "library: #{lib}"
      puts "topcells: #{topcells.inspect}"
      puts "cells: #{cells.inspect}"
      puts "symbols: #{symbols.inspect}"

#      symbols.each{|sym|
      cells.each{|sym|
        comp = QucsComponent.new sym
        comp.cdraw_comp_in
        @components << comp
      }
      symbols.each{|sym|
        comp = QucsComponent.new sym
        comp.cdraw_comp_in
        @components << comp
        @component_is_symbol[comp] = true
        symbol_info[sym] = comp.symbol
        if sym == 'voltage'
          ['vsin', 'vac', 'vpulse'].each{|s|
            copy = comp.dup 
            copy.name = s
            @components << copy
            @component_is_symbol[copy] = true
            symbol_info[sym] = copy.symbol
          }
        end
      }
    }
    symbol_info
  end
  
  def qucs_lib_in lib_path
    description = extract_qucs_components(File.read(lib_path))
    description.each_pair{|sym, desc|
      @component = QucsComponent.new sym
      @component.qucs_comp_in desc
      @components << @component
    }
  end

  def xschem_lib_in lib_path='circuits.lib'
    Dir.glob('*.sym').each{|sym|
      comp = QucsComponent.new sym.sub '.sym', ''
      comp.xschem_comp_in
      @components << comp
    }
  end

  def eeschema_lib_in lib_path=@lib_name+'.lib'
    description = extract_eeschema_components(File.read(lib_path))
    description.each_pair{|sym, desc|
      @component = QucsComponent.new sym
      @component.eeschema_comp_in desc
      @components << @component
    }
  end

  def qucs_lib_out model_script=nil
    result = {}

    FileUtils.mkdir_p File.dirname(@qucs_lib) unless File.directory? File.dirname(@qucs_lib)
    File.open(@qucs_lib, 'w'){|f|
      f.puts "<Qucs Library 0.0.21 \"#{@lib_name}\">\n"
      @components.each{|comp|
        f.puts "<Component #{comp.name}>\n#{comp.qucs_comp_out @lib_name, model_script}</Component>\n"
        qucs_dir = File.expand_path(File.join(@qucs_lib, '../..'))
        if @component_is_symbol[comp] 
          if ENV['QUCS_DIR']
            result[comp.name] = @qucs_lib.sub(qucs_dir, ENV['QUCS_DIR']) 
          else
            result[comp.name] = @qucs_lib.sub(qucs_dir, '#'+"{ENV['QUCS_DIR']}") 
          end
        end
      }
    }
    result
  end

  def eeschema_lib_out model_script=nil
    result = {}
    FileUtils.mkdir_p @target_dir unless File.directory? @target_dir
    File.open(File.join(@target_dir, @lib_name+'.lib'), 'w'){|f|
      f.puts "EESchema-LIBRARY Version 2.4\n#encoding utf-8\n"
      @components.each{|comp|
        f.puts comp.eeschema_comp_out(@lib_name, model_script)
        result[comp.name] = @lib_name # if @component_is_symbol[comp]
      }
    }
    result
  end

  def xschem_lib_out pictures_dir
    FileUtils.mkdir_p pictures_dir unless File.directory? pictures_dir
    Dir.chdir(pictures_dir){
      @components.each{|comp|
        comp.xschem_comp_out comp.name+'.sym'
      }
    }
  end

  def cdraw_lib_out pictures_dir
    FileUtils.mkdir_p pictures_dir unless File.directory? pictures_dir
    Dir.chdir(pictures_dir){
      @components.each{|comp|
        comp.cdraw_comp_out comp.name+'.asy'
      }
    }
  end

  def extract_qucs_components lines
    desc = {}
    cell = nil
    group = nil
    lines.each_line{|l|
      next if l =~ /<\//
      if l =~ /<Component +(\S+) *>/
        cell = $1
        desc[cell] = {}
      elsif l =~ /<Symbol>/
        group = 'Symbol'
        desc[cell][group] = ''
      elsif l =~ /<Description>/
        group = 'Description'
        desc[cell][group] = ''
      elsif l =~ /<Model>/
        group = 'Model'
        desc[cell][group] = ''
      elsif cell.nil? || group.nil? || desc[cell].nil?
        next
      else
        desc[cell][group] << l
      end
    }
    desc
  end

  def extract_eeschema_components lines
    desc = {}
    cell = nil
    lines.each_line{|l|
      if l =~ /^DEF +(\S+)/
        cell = $1
        desc[cell] = ''
      elsif l =~ /^ENDDEF/
        desc[cell] << l
        cell = nil
      end
      desc[cell] << l if cell
    }
    desc
  end

end

class QucsSymbol
  attr_accessor :id, :cell, :lines, :portsyms, :prefix, :value , :params, :label_pos, :name_pos, :symbol_type

  def initialize cell
    @cell = cell
    @lines = []
    @arcs = []
    @circles = []
    @rectangles = []
    @portsyms = []
    @symbol_type = nil # 'CELL'
  end

  XSCHEM_DEVICE_MAP = {
    res: [:resistor, 'R'],
    cap: [:capacitor, 'C'],
    capa: [:capacitor, 'C'],
    vsource: [:vsource, 'V'],
    voltage: [:vsource, 'V'],
    isource: [:isource, 'I'],
    current: [:isource, 'I'],
    vsvs: [:vcvs, 'E'],
    e: [:vcvs, 'E'],
    PMOS: [:pmos4, 'M'],
    NMOS: [:nmos4, 'M'],
    pmos4: [:pmos4, 'M'],
    nmos4: [:nmos4, 'M']
  }

  XSCHEM_GLOBAL_PROP = {}
  XSCHEM_GLOBAL_PROP[:subcircuit] = <<EOS
format="@name @pinlist @symname"
template="name=x1"
EOS
  XSCHEM_GLOBAL_PROP[:capacitor] = <<EOS
format="@name @pinlist @value m=@m"
tedax_format="footprint @name @footprint 
value @name @value
device @name @device
@comptag"
verilog_ignore=true
template="name=C1
m=1
value=1p
footprint=1206
device=\\"ceramic capacitor\\""
EOS
  XSCHEM_GLOBAL_PROP[:resistor] = <<EOS
format="@name @pinlist @value m=@m"
verilog_format="tran @name (@@P\\\\, @@M\\\\);"
tedax_format="footprint @name @footprint
value @name @value
device @name @device
@comptag"
template="name=R1
value=1k
footprint=1206
device=resistor
m=1
EOS
  XSCHEM_GLOBAL_PROP[:current_probe] = <<EOS
format="@name @pinlist 0"
template="name=Vmeas"
EOS
  XSCHEM_GLOBAL_PROP[:isource] = <<EOS
format="@name @pinlist @value"
template="name=I0 value=1m"
EOS
  XSCHEM_GLOBAL_PROP[:vcvs] = <<EOS
format="@name @pinlist @value"
template="name=F1 vnam=v1 value=1"
EOS
  XSCHEM_GLOBAL_PROP[:diode] = <<EOS
format="@name @pinlist @model area=@area"
template="name=D1 model=D1N914 area=1"
EOS
  XSCHEM_GLOBAL_PROP[:inductor] = <<EOS
format="@name @pinlist @value m=@m"
tedax_format="footprint @name @footprint 
value @name @value
device @name @device
@comptag"
template="name=L1
m=1
value=1n
footprint=1206
device=inductor
EOS
  XSCHEM_GLOBAL_PROP[:nmos4] = <<EOS
format="@spiceprefix@name @pinlist @model w=@w l=@l @extra as=@as ps=@ps ad=@ad pd=@pd m=@m"
template="name=M1 model=nmos w=5u l=0.18u as=0 ps=0 ad=0 pd=0 m=1"
EOS
  XSCHEM_GLOBAL_PROP[:npn] = <<EOS
format="@name @pinlist  @model area=@area"
tedax_format="footprint @name @footprint
device @name @device"
template="name=Q1
model=MMBT2222
device=MMBT2222
footprint=SOT23
area=1"
EOS
  XSCHEM_GLOBAL_PROP[:pmos4] = <<EOS
format="@spiceprefix@name @pinlist @model w=@w l=@l @extra as=@as ps=@ps ad=@ad pd=@pd m=@m"
template="name=M1 model=pmos w=5u l=0.18u as=0 ps=0 ad=0 pd=0 m=1"
EOS
  XSCHEM_GLOBAL_PROP[:pnp] = <<EOS
format="@spiceprefix@name @pinlist @model area=@area"
tedax_format="footprint @name @footprint
device @name @device"
template="name=Q1
model=Q2N2907
device=2N2907
footprint=TO92
area=1"
EOS
  XSCHEM_GLOBAL_PROP[:resistor] = <<EOS
format="@name @pinlist @value m=@m"
verilog_format="tran @name (@@P\\\\, @@M\\\\);"
tedax_format="footprint @name @footprint
value @name @value
device @name @device
@comptag"
template="name=R1
value=1k
footprint=1206
device=resistor
m=1"
EOS
  XSCHEM_GLOBAL_PROP[:switch] = <<EOS
format="@name @@P @@M @@CP @@CM @model"
template="name=S1 model=SWITCH1"
EOS
  XSCHEM_GLOBAL_PROP[:vsource] = <<EOS
format="@name @pinlist @value"
template="name=V1 value=3"
EOS

  CDRAW2QUCS_DIRECTION = {'TOP' => 0, 'RIGHT' => 90, 'BOTTOM' => 180, 'LEFT'=> 270}

  def cdraw_symbol_in
    File.read(@cell+'.asy').encode('UTF-8').gsub('µ', 'u').scrub.each_line{|l|
      if l =~ /SymbolType +(\S+)/
        @symbol_type = $1
      elsif l =~ /LINE +(\S+) +(\S+) +(\S+) +(\S+) +(\S+)/
        @lines << [c2q($2), c2q($3), c2q($4) - c2q($2), c2q($5) - c2q($3)] 
      elsif l =~ /CIRCLE *\S+ *(\S+) *(\S+) *(\S+) *(\S+) */
        @circles << [c2q($1), c2q($2), c2q($3), c2q($4)] 
      elsif l =~ /RECTANGLE *\S+ *(\S+) *(\S+) *(\S+) *(\S+) */
        # @rectangles << [c2q($1), c2q($2), c2q($3), c2q($4)] 
        x1, y1, x2, y2 =  [c2q($1), c2q($2), c2q($3), c2q($4)]
        @lines << [x1, y1, x2-x1, 0]
        @lines << [x2, y1, 0, y2-y1]
        @lines << [x2, y2, x1-x2, 0]
        @lines << [x1, y2, 0, y1-y2]
      elsif l =~ /ARC *\S+ *(\S+) *(\S+) *(\S+) *(\S+) *(\S+) *(\S+) *(\S+) *(\S+) */
        @arcs << [c2q($1), c2q($2), c2q($3), c2q($4), c2q($5), c2q($6), c2q($7), c2q($8)] 
      elsif l =~ /SYMATTR Value +(\S+)/
        @value = $1
      elsif l =~ /SYMATTR Value2 +(\S+)/
        @value2 = $1
      elsif l =~ /SYMATTR Prefix +(\S+)/
#        @prefix = $1.tr('Q', 'T')
        @prefix = $1
      elsif l =~ /PIN +(\S+) +(\S+) +(\S+) +(\S+)/
        @pin = {:xy => [c2q($1), c2q($2)], :angle => CDRAW2QUCS_DIRECTION[$3]} # LEFT, RIGHT, BOTTOM or TOP 
        @portsyms << @pin
      elsif l =~ /PINATTR PinName +(\S+)/
        @pin[:PinName] = $1
      elsif l =~ /PINATTR SpiceOrder +(\S+)/
        @pin[:SpiceOrder] = $1
      elsif l =~ /WINDOW 0 +(\S+) +(\S+)/
        @name_pos = [c2q($1.to_i), c2q($2.to_i)]
      elsif l =~ /WINDOW 3 +(\S+) +(\S+)/
        @label_pos = [c2q($1.to_i), c2q($2.to_i)]
      end
    }
  end

  def qucs_symbol_in desc
    desc && desc.each_line{|l|
      if l =~ /<Line +(\S+) +(\S+) +(\S+) +(\S+)/
        @lines << [q2c($1), q2c($2), q2c($3) + q2c($1), q2c($4) + q2c($2)] 
      elsif l =~ /<Eclipse *(\S+) *(\S+) *(\S+) *(\S+) */
        @circles << [q2c($1), q2c($2), q2c($3) + q2c($1), q2c($4) + q2c($2)] 
      elsif l =~ /<Rectangle *\S+ *(\S+) *(\S+) *(\S+) *(\S+) */
        @rectangles << [q2c($1), q2c($2), q2c($3), q2c($4)] 
      elsif l =~ /EArc *\S+ *(\S+) *(\S+) *(\S+) *(\S+) *(\S+) *(\S+) *(\S+) *(\S+) */
        @arcs << [q2c($1), q2c($2), q2c($3), q2c($4), q2c($5), q2c($6), q2c($7), q2c($8)] 
      elsif l =~ /<\.PortSym +(\S+) +(\S+) +(\S+) +(\S+)/
        @pin = {:xy => [q2c($1), q2c($2)], :SpiceOrder => $3.to_i, :angle => $4}
        @portsyms << @pin
      elsif l=~ /<\.ID 0 0 (\S+)>/
        @prefix = $1
      end
    }
  end

  def eeschema_symbol_in desc
    desc && desc.each_line{|l|
      if l =~ /^S (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+)/
        @rectangles << [e2q($1), e2q($2), e2q($3), e2q($4)] 
        unit = $5; convert = $6; thickness = $7; fill = $8
      elsif l =~ /^P \S+ \S+ \S+ \S+ (\S+) (\S+) (\S+) (\S+)/
        x1 = e2q($1)
        y1 = e2q($2)
        x2 = e2q($3) -x1
        y2 = e2q($4) -y1
        @lines << [x1, y1, x2, y2]
      elsif l =~ /^C (\S+) (\S+) (\S+)/
        x = e2q($1)
        y = -e2q($2)
        r = e2q($3)
        @circles << [x-r, y-r, x+r, y+r]
      elsif l =~ /^X (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+)/
        name = $1; num = $2; posx = $3; posy = $4;
        length = $5; direction = $6; name_text_size = $7;
        num_text_size = $8; unit = $9; convert = $10; electrical_type = $11 # [pin_type]
        @pin = {:xy => [e2q(posx), -e2q(posy)], :SpiceOrder => num} 
        @portsyms << @pin
        case direction
        when 'U'
          @pin[:angle] = 0
        when 'R'
          @pin[:angle] = 90
        when 'D'
          @pin[:angle] = 180
        when 'L'
          @pin[:angle] = 270
        end
      elsif l =~ /^F *0 +"(\S+)" +(\S+) +(\S+) +(\S+)/
        @prefix = $1
        @name_pos = [e2q($2.to_i), -e2q($3.to_i)]
      elsif l =~ /^F *1 +\S+ +(\S+) +(\S+) +(\S+)/
        @label_pos = [e2q($1.to_i), -e2q($2.to_i)]
      end
    }
  end

  def xschem_symbol_in desc
    device, @prefix = XSCHEM_DEVICE_MAP[@cell.to_sym]
    desc && desc.each_line{|l|
      if l =~ /^B \S+ (\S+) (\S+) (\S+) (\S+) {(.*)}/
        label = $5
        x = ($1.to_i+$3.to_i)/2
        y = ($2.to_i+$4.to_i)/2
        if label =~ /pinnumber=(\S+)/
          @pin = {:xy => [x2q(x), x2q(y)], :SpiceOrder => $1.to_i}
          @portsyms << @pin
        else
          @rectangles << [x2q($1), x2q($2), x2q($3), x2q($4)] 
        end
      elsif l =~ /^L \S+ (\S+) (\S+) (\S+) (\S+)/
        x1 = x2q($1)
        y1 = -x2q($2)
        x2 = x2q($3) -x1
        y2 = -x2q($4) -y1
        @lines << [x1, y1, x2, y2]
      elsif l =~ /^A \S+ (\S+) (\S+) (\S+) (\S+) 360 {}/
        x = x2q($1.to_i)
        y = x2q($2.to_i)
        r = x2q($3.to_i)
        s = x2q($4.to_i)
        @circles << [x-r, y-r, x+r, y+r]
      elsif l =~ /^T {@name} (\S+) (\S+)/
        @name_pos = [x2q($1.to_i), x2q($2.to_i)]        
      elsif l =~ /^T {@value} (\S+) (\S+)/
        @label_pos = [x2q($1.to_i), x2q($2.to_i)]        
      elsif l =~ /^T {@symname} (\S+) (\S+)/
        @symbol_type = 'BLOCK'
        @label_pos = [x2q($1.to_i), x2q($2.to_i)]        
      end
    }
  end

  def qucs_symbol_out params=nil
    return '' if @portsyms.size == 0
    if @params = params
#    result = "  <.ID 120 60 #{@prefix||'X'}>\n"
      params = ' ' + @params.map{|p|
        if p[2]
          "\"#{p[1]}=#{p[2]}=#{p[0]}==\""
        else
          "\"#{p[1]}=#{p[0]}===\""
        end
      }.join(' ')
    end
    result = "  <.ID 0 0 #{@prefix||'X'}#{params}>\n"
    @lines.each{|l|
      result << "  <Line #{l.join(' ')} #000080 2 1>\n"
    }
    @rectangles.each{|r|
      x1, y1, x2, y2 = r
      x = [x1, x2].min
      y = [y1, y2].min
      w = (x2 - x1).abs
      h = (y2 - y1).abs
      result << "  <Rectangle #{x} #{y} #{w} #{h} #000000 0 1 #c0c0c0 1 0>\n"
    }
    @arcs.each{|a|
      x1, y2, x2, y1, xa1, ya1, xa2, ya2 = a
      x = [x1, x2].min
      y = [y1, y2].min
      w = (x2 - x1).abs
      h = (y2 - y1).abs

      xc = (x1+x2)/2.0
      yc = (y1+y2)/2.0
      startangle = Math.atan2((ya2-yc), (xa2-xc))
      stopangle = Math.atan2((ya1-yc), (xa1-xc)).to_i
      start = (startangle*180/Math::PI).to_i
      stop = (stopangle*180/Math::PI).to_i
      printf "start: %f, stop: %f\n", start, stop
      
      result << "  <EArc #{x} #{y} #{w} #{h} #{start*16} #{(stop-start)*16} #000000 0 1 #c0c0c0 1 0>\n"
    }
    @circles.each{|c|
      cx1, cy1, cx2, cy2 = c
      x1 = [cx1, cx2].min
      x2 = [cx1, cx2].max
      y1 = [cy1, cy2].min
      y2 = [cy1, cy2].max
      result << "  <Ellipse #{x1} #{y1} #{x2-x1} #{y2-y1} #000000 0 1 #c0c0c0 1 0>\n"
    }
    @portsyms.each{|p|
      result << "  <.PortSym #{p[:xy].join(' ')} #{p[:SpiceOrder]} 0>\n"
    }
    result
  end

  EESCHEMA_SYMBOL_ORIENTATION = {0 => 'U', 90 => 'R', 180 => 'D', 270 => 'L'}

  def eeschema_symbol_orientation p, center = [0.0, 0.0]
    if p[:angle]
      return EESCHEMA_SYMBOL_ORIENTATION[p[:angle]]
    end
    x = q2e(p[:xy][0])
    y = -q2e(p[:xy][1])
    if (x-center[0]).abs > (y-center[1]).abs
      if x-center[0] > 0
        'L'
      else
        'R'
      end
    else
      if y-center[1] > 0
        'D'
      else
        'U'
      end
    end
  end

  def eeschema_symbol_out params=nil
    return '' if @portsyms.size == 0
    result = "DRAW\n"
    @lines.each{|l|
      x1 = q2e(l[0])
      y1 = -q2e(l[1])
      x2 = q2e(l[2]) + x1
      y2 = -q2e(l[3]) + y1  # -(q2e(l[3]) + q2e(l[1]))
      result << "P 2 0 1 0 #{x1} #{y1} #{x2} #{y2} N\n"
    }
    @rectangles.each{|r|
      x1, y1, x2, y2 = r
      #      x = [x1, x2].min
      #      y = [y1, y2].min
      #      w = (x2 - x1).abs
      #      h = (y2 - y1).abs
      result << "S #{q2e(x1)} #{-q2e(y1)} #{q2e(x2)} #{-q2e(y2)} 0 1 0 f\n"
    }
    @arcs.each{|a|
      x1, y2, x2, y1, xa1, ya1, xa2, ya2 = a
      x = [x1, x2].min
      y = [y1, y2].min
      w = (x2 - x1).abs
      h = (y2 - y1).abs

      xc = (x1+x2)/2.0
      yc = (y1+y2)/2.0
      startangle = Math.atan2((ya2-yc), (xa2-xc))
      stopangle = Math.atan2((ya1-yc), (xa1-xc)).to_i
      start = (startangle*180/Math::PI).to_i
      stop = (stopangle*180/Math::PI).to_i
      printf "start: %f, stop: %f\n", start, stop
      
      result << "A #{q2e(x)} #{-q2e(y)} #{q2e([w,h].min/2)} #{start} #{stop} 0 1 0 N #{q2e(xa1)} #{-q2e(ya1)} #{q2e(xa2)} #{-q2e(ya2)}\n"
    }
    @circles.each{|c|
      cx1, cy1, cx2, cy2 = c
      x1 = [cx1, cx2].min
      x2 = [cx1, cx2].max
      y1 = [cy1, cy2].min
      y2 = [cy1, cy2].max
      result << "C #{q2e(x1+x2)/2} #{-q2e((y1+y2)/2)} #{q2e([x2-x1,y2-y1].max/2)} 0 1 0N\n"
    }

    center = [0.0, 0.0]
    @portsyms.each{|p|
      center[0] = center[0] + q2e(p[:xy][0])
      center[1] = center[1] - q2e(p[:xy][1])
    }
    center[0] = center[0]/@portsyms.size
    center[1] = center[1]/@portsyms.size     
    @portsyms.each{|p|
      result << "X #{p[:PinName]||'~'} #{p[:SpiceOrder]} #{q2e(p[:xy][0])} #{-q2e(p[:xy][1])} 25 #{eeschema_symbol_orientation(p, center)} 35 35 1 1 I\n"
    }
    result << "ENDDRAW\n"
  end

  def xschem_symbol_out
    device, prefix = XSCHEM_DEVICE_MAP[@cell.to_sym]
    device = 'subcircuit' if @symbol_type == 'BLOCK'
    device = device.to_sym if device
    result =<<EOS
v {xschem version=2.9.7 file_version=1.1}
G {type=#{device}
#{XSCHEM_GLOBAL_PROP[device]}
}
V {}
S {}
E {}
EOS
    @lines.each{|l|
      x1 = q2x(l[0])
      y1 = q2x(l[1])
      x2 = q2x(l[2]) + x1
      y2 = q2x(l[3]) + y1
      result << "L 4 #{x1} #{y1} #{x2} #{y2} {}\n"
    }
    @rectangles.each{|r|
      result << "B 5 #{r.map{|a| q2x(a)}.join(' ')} {}\n"
    }
    @arcs.each{|a|
      result << "A 3 #{a.map{|a| q2x(a)}.join(' ')} {}\n"
    }
    @circles.each{|c|
      cx1, cy1, cx2, cy2 = c
      x1 = [cx1, cx2].min
      x2 = [cx1, cx2].max
      y1 = [cy1, cy2].min
      y2 = [cy1, cy2].max
      result << "A 3 #{q2x(x1+x2)/2} #{q2x((y1+y2)/2)} #{q2x([x2-x1,y2-y1].max/2)} 0 360 {}\n"
    }
    @portsyms.sort{|a,b| a[:SpiceOrder] <=> b[:SpiceOrder]}.each{|p|
      x, y = p[:xy]
      result << "B 5 #{q2x(x)-2} #{q2x(y)-2} #{q2x(x)+2} #{q2x(y)+2} {name=#{p[:PinName]} dir=in}\n"
      orientation = 0
      case p[:angle]
      when 0
        orientation = 1
        mirror = 1
      when 90
        orientation = 2
        mirror = 0
      when 180
        orientation = 3
        mirror = 0
      when 270
        orientation = 0
        mirror = 0
      end
      result << "T {#{p[:PinName]}} #{q2x(x)} #{q2x(y)} #{orientation} #{mirror} 0.2 0.2 {layer=13}\n"
    }
    if @label_pos 
      label_x = q2x(@label_pos[0])
      label_y = q2x(@label_pos[1])
      result << "T {@value} #{label_x} #{label_y} 0 0 0.20 0.2 {}\n"
    end
    if @name_pos
      name_x = q2x(@name_pos[0])
      name_y = q2x(@name_pos[1])
      result << "T {@name} #{name_x} #{name_y} 0 0 0.2 0.2 {}\n"
      if @symbol_type == 'BLOCK'
        result << "T {@symname} #{name_x} #{name_y + 40} 0 0 0.20 0.2 {}\n"
      end
    end
    result
  end

  def cdraw_symbol_out type='CELL'
    result = "Version 4\nSymbolType #{type}\n"
    xmin = ymin = 1000000000
    xmax = ymax = -1000000000
    @lines.each{|l|
      x1 = q2c(l[0])
      y1 = -q2c(l[1])
      x2 = x1 + q2c(l[2])
      y2 = y1 - q2c(l[3])
      xmin = [xmin, x1, x2].min
      xmax = [xmax, x1, x2].max
      ymin = [ymin, y1, y2].min
      ymax = [ymax, y1, y2].max
      result << "LINE Normal #{x1} #{y1} #{x2} #{y2}\n"
    }
    @rectangles.each{|r|
      result << "RECTANGLE Normal #{r.map{|a| q2c(a).to_s}.join(' ')}\n"
    }
    @arcs.each{|a|
      result << "ARC Normal #{a.map{|a| q2c(a).to_s}.join(' ')}\n"
    }
    @circles.each{|c|
      result << "CIRCLE Normal #{c.map{|a| q2c(a).to_s}.join(' ')}\n"
    }
    if @name_pos && @label_pos
      result << "WINDOW 0 #{q2c @name_pos[0]} #{q2c @name_pos[1]} Left 2\n"
      result << "WINDOW 3 #{q2c @label_pos[0]} #{q2c @label_pos[1]} Left 2\n"
    else
      result << "WINDOW 0 #{(xmin+xmax)/2} #{(ymin+ymax)/2} Left 2\n"
      result << "WINDOW 3 #{(xmin+xmax)/2} #{(ymin+ymax)/2 - 20} Left 2\n"
    end
    # result << "SYMATTR Value #{@prefix}\n"
    # result << "SYMATTR Prefix #{@prefix}\n"
    @portsyms.each{|p|
      result << "PIN #{p[:xy].map{|a| q2c(a).to_s}.join(' ')} NONE 0\n"
      # result << "PINATTR PinName P#{p[:SpiceOrder]}\n" # Pn should be replaced
      result << "PINATTR PinName #{p[:PinName]}\n"
      result << "PINATTR SpiceOrder #{p[:SpiceOrder]}\n"
    }
    result
  end
end

class QucsSchematic
  attr_accessor :cell, :components, :wires, :lines
  def initialize cell, lib_path={}, symbols={}
    @cell = cell
    @lib_path = lib_path
    @symbols = symbols
    @properties = {:View => [0,0,800,800,1,0,0], :Grid => [10,10,1],
      :DataSet => 'test.dat', :DataDisplay => 'test.dpl', :OpenDisplay => 1,
#      :Script => 'test.m', :RunScript => 0,
      :showFrame => 0, 
      :FrameText0 => 'Title', :FrameText1 => 'Drawn By:', 
      :FrameText2 => 'Date:', :FrameText3 => 'Revision:'}
    @wires = []
    @components =[]
    @texts = []
    @lines = [] 
    @lib_info = {}
  end

  def cdraw_schema_in
    # File.open(@cell+'.asc', 'r:Windows-1252').read.encode('UTF-8').gsub(181.chr(Encoding::UTF_8), 'u').scrub.each_line{|l|
    mu = 181.chr(Encoding::UTF_8)
    File.open(@cell+'.asc', 'r:UTF-8').read.gsub(mu, 'u').scrub.each_line{|l|
      if l =~ /WIRE +(\S+) +(\S+) +(\S+) +(\S+)/ 
        @wires << [c2q($1), c2q($2), c2q($3), c2q($4)]
      elsif l =~ /SHEET +(\S+) +(\S+) +(\S+)/ 
        @properties[:View][2] = c2q($2)
        @properties[:View][3] = c2q($3)
      elsif l =~ /FLAG +(\S+) +(\S+) +(\S+)/ # note: CDRAW format is different from LTspice
        x = c2q($1)
        y = c2q($2)
        net_name = $3                        #    not processed here (WIRE names are ignored?)
        @wires << [x, y, x, y, net_name, x, y]
      elsif l =~ /SYMBOL +(\S+) +(\S+) +(\S+) +(\S+)/
#        @component = {:name=>$1.downcase, :x=>c2q($2), :y=>c2q($3), :rotation=>$4} # component name in LTspice must be (converted to) downcase ---> this might be okay for symbols but bad for subckts
        @component = {:name=>$1, :x=>c2q($2), :y=>c2q($3), :rotation=>$4} # so reverted back
        if @component[:name] =~ /(\S+)\\(\S+)/  # like OR1LIB\\PMOS
          @component[:name] = $2
        elsif @component[:name] =~ /(\S+)@(\S+)/  # like PMOS@OR1LIB
          @component[:name] = $1
        end
        @components << @component
      elsif l =~ /SYMATTR +(\S+) +(.*)$/
        @component[:symattr] ||= {}
        @component[:symattr][$1] = $2.chomp
      elsif l =~ /TEXT +(\S+) +(\S+) +(\S+) +(\S+) +(.*)$/
        @component = {:x=>c2q($1), :y=>c2q($2)}
        t3 = $3
        t4 = $4
        text = $5
        if text =~ /!\.tran +(\S*[0-9]+)([^0-9]*)$/
          @component[:name] = '.tran'
          @component[:tstop] = $1 + $2
        elsif text =~ /!\.dc +(\S+) +(\S+) +(\S+) +(\S+)/
          @component[:name] = '.dc'
          @component[:sweep] = $1
          @component[:start] = $2
          @component[:stop] = $3
          @component[:step] = $4
        elsif text =~ /!\.ac +lin +(\S+) +(\S*[0-9]+)([^0-9]*) +(\S*[0-9]+)([^0-9]*)$/
          @component[:name] = '.ac'
          @component[:sweep] = 'lin'
          @component[:npoints] = $1
          @component[:fstart] = $2 + ' ' + $3
          @component[:fstop] = $4 + ' ' + $5
        elsif text =~ /!\.model +(\S+) +([^ (=]+)(.*)$/
          @component[:name] = '.model'
          @component[:model] = $1
          if $2.upcase == 'SW'
            @component[:type] = 'VSWITCH'
          else
            @component[:type] = $2
          end
          @component[:rest] = $3
        elsif text =~ /!\.include +(.*)$/
          @component[:name] = '.include'
          @component[:path] = $1.gsub(/['\"]/,'')
        else
          @texts << [@component[:x], @component[:y], t3, t4, text.chomp]
        end
        @components << @component if @component[:name]
      elsif l =~ /LINE +(\S+) +(\S+) +(\S+) +(\S+) +(\S+)/
        @lines << [c2q($2), c2q($3), c2q($4) - c2q($2), c2q($5) - c2q($3)] 
      end
    }

    @symbol = QucsSymbol.new @cell
    @symbol.cdraw_symbol_in if File.exist?(@cell+'.asy')
    props = {}
    props = YAML.load(File.read(@cell+'.yaml').encode('UTF-8')) if File.exist? @cell+'.yaml'
    @lib_info = props['cells']||{}
    @lib_info['GND'] = 'power'
    @lib_info
  end

  def qucs_schema_in
    desc = extract_qucs_cell(File.read(@cell+'.sch').encode('UTF-8'))
    c = QucsComponent.new @cell
    c.qucs_comp_in desc
    @symbol = c.symbol
    desc['Components'] && desc['Components'].each_line{|c|
      c =~ /<(\S+) +(\S+) +\S+ +(\S+) +(\S+) +0 +0 +(\S+) +(\S+) +"(\S+)" 0 "(\S+)"/
      @component = {:type=> $1, :name=>$8, :x=>q2c($3), :y=>q2c($4), :mirror=>$5.to_i, :rotation=>$6.to_i, :lib_path=>$7, :symmattr => {"InstName" =>$2}}
      @components << @component
    }
    desc['Wires'] && desc['Wires'].each_line{|w|
      w =~ /<(\S+) +(\S+) +(\S+) +(\S+)/ 
      @wires << [q2c($1), q2c($2), q2c($3), q2c($4)]
    }
    desc['Diagrams']
    desc['Paintings']
  end

  def eeschema_schema_in
    desc = extract_eeschema_cell(File.read(@cell+'.sch').encode('UTF-8'))
    #c = QucsComponent.new @cell
    #c.eeschema_comp_in desc
    #@symbol = c.symbol
    desc['Components'] && desc['Components'].each{|lines|
      @component = {:type => 'Lib'}
      lines.each_line{|l|
        if l =~ /^L (\S+):(\S+) (\S+)/ # Simulation_SPICE:VSIN V1
          @component[:lib_path] = $1
          @component[:name] = $2
          @lib_info[@component[:name]] = 'circuits'
          @component[:symattr] = {'InstName'=> $3}
          @component[:type] = 'Lib'
        elsif l =~ /^P (\S+) (\S+)/
          @component[:x] = e2q($1)
          @component[:y] = e2q($2)
        elsif l =~ /F 0 \"(\S+)\" \S+ (\S+) (\S+)/
          @component[:name_pos] = [e2q($2), e2q($3)]
          # @component[:name] = $1 # [:symattr][InstName] already set
        elsif l =~ /F 1 \"(\S+)\" \S+ (\S+) (\S+)/
          @component[:symattr]['Value'] = $1
          @component[:label_pos] = [e2q($2), e2q($3)]
        elsif l =~ /F 5 \"([^\"]*)\"/
          @component[:symattr]['Value2'] = $1
        elsif l =~ /\s*((\S+) (\S+) (\S+) (\S+))/
          case $1
          when '1 0 0 -1' # 'R0'
            @component[:rotation] = 'R0'
          when '0 1 1 0'  # 'R90'
            @component[:rotation] = 'R90' 
          when '-1 0 0 1' # 'R180'
            @component[:rotation] = 'R180'
          when '0 -1 -1 0' # 'R270'
            @component[:rotation] = 'R270' 
          when '-1 0 0 -1' # 'M0'
            @component[:rotation] = 'M0'
          when '0 -1 1 0' # 'M90'
            @component[:rotation] = 'M90' 
          when '1 0 0 1' # 'M180'
            @component[:rotation] = 'M180'
          when '0 1 -1 0' # 'M270'
            @component[:rotation] = 'M270'
          end
        end
      }
      # c =~ /<(\S+) +(\S+) +\S+ +(\S+) +(\S+) +0 +0 +(\S+) +(\S+) +"(\S+)" 0 "(\S+)"/
      # @component = {:type=> $1, :name=>$2, :x=>q2c($3), :y=>q2c($4), :mirror=>$5.to_i, :rotation=>$6.to_i, :lib_path=>$7, :cell_name=>$8}
      @components << @component
    }
    desc['Wires'] && desc['Wires'].each{|w|
      w =~ /(\S+) +(\S+) +(\S+) +(\S+)/ 
      @wires << [e2q($1), e2q($2), e2q($3), e2q($4)]
    }
    desc['Texts'] && desc['Texts'].each{|l|
      l =~ /Text +(\S+) +(\S+) +(\S+) +(\S+) +(\S+) +(\S+) ~ 0\n(.*)$/
      if $1 == 'GLabel'
        @wires << [e2q($2), e2q($3), e2q($2), e2q($3), $7]
      elsif $1 == 'HLabel'
        case $6
        when 'Output'
          inst_name = 'out'
        when 'Input'
          inst_name= 'in'
        when 'BiDi'
          inst_name = 'inout'
        else
          inst_name = nil
        end
        @component = {:type=> 'Port', :name=>inst_name, :x=>e2q($2), :y=>e2q($3), :symattr=>{"InstName" => $7}}
        @components << @component
      else
        @texts << [e2q($2), e2q($3), $4||"0", $5||"50", $6]
      end
    }
    desc['Diagrams']
    desc['Paintings']
  end

  def xschem_schema_in
    @lib_info = {}
    File.read(@cell+'.sch').each_line{|l|
      if l =~ /^N +(\S+) +(\S+) +(\S+) +(\S+)/ #  {lab=(\S+)}/ 
        @wires << [x2q($1), x2q($2), x2q($3), x2q($4)]
      elsif l =~ /^C {(\S+).sym} +(\S+) +(\S+) +(\S+) +(\S+) {(.*)}/
        name = $1
        x = $2
        y = $3
        rotation = $4
        mirror = $5
        properties = $6
        if name == 'lab_pin'
          properties =~ /lab=(\S+)/
          @wires << [x2q(x), x2q(y), x2q(x), x2q(y), $1]
          next
        end
        @lib_info[name] = 'circuits'
        @component = {:type => 'Lib', :name=>$1, :x=>x2q(x), :y=>x2q(y), :rotation=>xschem_in_orientation(rotation, mirror)} 
        if properties =~ /name=(\S+)/
          @component[:symattr] = {"InstName"=>$1}
        end
        if properties =~ /value=\"([^\"]*)\"/
          @component[:symattr]["Value2"] = $1
        elsif properties =~ /value=(\S+)/
          @component[:symattr]["Value"] = $1
        end
        @components << @component
      elsif l =~ /^T +(\S+) +(\S+) +(\S+)/
        text = $1
        @texts << [x2q($2), x2q($3), 0.2, 0.2, text]
      elsif l =~ /^L \S+ +(\S+) +(\S+) +(\S+) +(\S+) +(\S+)/
        @lines << [x2q($2), x2q($3), x2q($4), x2q($5)] 
      end
    }

    if File.exist?(@cell+'.sym')
      @symbol = QucsSymbol.new @cell
      @symbol.xschem_symbol_in 
    else
      @symbol = nil
    end
    props = {}
    props = YAML.load(File.read(@cell+'.yaml').encode('UTF-8')) if File.exist? @cell+'.yaml'
    # @lib_info = props['cells']||{}
    # @lib_info['GND'] = 'power'
    @lib_info
  end

  def qucs_schema_out file
    File.open(file, 'w'){|f|
      f.puts "<Qucs Schematic 0.0.21>\n"
      f.puts "<Properties>\n#{properties}</Properties>\n"
      f.puts "<Symbol>\n#{@symbol.qucs_symbol_out}</Symbol>\n" if @symbol
      f.puts "<Components>\n#{get_components}</Components>\n" if @components
      f.puts "<Wires>\n#{wires}</Wires>\n"
      f.puts "<Diagrams>\n</Diagrams>\n"
      f.puts "<Paintings>\n#{paintings}</Paintings>\n"
    }
  end
    
  def xschem_schema_out file
    File.open(file, 'w'){|f|
      f.puts <<EOS    
v {xschem version=2.9.7 file_version=1.1}
G {}
V {}
S {}
E {}
EOS
      global_pins = []
      @wires.each{|w|
        if w[4] && (w[0] == w[2]) && (w[1] == w[3])
          global_pins << w
        end
      }
      @wires = @wires - global_pins
      index = 0
      global_pins.each{|w|
        f.puts "C {lab_pin.sym} #{q2x(w[0])} #{q2x(w[1])} 0 1 {name=p#{index} lab=#{w[4]}\n}"
        index = index + 1
      }
      index = 0
      @texts.each{|x, y, t3, t4, text|
        if text =~ /^!\./
          attributes="name=s#{index} value=\"#{text[1..-1]}\""
          attributes.sub! '.lib', '.include' # .lib is not supported in ngspice
          f.puts "C {netlist.sym} #{x} #{y} 0 0 {#{attributes}}\n"
        else
          f.puts "Text {#{text}} #{q2x(x)} #{q2x(y)} 0 0 0.4 0.4 {}"
        end
        index = index + 1 
      }
      @components.each{|c|
        x = q2x(c[:x])
        y = q2x(c[:y])
        orientation = xschem_out_orientation(c[:rotation]) || '0 0'
        attributes = c[:symattr] ? "name=#{c[:symattr]['InstName']}" : ''
        if c[:name].start_with? '.'
          case c[:name]
          when '.include', '.lib'
            attributes << "only_toplevel=false value=\".include #{c[:path]}\"\n"
          when '.tran'
            tstep = c[:tstep] || eng2number(c[:tstop])/100.0
            attributes << "only_toplevel=false value=\".tran #{tstep} #{c[:tstop]}\"\n"
          when '.dc'
            attributes << "only_toplevel=false value=\".dc #{c[:sweep]} #{c[:start]} #{c[:stop]} #{c[:step]}\"\n"
          end
          c[:name] = 'code_shown'
        elsif c[:name] == 'voltage'
          # attributes << " lab=#{c[:name]}"
          if value = c[:symattr]['Value'] || c[:symattr]['Value2']
            if value.include? 'type=sine'
              attributes << " value=\"#{get_sine(value)}\""
            else
              attributes << " value=#{value}"
            end
          end
        elsif c[:name] =~ /[io]pin/
          attributes << " lab=#{c[:symattr]['InstName']}" if c[:symattr]
        else
          # attributes << " lab=#{c[:name]}" if c[:name]
          if c[:symattr]
            if value = c[:symattr]['Value']
              if value.include? '='
                attributes << " value=\"#{value}\""
              else
                if c[:symattr]['Value2'] 
                  attributes << " model=#{value}"
                else
                  attributes << " value=#{value}"
                end
              end
            else
              if symbol = @symbols[c[:name]]
                attributes << " model=#{symbol.value}"
              end
            end
            if value2 = c[:symattr]['Value2'] 
              attributes << ' ' + value2
            end
          end
        end
        f.puts "C {#{c[:name]}.sym} #{x} #{y} #{orientation} {#{attributes}}\n"
      }
      @wires.each{|w|
      #      result << "Wire Wire Line\n\t
        f.puts "N #{q2x(w[0])} #{q2x(w[1])} #{q2x(w[2])} #{q2x(w[3])} {}"
      }
    }
  end

  def eeschema_schema_out file
    File.open(file, 'w'){|f|
      xmin = ymin = 10000000
      xmax = ymax = -xmin
      global_pins = []
      @wires.each{|w|
        xmin = [w[0], w[2], xmin].min
        xmax = [w[1], w[3], xmax].max
        if w[4] && (w[0] == w[2]) && (w[1] == w[3])
          global_pins << w
        end
      }
      @wires = @wires - global_pins
      offset = [6000 - ((q2e(xmin)+q2e(xmax))/100)*50, 4100 - ((q2e(ymin)+q2e(ymax))/100)*50]
      f.puts eeschema_schema_header @lib_info.values.uniq
      f.puts eeschema_schema_components offset
      f.puts eeschema_schema_wires offset
      f.puts eeschema_schema_pins global_pins, offset
      f.puts eeschema_schema_texts offset
      f.puts '$EndSCHEMATC'
    }      
  end

  def eeschema_schema_header libraries
<<EOS
EESchema Schematic File Version 4
LIBS:#{libraries.join ' '}
EELAYER 29 0
EELAYER END
$Descr A4 11693 8268
encoding utf-8
Sheet 1 3
Title ""
Date ""
Rev ""
Comp ""
Comment1 ""
Comment2 ""
Comment3 ""
Comment4 ""
$EndDescr
EOS
  end

  def eeschema_schema_components offset
    result = ''
    @components.each{|c|
      next if ['ipin', 'opin', 'iopin'].include? c[:name]
      x = q2e(c[:x])+offset[0]
      y = q2e(c[:y])+offset[1]
      if c[:name].start_with? '.'
        case c[:name]
        when '.include'
          result << "Text Notes #{x} #{y} 0 50 ~ 0\n.include #{c[:path]}\n"
        end
        next
      end
      result << "$Comp\n"
      inst_name = c[:symattr]? c[:symattr]['InstName'] : nil
      component_name = c[:name] 
      component_name = 'GND' if component_name == 'gnd'
      result << "L #{@lib_info[component_name]}:#{component_name} #{inst_name}\n"
      result << "U 1 1 #{format("%x", Time.now).upcase}\n"
      result << "P #{x} #{y}\n"
      label_x, label_y = @symbols[component_name] ? @symbols[component_name].label_pos : [0, 0]
      name_x, name_y = @symbols[component_name]? @symbols[component_name].name_pos : [0, 0]
      flags = (component_name == 'GND') ? '0001' : '0000'
      result << "F 0 \"#{inst_name}\" H #{x+q2e(name_x)} #{y-q2e(name_y)} 50 #{flags} L CNN\n"
      case component_name
      when 'GND'
        result << "F 1 \"#{c[:symattr]['Value']}\" H #{x+q2e(label_x)} #{y - q2e(label_y)} 50 0001 L CNN\n"
      when 'res', 'cap'
        result << "F 1 \"#{c[:symattr]['Value']}\" H #{x+q2e(label_x)} #{y - q2e(label_y)} 50 0000 L CNN\n"
      when 'voltage'
        if c[:symattr]['Value2'] && c[:symattr]['Value2'] =~ /type=sine/ 
          result << "F 1 \"VSIN\" H #{x+q2e(label_x)} #{y - q2e(label_y)} 50 0000 L CNN\n"
          result << "F 2 \"\" H #{x} #{y} 50 0001 L CNN\n"
          result << "F 3 \"~\" H #{x} #{y} 50 0001 L CNN\n"
          result << "F 4 \"Y\" H #{x} #{y} 50 0001 L CNN \"Spice_Netlist_Enabled\"\n"
          result << "F 5 \"V\" H #{x} #{y} 50 0001 L CNN \"Spice_Primitive\"\n"
          result << "F 6 \"#{get_sine c[:symattr]['Value2']}\" H #{x+q2e(label_x)} #{y - q2e(label_y)-11} 50 0000 L CNN \"Spice_Model\"\n"
        else
          result << "F 1 \"#{c[:symattr]['Value']}\" H #{x+q2e(label_x)} #{y - q2e(label_y)} 50 0000 L CNN\n"
        end
      when 'NMOS', 'PMOS'
        result << "F 1 \"#{component_name}\" H #{x+q2e(label_x)} #{y - q2e(label_y)} 50 0000 L CNN\n"
        result << "F 4 \"M\" H #{x} #{y} 50 0001 L CNN \"Spice_Primitive\"\n"
        model = c[:symattr]['Value'] || (@symbols[component_name] && @symbols[component_name].value)
        result << "F 5 \"#{model} #{c[:symattr]['Value2']}\" H #{x} #{y} 50 0001 L CNN \"Spice_Model\"\n"
      else
        result << "F 1 \"#{component_name}\" H #{x+q2e(label_x)} #{y - q2e(label_y)} 50 0000 L CNN\n"
        result << "F 5 \"Y\" H #{x} #{y} 50 0001 L CNN \"Spice_Netlist_Enabled\"\n"     
      end
      result << "\t 1 #{x} #{y}\n"
      result << "\t #{eeschema_orientation c[:rotation]}\n"
      result << "$EndComp\n"
    }
    result
  end

  def get_sine parameters
    params = {}
    parameters.scan(/(\S+)=(\S+)/).map{|a,b| params[a]=b} # like type=sine sinedc=0 ampl=0.1 freq=1k mag=1
    (params['mag'] ? "AC #{params['mag']} " : '') + "sin(#{params['sinedc']} #{params['ampl']} #{params['freq']})"
  end

  def xschem_in_orientation rotation, mirror
    case [rotation, mirror]
      when ['0',  '0']
        'R0'
      when ['1', '0']
        'R90'
      when ['2', '0']
        'R180'
      when ['3', '0']
        'R270'
      when ['0', '1']
        'M0'
      when ['1', '1']
        'M270'
      when ['2', '1']
        'M180'
      when ['3', '1']
        'M90'
      end
  end

  def xschem_out_orientation rotation
    case rotation
      when 'R0'
        '0 0'
      when 'R90'
        '1 0'
      when 'R180'
        '2 0'
      when 'R270'
        '3 0'
      when 'M0'
        '0 1'
      when 'M270'
        '1 1'
      when 'M180'
        '2 1'
      when 'M90'
        '3 1'
      end
  end    

  def eeschema_orientation rotation
=begin
  0.step(270, 90){|p|
    c = Math::cos Math::PI*p/180
    s = Math::sin Math::PI*p/180
    puts "R#{p}: [#{c.to_i}, #{-s.to_i}, #{-s.to_i}, #{-c.to_i}]"
  }
  0.step(270, 90){|p|
    c = Math::cos Math::PI*p/180
    s = Math::sin Math::PI*p/180
    puts "M#{p}: [#{-c.to_i}, #{s.to_i}, #{-s.to_i}, #{-c.to_i}]"
  }
=end  

    case rotation
      when 'R0'
        '1 0 0 -1'
      when 'R90'
        '0 1 1 0'
      when 'R180'
        '-1 0 0 1'
      when 'R270'
        '0 -1 -1 0'
      when 'M0'
        '-1 0 0 -1'
      when 'M90'
        '0 -1 1 0'
      when 'M180'
        '1 0 0 1'
      when 'M270'
        '0 1 -1 0'
      end
  end

  def shifl (wire,n,wirs)
    #  puts "shifl called w/ wire=#{wire.inspect}, n=#{n.inspect}, wirs=#{wirs.inspect}"
    #out=[]
    chng=0
    pnt=wire[n]
    rang=0
    conn=0
    #~ print "########################################"
    #~ print "wire"
    #~ print wire
    #~ print "point"
    #~ print wire(n)
    #~ print "wires"
    #~ print wirs
    for j in wirs do
      if (pnt==j[0]) or (pnt==j[1])
        #~ rang=rang+1
        if (j[0][0]==wire[1][0] and j[0][0]==wire[0][0] and j[1][0]==wire[0][0] and j[1][0]==wire[1][0]) or (j[0][1]==wire[1][1] and j[0][1]==wire[0][1] and j[1][1]==wire[0][1] and j[1][1]==wire[1][1])and (chng==0)
          if wire[1]==j[1]
            wire=[wire[0],j[0]]
          elsif wire[1]==j[0]
            wire=[wire[0],j[1]]
          elsif wire[0]==j[1]
            wire=[wire[1],j[0]]
          elsif wire[0]==j[0]
            wire=[wire[1],j[1]]
          end
          #        puts "** wirs=#{wirs.inspect}, j=#{j.inspect}"
          wirs.delete(j)
          chng=1
        end
      end
    end
    #out.push(chng)
    #out.push(wire)
    #out.push(wirs)
    #out
    [chng, wire, wirs]
  end

  def eeschema_schema_wires offset
    result = ''
    aa=[]
    @wires.each{|w|
      #      result << "Wire Wire Line\n\t#{q2e(w[0])+10000} #{q2e(w[1])} #{q2e(w[2])+10000} #{q2e(w[3])} \n
      ss = "#{q2e(w[0])+offset[0]} #{q2e(w[1])+offset[1]} #{q2e(w[2])+offset[0]} #{q2e(w[3])+offset[1]}"
      coord = ss.split
      aa.push([coord[0..2-1],coord[2..-1]])
    }
#    result
    pts=[]
    cc=[]
    for i in aa
      cc.push(i[0])
      cc.push(i[1])
    end
    for i in cc
      a=cc.count(i)
      if a>2
        pts.push(i) # count the number of nodes
      end
      #    for j in range(a)
      for j in 0..a-1
        cc.delete(i)
      end
    end
    #  puts "aa=#{aa.inspect}"
    a=0
    while a < aa.length - 1
      ind=0
      i=aa[a] # i is wire
      while(ind!=2)
        # p=i[ind] # not used
        #        ost=aa[:a]
        if a==0 # note: aa[:a] in python is not aa[0..a-1] in ruby when a==0 
          ost=[]
        else
          ost=aa[0..a-1]
        end
        #      cc=shifl(i,ind,aa[(a+1)..-1]) # note this cc is different from the above cc 
        #      if cc[0]==0
        #        ind=ind+1
        #      i=cc[1]
        #      ost.push(cc[1])
        #      end
        #      ost=ost+cc[2]
        chng, wire, wirs = shifl(i,ind,aa[(a+1)..-1])
        if chng == 0
          ind = ind + 1
        end
        i=wire
        ost.push wire
        ost = ost + wirs
        aa=ost
        #      puts "> a=#{a} ind=#{ind} aa=#{aa.inspect}"
      end
      a=a+1
    end
    for i in aa
      result << "Wire Wire Line\n"
      # str="\t"+i[0][0]+" "+i[0][1]+" "+i[1][0]+" "+i[1][1]+"\n"
      result << "\t#{i[0][0]} #{i[0][1]} #{i[1][0]} #{i[1][1]}\n"
    end
    for i in pts
      # str="Connection ~ "+i[0]+" "+i[1]+"\n"
      str="Connection ~ #{i[0]} #{i[1]}\n"
      result << str
    end
    result
  end

  def eeschema_schema_pins global_pins, offset
    result = ''
    @components.each{|c|
      x = q2e(c[:x])+offset[0]
      y = q2e(c[:y])+offset[1]
      inst_name = c[:symattr]? c[:symattr]['InstName'] : nil
      case c[:name]
      when 'ipin'
        result << "Text HLabel #{x} #{y} 0 60 Input ~ 0\n#{inst_name}\n"
      when 'opin'
        result << "Text HLabel #{x} #{y} 0 60 Output ~ 0\n#{inst_name}\n"
      when 'iopin'
        result << "Text HLabel #{x} #{y} 0 60 Bidi ~ 0\n#{inst_name}\n"
      end
    }
    global_pins.each{|w|
      x = q2e(w[0])+offset[0]
      y = q2e(w[1])+offset[1]
      pin_name = w[4]
      result << "Text GLabel #{x} #{y} 0 50 Input ~ 0\n#{pin_name}\n"
    }
    result
  end

  def eeschema_schema_texts offset
    result = ''
    @texts.each{|x, y, t3, t4, text|
      result << "Text Notes #{q2e(x)+offset[0]} #{q2e(y)+offset[1]} 0 50 ~ 0\n#{text}\n"
    }
    result
  end

  def cdraw_schema_out pictures_dir
    FileUtils.mkdir_p pictures_dir unless File.directory? pictures_dir
    if @symbol
      File.open(File.join(pictures_dir, @cell+'.asy'), 'w'){|f|
        f.puts @symbol.cdraw_symbol_out 'BLOCK'
      }
    end
    lib_paths = []
    File.open(File.join(pictures_dir, @cell+'.asc'), 'w'){|f|
      f.puts "Version 4\nSHEET #{q2c(@properties[:View][2])} #{q2c(@properties[:View][3])} 1\n" 
      @wires.each{|w|
        f.puts "WIRE #{w.map{|a| q2c(a).to_s}.join(' ')}"
      }
      @components.each{|c|
        if c[:name] && c[:name].downcase == 'gnd' 
          f.puts "FLAG #{q2c(c[:x])} #{q2c(c[:y])} 0"
          next
        end
        name = nil
        case c[:type]
        when 'Port'
          case c[:name]
          when 'in'
            name = 'In'
          when 'out'
            name = 'Out'
          when 'inout'
            name = 'InOut'
          end
          f.puts "FLAG #{q2c(c[:x])} #{q2c(c[:y])} #{c[:symattr]['InstName']}"
          f.puts "IOPIN #{q2c(c[:x])} #{q2c(c[:y])} #{name}" if name
        when 'Lib'
          next if c[:name].nil?
          f.puts "SYMBOL #{c[:name].downcase} #{q2c(c[:x])} #{q2c(c[:y])} #{c[:rotation]}" # component name in LTspice must be (converted to) downcase 
          c[:name_pos] && f.puts("WINDOW 0 #{q2c(c[:name_pos][0]) - q2c(c[:x])} #{q2c(c[:name_pos][1]) - q2c(c[:y])} Left 2")
          c[:label_pos] && f.puts("WINDOW 3 #{q2c(c[:label_pos][0]) - q2c(c[:x])} #{q2c(c[:label_pos][1]) - q2c(c[:y])} Left 2")
          if c[:symattr]
            f.puts "SYMATTR InstName #{c[:symattr]['InstName']}" 
            f.puts "SYMATTR Value #{c[:symattr]['Value']}"
            f.puts "SYMATTR Value2 #{c[:symattr]['Value2']}"
          end
          lib_paths << c[:lib_path]
        when 'Sub'
          f.puts "SYMBOL #{c[:name]} #{q2c(c[:x])} #{q2c(c[:y])} #{c[:rotation]}"
          f.puts "SYMATTR InstName #{c[:name]}"
        else
          
        end
        }
    }
    lib_paths.uniq
  end

  private
  def properties
    result = ''
    @properties.each_pair{|p, v|
      if v.class == Array
        result << " <#{p}=#{v.join(',')}>\n"
      else
        result << " <#{p}=#{v}>\n"
      end
    }
    result
  end

  def get_components
    result = ''
    @components.each{|c|
      if c[:name] == '.tran'
        result << " <.TR TR1 1 #{c[:x]} #{c[:y]} 0 71 0 0 \"lin\" 1 \"0\" 1 \"10 ms\" 1 \"11\" 0 \"Trapezoidal\" 0 \"2\" 0 \"1 ns\" 0 \"1e-16\" 0 \"150\" 0 \"0.001\" 0 \"1 pA\" 0 \"1 uV\" 0 \"26.85\" 0 \"1e-3\" 0 \"1e-6\" 0 \"1\" 0 \"CroutLU\" 0 \"no\" 0 \"yes\" 0 \"0\" 0>\n"
        next
      elsif c[:name] == '.model'
        c[:type] == 'VSWITCH' if c[:type] == 'SW'
        result << " <SpiceModel SpiceModel1 1 #{c[:x]} #{c[:y]} -30 17 0 0 \".MODEL #{c[:model]} #{c[:type]} #{c[:rest]}\" 1 \"\" 0 \"\" 0 \"\" 0 \"Line_5=\" 0>\n"
        next
      elsif c[:name] == '.include'
        result << " <SpiceInclude SpiceInclude1 1 #{c[:x]} #{c[:y]} -36 17 0 0 \"#{c[:path]}\" 1 \"\" 0 \"\" 0 \"\" 0 \"\" 0>\n"
        next
      elsif c[:name] =~ /gnd/
        result << " <GND * 1 #{c[:x]} #{c[:y]} 0 0 0 0>\n"
        next
      elsif c[:name] =~ /pin/
        number = nil
        @symbol.portsyms.each{|p|
          if p[:PinName] == c[:symattr]['InstName']
            number = p[:SpiceOrder]
            break
          end
        }
        direction = find_direction c[:x], c[:y]
        porttype = 'analog'
        case c[:name]
        when 'ipin'
          porttype = 'in'
        when 'opin'
          porttype = 'out'
        when 'iopin'
          porttype = 'inout'
        end
        result << " <Port #{c[:symattr]['InstName']} 1 #{c[:x]} #{c[:y]} 0 0 0 #{direction} \"#{number}\" 1 \"#{porttype}\" 0>\n"
        next
      elsif @lib_info
        if (lib = @lib_info[c[:name]]) && c[:symattr]
          if (c[:lib_path] || @lib_path[c[:name]])
            result << " <Lib #{c[:symattr]['InstName']}"
          else
            result << " <Sub #{c[:symattr]['InstName']}"
          end
        end
      elsif c[:symattr]
        type = c[:symattr]['Prefix']
        type ||= c[:symattr]['InstName'][0,1] 
        result << " <#{type} #{c[:symattr]['InstName']}"
      else
        puts "Error? missing starting line for: c[:name]=#{c[:name]} c[:symattr]=#c[:symattr]"
      end
      result << " 1 #{c[:x]} #{c[:y]} 0 0"
      case c[:rotation]
      when 'R0'
        mirror = 0
        rotation = 0 
      when 'R90'
        mirror = 0
        rotation = 3
      when 'R180'
        mirror = 0
        rotation = 2
      when 'R270'        
        mirror = 0
        rotation = 1
      when 'M0'
        mirror = 1
        rotation = 2
      when 'M90'
        mirror = 1
        rotation = 3
      when 'M180'
        mirror = 1
        rotation = 0
      when 'M270'
        mirror = 1
        rotation = 1
      end
      result << " #{mirror} #{rotation}" 
      if @lib_info && (lib = @lib_info[c[:name]])
        if @lib_path[c[:name]]
          lib_path = @lib_path[c[:name]].sub('.lib', '')
          symbol = @symbols[c[:name]]
          if symbol && symbol.params
            value2, = parse_parameters c[:symattr]['Value2']
            if c[:name] == 'voltage'
              case value2['type']
              when 'sine'
                unless @symbols['vsin']
                  symbol_copy = symbol.dup
                  symbol_copy.cell = 'vsin'
                  symbol_copy.params = [['sinedc', '0'], ['ampl', '1'], ['freq', '1Khz'], ['delay', '0'], ['damp', '0'], ['sinephase', 0]]
                  @symbols['vsin'] = symbol_copy
                end
                c[:name] = 'vsin'
                symbol = @symbols[c[:name]]
              end
            end
            values = symbol.params.map{|p|
              if val = value2[p[0]] || value2[p[0].downcase]
                val.gsub! '{', ''
                val.gsub! '}', ''
              else
                val = c[:symattr]['Value'] # not sure if this is right
              end
              "\"#{val}\" #{p[1] || '0'}"
            }.join(' ')
            result << " \"#{lib_path}\" 0 \"#{c[:name]}\" 0 #{values}>\n"
          else
            result << " \"#{lib_path}\" 0 \"#{c[:name]}\" 0>\n"
          end
        else
          result << " \"\#{ENV['QUCS_DIR']}/#{File.join @lib_info[c[:name]]+'_prj', c[:name]+'.sch'}\" 0>\n"
        end
      else
        result << ">\n"
      end
    }
    result
  end

  def find_direction x, y
    candidate = 0
    @wires.each{|x1, y1, x2, y2|
      if y1 == y2 and y == y1
        return 0 if [x1, x2].min == x
        return 2 if [x1, x2].max == x
        candidate = 1
      end
    }
    @wires.each{|x1, y1, x2, y2|
      if x1 == x2 and x == x1
        return 1 if [y1, y2].max == y
        return 3 if [y1, y2].min == y
        candidate = 0
      end
    }
    candidate
  end
  
  private :find_direction

  def paintings
    result = ''
    #    @rectanges.each{|r|
    #      result << "<Rectangle #{} #{} #{} #{} #000000 0 1 #c0c0c0 1 0>\n"
    #    }
    @lines.each{|l|
      result << "<Line #{l[0]} #{l[1]} #{l[2]} #{l[3]} #000000 0 1>\n"
    }
    @texts.each{|t|
      result << "<Text #{t[0]} #{t[1]} 12 #000000 0 \"#{t[4]}\">\n"
    }
    result
  end

  def wires
    result = ''
    @wires.each{|w|
      result << "<#{w[0]} #{w[1]} #{w[2]} #{w[3]} \"#{w[4]}\" #{w[5]||"0"} #{w[6]||"0"} 0 \"\">\n"
    }
    result
  end

  def extract_qucs_cell lines
    desc = {}
    group = nil
    lines.each_line{|l|
      next if l =~ /<\//
      if l =~ /<Components>/
        group = 'Components'
        desc[group] = ''
      elsif l =~ /<Symbol>/
        group = 'Symbol'
        desc[group] = ''
      elsif l =~ /<Description>/
        group = 'Description'
        desc[group] = ''
      elsif l =~ /<Model>/
        group = 'Model'
        desc[group] = ''
      elsif l =~ /<Wires>/
        group = 'Wires' 
        desc[group] = ''
      elsif l =~ /<Diagrams>/
        group = 'Diagrams'
        desc[group] = ''
      elsif l =~ /<Paintings>/
        group = 'Paintings'
        desc[group] = ''
      elsif desc[group].nil?
        next
      else
        desc[group] << l
      end
    }
    desc
  end

  def extract_eeschema_cell lines
    desc = {'Wires' => [], 'Connection' => [], 'Texts' => []}
    group = nil
    flag_wire = flag_text = false
    lines.each_line{|l|
      if flag_wire
        desc['Wires'] << l
        flag_wire = false
      elsif flag_text
        desc['Texts'][desc['Texts'].size-1] << l
        flag_text = false
      elsif l =~ /^\$Comp/
        group = 'Components'
        desc[group] ||= []
        desc[group][desc[group].size] = ''
      elsif l =~ /^Wire/
        flag_wire = true
      elsif l =~ /^Connection/
        desc['Connection'] << l
      elsif l =~ /^Text/
        desc['Texts'][desc['Texts'].size] = l
        flag_text = true
      elsif desc[group].nil?
        next
      else
        desc[group][desc[group].size-1] << l
      end
    }
    desc
  end
end

def cdraw2target target, pictures_dir, target_dir=File.join(ENV['HOME'], '.qucs'), model_script=nil
  lib_path = {}
  Dir.chdir(pictures_dir){  
    libraries = Dir.glob('*').select{|lib| File.directory? lib}
    symbols = {}
    libraries.each{|lib|
      l = QucsLibrary.new lib, target_dir
      symbols.merge! l.cdraw_lib_in(lib)
      if target == 'qucs'
        lib_path.merge! l.qucs_lib_out(model_script)
      elsif target == 'eeschema'
        lib_path.merge! l.eeschema_lib_out(model_script)
      elsif target == 'xschem'
        l.xschem_lib_out(target_dir)
      end
    }
    if target == 'eeschema'
      eeschema_sym_lib_table lib_path.values.uniq, target_dir
    end
    libraries.each{|lib|
      Dir.chdir(lib){
        cells = Dir.glob('*.asc').map{|a| a.sub('.asc','')}
        cells.delete_if {|c| # delete a fake symbol if it has nothing inside like a 'gnd'
          asc_contents = File.open(c + '.asc', 'r:Windows-1252').read.encode('UTF-8').gsub('?', 'u')
          not asc_contents.include?('SYMBOL') # asc actually had nothing like a 'gnd'
        }
        cells.each{|cell|
          c = QucsSchematic.new cell, lib_path, symbols
          c.cdraw_schema_in
          if target == 'qucs'
            proj_dir = File.join(target_dir, "#{lib}_prj")
            FileUtils.mkdir_p proj_dir unless File.directory? proj_dir
            c.qucs_schema_out File.join(proj_dir, cell + '.sch')
          elsif target == 'eeschema'
            c.eeschema_schema_out File.join(target_dir, cell + '.sch')
          elsif target == 'xschem'
            c.xschem_schema_out File.join(target_dir, cell + '.sch')
          end
        }
      }
    }
  }
end
if $0 == __FILE__
  require '/home/anagix/work/alb2/lib/xschem'
  require '/home/anagix/work/alb2/lib/eeschema'
  require '/home/anagix/work/alb2/lib/lib_util'
=begin
  cdraw2target 'eeschema', '/usr/local/anagix_tools/alb2/public/system/projects/my_amp/cdraw', '/usr/local/anagix_tools/alb2/public/system/projects/my_amp/eeschema'
  cdraw2target 'xschem', '/usr/local/anagix_tools/alb2/public/system/projects/my_amp/cdraw', '/usr/local/anagix_tools/alb2/public/system/projects/my_amp/xschem'
  ENV['QUCS_DIR'] = '/usr/local/anagix_tools/alb2/public/system/projects/my_amp/qucs'
  cdraw2target 'qucs', '/usr/local/anagix_tools/alb2/public/system/projects/my_amp/cdraw', ENV['QUCS_DIR']

  cdraw2target 'xschem', '/usr/local/anagix_tools/alb2/public/system/projects/my_amp/cdraw', '/usr/local/anagix_tools/alb2/public/system/projects/my_amp/xschem'
=end
  cdraw2target 'xschem', '/home/anagix/work/alb2/public/system/projects/amp_machida/cdraw', '/tmp/xschem'
  cdraw2target 'eeschema', '/home/anagix/work/alb2/public/system/projects/amp_machida/cdraw', '/tmp/eeschema'
  cdraw2target 'qucs', '/home/anagix/work/alb2/public/system/projects/amp_machida/cdraw', '/tmp/qucs'
end
