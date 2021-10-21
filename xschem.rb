# Copyright Anagix Corporation 2009-2020

require '/home/anagix/work/alb2/lib/qucs' if $0 == __FILE__

class Xschem
  def get_cells_and_symbols
    symbols = Dir.glob("*.sym").map{|a| a.sub('.sym','')}
    cells = Dir.glob("*.sch").map{|a| a.sub('.sch','')}
    [cells, symbols]
  end

  def search_symbols cell
    symbols = []
    File.exist?(cell+'.sch') && File.read(cell+'.sch').each_line{|l|
      if l =~ /^C {(\S+)\.sym}/
        symbols << $1
      end
    }
    symbols.uniq
  end
end

class XschemComponent < QucsComponent
  attr_accessor :name, :description, :model, :symbol

  def xschem_comp_in
    @symbol = XschemSymbol.new @name
    @symbol.xschem_symbol_in
  end
end

class XschemLibrary < QucsLibrary
  attr_accessor :name, :components
  def initialize name
    @lib_name = name
    @components = []
    @component_is_symbol = {}
  end

  def xschem_lib_in lib
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
        comp = XschemComponent.new sym
        comp.xschem_comp_in
        @components << comp
      }
      symbols.each{|sym|
        comp = XschemComponent.new sym
        comp.xschem_comp_in
        @components << comp
        @component_is_symbol[comp] = true
        symbol_info[sym] = comp.symbol
      }
    }
    symbol_info
  end
end

class XschemSymbol <QucsSymbol
  def initialize cell
    super cell
    @desc = nil
  end

  def xschem_symbol_in 
    if File.exist? @cell+'.sym'
      @desc = File.read(@cell+'.sym').encode('UTF-8')
    end
  end

  def xschem_symbol_out params=nil
    @desc
  end
end

class XschemSchematic <QucsSchematic
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

  def xschem_schema_in
    @desc = File.read(@cell+'.sch').encode('UTF-8')
  end
  
  def xschem_schema_out file
    File.open(file, 'w'){|f|
      f.puts @desc
    }      
  end
end

def alb2xschem work_dir, xschem_dir
  Dir.chdir(work_dir){
    libraries = Dir.glob('*')
    libraries.each{|lib|
      l = XschemLibrary.new lib
      l.xschem_lib_in(lib)
      l.xschem_lib_out xschem_dir
    }
    libraries.each{|lib|
      Dir.chdir(lib){
        cells = Dir.glob('*.sch').map{|a| a.sub('.sch','')}
        cells.each{|cell|
          c = XschemSchematic.new cell
          c.xschem_schema_in
          c.xschem_schema_out File.join(xschem_dir, cell + '.sch')
        }
      }
    }
  }
end

def xschem2cdraw xschem_dir, cdraw_dir
  puts "xschem2cdraw xschem_dir=#{xschem_dir}, cdraw_dir=#{cdraw_dir}"
  Dir.chdir(xschem_dir){
    Dir.glob('*.sym').each{|sym|
      # c = XschemComponent.new sym.sub('.sym', '')
      c = QucsComponent.new sym.sub('.sym', '')
      c.xschem_comp_in
      # FileUtils.rm_r cdraw_dir; FileUtils.mkdir cdraw_dir
      c.cdraw_comp_out File.join(cdraw_dir, c.name+'.asy')
    }
    Dir.glob('*.sch').each{|sch_file|
      # c = XschemSchematic.new sch_file.sub('.sch', '')
      c = QucsSchematic.new sch_file.sub('.sch', '')
      c.xschem_schema_in 
      c.cdraw_schema_out cdraw_dir
    }
  }
end
    
def xschem2qucs xschem_dir, qucs_dir=File.join(ENV['HOME'], '.qucs'), model_script=nil
  puts "xschem2qucs xschem_dir=#{xschem_dir}, qucs_dir=#{qucs_dir}" 
  Dir.chdir(xschem_dir){
    l = QucsLibrary.new 'circuits', qucs_dir
    l.xschem_lib_in
    l.qucs_lib_out

    proj_dir = File.join(qucs_dir, "circuits_prj")
    cells = Dir.glob('*.sch').map{|a| a.sub('.sch','')}
    cells.each{|cell|
      c = QucsSchematic.new cell
      c.xschem_schema_in
      FileUtils.mkdir_p proj_dir unless File.directory? proj_dir
      c.qucs_schema_out File.join(proj_dir, cell + '.sch')
    }
  }
end


if $0 == __FILE__
#  current = Xschem.new
#  current.get_cells_and_symbols # run xschem.rb in the xschem directory
  xschem2cdraw '/usr/local/anagix_tools/alb2/public/system/projects/my_amp/xschem', '/usr/local/anagix_tools/alb2/public/system/projects/my_amp/xschem2cdraw'
  ENV['QUCS_DIR'] = '/usr/local/anagix_tools/alb2/public/system/projects/my_amp/xschem2qucs'  
  xschem2qucs '/usr/local/anagix_tools/alb2/public/system/projects/my_amp/xschem', '/usr/local/anagix_tools/alb2/public/system/projects/my_amp/xschem2qucs'
end

