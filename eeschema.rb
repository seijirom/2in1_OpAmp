# Copyright Anagix Corporation 2009-2020

require '/home/anagix/work/alb2/lib/qucs' if $0 == __FILE__

class EEschema
  def get_cells_and_symbols
    symbols = []
    base_props = {}
    Dir.glob('*.lib').each{|lib|
      lib_dir = lib.sub('.lib', '')
      lib_dir = '.'

      Dir.mkdir lib_dir  unless File.directory? lib_dir
      symname = contents = nil
      File.read(lib).each_line{|l|
        if l =~ /DEF (\S+)/
          symname = $1
          symbols << symname
          base_props[symname] = lib.sub('.lib', '')
          contents = l
        elsif l =~ /ENDDEF/
          contents << l
          unless File.exist? sym_file = File.join(lib_dir, symname+'.sym')
            File.open(sym_file, 'w'){|f| f.puts contents}
          end
        else
          contents << l if contents
        end
      }
    }
    cells = Dir.glob("*.sch").map{|a| a.sub('.sch','')}
    [cells, symbols, base_props]
  end

  def search_symbols cell
    symbols = []
    #  File.exist?(cell) && File.read(cell).each_line{|l|
    File.exist?(cell+'.sch') && File.read(cell+'.sch').each_line{|l|
      if l =~ /^L ((\S+):(\S+))/
        symbols << $2
      end
    }
    symbols.uniq
  end
end

class EEschemaComponent < QucsComponent
  attr_accessor :name, :description, :model, :symbol

  def eeschema_comp_in
    @symbol = EEschemaSymbol.new @name
    @symbol.eeschema_symbol_in
  end

  def eeschema_comp_out
    @symbol.eeschema_symbol_out
  end
end

class EEschemaLibrary < QucsLibrary
  attr_accessor :name, :components
  def initialize name, target_dir=File.join(ENV['HOME'], '.qucs')
    @target_dir = target_dir
#    FileUtils.rm_r target_dir if File.directory? target_dir
#    FileUtils.mkdir target_dir
    @lib_name = name
    @components = []
    @component_is_symbol = {}
  end

=begin
  def eeschema_lib_in lib
    symbol_info = {}
    FileUtils.mkdir lib unless File.directory? lib
    Dir.chdir(lib){
      symbols = Dir.glob('*.sym').map{|a| a.sub('.sym','')}
      cells = Dir.glob('*.sch').map{|a| a.sub('.sch','')}
      topcells = cells - symbols
      symbols = symbols - cells
      cells = cells - topcells
      puts "library: #{lib}"
      puts "topcells: #{topcells.inspect}"
      puts "cells: #{cells.inspect}"
      puts "symbols: #{symbols.inspect}"

      cells.each{|sym|
        comp = EEschemaComponent.new sym
        comp.eeschema_comp_in
        @components << comp
      }
      symbols.each{|sym|
        comp = EEschemaComponent.new sym
        comp.eeschema_comp_in
        @components << comp
        @component_is_symbol[comp] = true
        symbol_info[sym] = comp.symbol
      }
    }
    symbol_info
  end
=end  
  def eeschema_lib_in lib
    symbol_info = {}
    Dir.chdir(lib){
      symbols = Dir.glob('*.sym').map{|a| a.sub('.sym','')}
      cells = Dir.glob('*.sch').map{|a| a.sub('.sch','')}
      topcells = cells - symbols
      symbols = symbols - cells
      cells = cells - topcells
      puts "library: #{lib}"
      puts "topcells: #{topcells.inspect}"
      puts "cells: #{cells.inspect}"
      puts "symbols: #{symbols.inspect}"

      cells.each{|sym|
        comp = EEschemaComponent.new sym
        comp.eeschema_comp_in
        @components << comp
      }
      symbols.each{|sym|
        comp = EEschemaComponent.new sym
        comp.eeschema_comp_in
        @components << comp
        @component_is_symbol[comp] = true
        symbol_info[sym] = comp.symbol
      }
    }
    symbol_info
  end

  def eeschema_lib_out model_script=nil
    result = {}
    FileUtils.mkdir_p @target_dir unless File.directory? @target_dir
    File.open(File.join(@target_dir, @lib_name+'.lib'), 'w'){|f|
      f.puts "EESchema-LIBRARY Version 2.4\n#encoding utf-8\n"
      @components.each{|comp|
        result[comp.name] = @lib_name # if @component_is_symbol[comp]
        f.puts comp.eeschema_comp_out
      }
    } unless @components.empty?
    result
  end
end

class EEschemaSymbol <QucsSymbol
  def initialize cell
    super cell
    @desc = nil
  end

  def eeschema_symbol_in 
    if File.exist? @cell+'.sym'
      @desc = File.read(@cell+'.sym').encode('UTF-8')
    end
  end

  def eeschema_symbol_out params=nil
    @desc
  end
end

class EEschemaSchematic <QucsSchematic
  def initialize cell
    @cell = cell
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

  def eeschema_schema_in
    @desc = File.read(@cell+'.sch').encode('UTF-8')
  end

  def eeschema_schema_out file
    File.open(file, 'w'){|f|
      f.puts @desc
    }      
  end
end

def eeschema_sym_lib_table libraries, directory='.'
  File.open(File.join(directory, 'sym-lib-table'), 'w'){|f|
    f.puts '(sym_lib_table'
    libraries.each{|l|
      f.puts "  (lib (name #{l})(type Legacy)(uri ${KIPRJMOD}/#{l}.lib)(options \"\")(descr \"\"))"
    }
    f.puts ')'
  }
end

def alb2eeschema work_dir, eeschema_dir
  puts "alb2eeschema @work_dir=#{work_dir}, eeschema_dir=#{eeschema_dir}"
  Dir.chdir(work_dir){
    libraries = Dir.glob('*')
    libraries.each{|lib|
      l = EEschemaLibrary.new lib, eeschema_dir
      l.eeschema_lib_in(lib)
      l.eeschema_lib_out
    }
    libraries.each{|lib|
      Dir.chdir(lib){
        cells = Dir.glob('*.sch').map{|a| a.sub('.sch','')}
        cells.each{|cell|
          c = EEschemaSchematic.new cell
          c.eeschema_schema_in
          c.eeschema_schema_out File.join(eeschema_dir, cell + '.sch')
        }
      }
    }
    eeschema_sym_lib_table libraries, eeschema_dir 
  }
end

def eeschema2cdraw eeschema_dir, cdraw_dir
  puts "eeschema2cdraw @eeschema_dir=#{eeschema_dir}, cdraw_dir=#{cdraw_dir}"  
  FileUtils.rm_r cdraw_dir if File.directory? cdraw_dir ; FileUtils.mkdir cdraw_dir

  Dir.chdir(eeschema_dir){
    symbols = {}
    Dir.glob('*.lib').each{|lib|
      #l = EEschemaLibrary.new lib, eeschema_dir
      l = QucsLibrary.new lib, eeschema_dir
      
      symbols.merge! l.eeschema_lib_in(lib)
      l.cdraw_lib_out cdraw_dir
    }
    Dir.glob('*.sch').each{|sch_file|
      c = QucsSchematic.new sch_file.sub('.sch', '')
      c.eeschema_schema_in 
      c.cdraw_schema_out cdraw_dir
    }
  }
end
    
def eeschema2qucs eeschema_dir, qucs_dir=File.join(ENV['HOME'], '.qucs'), model_script=nil
  puts "eeschema2qucs eeschema_dir=#{eeschema_dir}, qucs_dir=#{qucs_dir}, "
  Dir.chdir(eeschema_dir){
    puts "eeschema2qucs @pwd=#{Dir.pwd}"
    symbols = {}
    libraries = Dir.glob('*.lib').map{|a| a.sub('.lib', '')}  # PTS06LIB.lib, circuis.lib, power.lib
    libraries.each{|lib|
      l = QucsLibrary.new lib, qucs_dir
      symbols.merge! l.eeschema_lib_in
      l.qucs_lib_out
    }
    proj_dir = File.join(qucs_dir, "circuits_prj")
    cells = Dir.glob('*.sch').map{|a| a.sub('.sch','')}
    cells.each{|cell|
      c = QucsSchematic.new cell
      c.eeschema_schema_in
      FileUtils.mkdir_p proj_dir unless File.directory? proj_dir
      c.qucs_schema_out File.join(proj_dir, cell + '.sch')
    }
  }
end

def eeschema2xschem eeschema_dir, xschem_dir
  puts "eeschema2xschem @eeschema_dir=#{eeschema_dir}, xschem_dir=#{xschem_dir}"
  FileUtils.rm_r xschem_dir if File.directory? xschem_dir ; FileUtils.mkdir xschem_dir  
  Dir.chdir(eeschema_dir){
    puts "eeschema2xschem @pwd=#{Dir.pwd}"
    symbols = {}
    libraries = Dir.glob('*.lib').map{|a| a.sub('.lib', '')}  # PTS06LIB.lib, circuis.lib, power.lib
    libraries.each{|lib|
      l = QucsLibrary.new lib, xschem_dir
      symbols.merge! l.eeschema_lib_in
      l.xschem_lib_out xschem_dir
    }
    Dir.glob('*.sch').each{|sch_file|
      c = QucsSchematic.new sch_file.sub('.sch', '')
      c.eeschema_schema_in 
      c.xschem_schema_out File.join(xschem_dir, sch_file)
    }
  }
end

if $0 == __FILE__
#  current = EEschema.new
#  current.get_cells_and_symbols # run eeschema.rb in the eeschama directory
  eeschema2cdraw '/usr/local/anagix_tools/alb2/public/system/projects/my_amp/eeschema', '/usr/local/anagix_tools/alb2/public/system/projects/my_amp/eeschema2cdraw'
  ENV['QUCS_DIR'] = '/usr/local/anagix_tools/alb2/public/system/projects/my_amp/eeschema2qucs'
  eeschema2qucs '/usr/local/anagix_tools/alb2/public/system/projects/my_amp/eeschema', '/usr/local/anagix_tools/alb2/public/system/projects/my_amp/eeschema2qucs'

end

