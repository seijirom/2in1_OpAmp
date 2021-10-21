# coding: utf-8
# altactl v0.1 Copyright(C) Anagix Corporation
lib_path = File.dirname __FILE__
$:.unshift lib_path
$:.unshift '.'
# $alb=nil # set if minitest exist and want to run standalone (=w/o ALB/ALTA) 
#if $alb.nil?
$:.unshift File.join(lib_path, '../ade_express')
require 'byebug'
require 'fileutils'
require 'optparse'
#require 'lib_util'
#require 'alb_lib'
require 'alta'
#end
load 'ltspctl.rb'
load 'qucsctl.rb'
load 'ngspctl.rb' unless /mswin32|mingw/ =~ RUBY_PLATFORM
=begin
#files to load:
compact_model.rb
ltspice.rb
altactl.rb
ltspctl.rb
xyce.rb
alb_lib.rb
postprocess.rb
qucs.rb
ngspctl.rb
lib_util.rb
alta.rb
xschem.rb
spice_parser.rb
qucsctl.rb
=end

minitest = File.join(lib_path, '..', 'minitest', 'minitest_common.rb')
begin
  load minitest if File.exist? minitest
rescue => error
  puts error
end

if /mswin32|mingw/ =~ RUBY_PLATFORM && ENV['APPDATA']
  $alb_dir ||= ENV['ALBDATA'] || File.join(ENV['APPDATA'], 'ALB')
else
  $alb_dir ||= File.expand_path(File.join(ENV['HOME'], 'ALBDATA'))
end

def get_cwd
  desc= $alb.desc
  if desc['job_id']
    File.join $alb_dir, desc['job_id']
  end
end

def get_testbench name=$alb.desc['testbench']
  data_type, sch, sym, symbol_line = get_data_type $alb.desc['editor']
  File.join get_cwd(), name + sch
end

def get_cell name=$alb.desc['cell']
  data_type, sch, sym, symbol_line = get_data_type $alb.desc['editor']
  File.join get_cwd(), name + sch
end

def expand cells, c
  puts "expand #{c.file} w/ cells: #{cells.inspect}" if c
  c && c.elements.each_pair{|k, v|
    if k =~ /^[Xx]/
      cell_name = v[:type].tr('@-', '__')
      cell_name = 'a' + cell_name if cell_name =~ /^\d/ # if cell name starts with digits
      d = LTspiceControl.new get_cell(v[:type])
      eval "$#{cell_name} = d"
      cells << '$'+cell_name
      expand cells, d if d.elements
    end
  }
end

def alta_connect
  cell = $alb.desc['testbench'] || $alb.desc['cell']
  wd = get_cwd()
  return unless File.directory? wd
  data_type, sch, sym, symbol_line = get_data_type $alb.desc['editor']
  return if cell.nil? 
  asc_file = File.join wd, cell + sch
  return unless File.exist? asc_file
  c = QucsControl .new asc_file if data_type == 'qucs'
  c = LTspiceControl.new asc_file if data_type == 'ltspice'
  cells = ['$'+ cell]
  eval "#{cells[0]} = c"
  expand cells, c
  puts "You can access: #{cells.inspect}"
  cells
end

def alta_close
  result = command "alta_kill(#{$alb.desc[:pid]})"
end

def alta_upload
  result = command "alta_upload"
end

$pos = { {l: 1e-5, w: 1e-4} => 'A',
         {l: 6e-6, w: 1e-4} => 'G',
         {l: 4e-6, w: 1e-4} => 'M',
         {l: 1e-5, w: 3e-5} => 'S',
         {l: 4e-6, w: 3e-5} => 'Y',
         {l: 6e-6, w: 3e-5} => 'AE',
         {l: 1e-5, w: 1.4e-5} => 'AK',
         {l: 6e-6, w: 1.4e-5 } => 'AQ',
         {l: 4e-6, w: 1.4e-5 } => 'AW' }

def excel_index a1ColNum # like 'AZ' to index conversion
  base10Num = 0;
  (0..a1ColNum.length-1).each{|i|
    base10Num = base10Num + (a1ColNum[a1ColNum.length-1-i].ord - ('A'.ord) +1) * (26**i)
  }
  base10Num;
end
  
def xslread_id_vds id_vds_file='actsim_r01_181123.xlsx', sheet='nmos_IDVD', size
  require 'daru'
  require 'roo'
  stepvar='vgs'
  xlsx = Roo::Excelx.new(id_vds_file)
  idvd = xlsx.sheet(sheet)
  pos = excel_index $pos[size]
  
  row = 9
  df = nil
  indices = [0]
  0.4.step(2, 0.4){|vg|
    vds = []
    id = []
    # puts "vg = #{vg}"
    0.05.step(3, 0.05){|vd|
      # puts idvd.cell(row, pos), idvd.cell(row, pos+1)
      vds << idvd.cell(row, pos)
      id << idvd.cell(row, pos+1)
      row = row + 1
    }
    df = setdf(vg, df, vds, id, nil, stepvar)
    indices << indices.size
    row = row + 1
  }
  [df, indices]
end

def xslread_pmos_id_vds id_vds_file='actsim_r01_181123.xlsx', sheet='pmos_IDVD', size
  require 'daru'
  require 'roo'
  stepvar='vgs'
  xlsx = Roo::Excelx.new(id_vds_file)
  idvd = xlsx.sheet(sheet)
  pos = excel_index $pos[size]
  
  row = 9
  df = nil
  indices = [0]
  -0.4.step(-2, -0.4){|vg|
    vds = []
    id = []
    # puts "vg = #{vg}"
    -0.05.step(-3, -0.05){|vd|
      # puts idvd.cell(row, pos), idvd.cell(row, pos+1)
      vds << idvd.cell(row, pos)
      id << idvd.cell(row, pos+1)
      row = row + 1
    }
    df = setdf(vg, df, vds, id, nil, stepvar)
    indices << indices.size
    row = row + 1
  }
  [df, indices]
end

def xslread_id_vgs id_vds_file='actsim_r01_181123.xlsx', sheet='nmos_IDVD', size
  require 'daru'
  require 'roo'
  stepvar='vgs'
  xlsx = Roo::Excelx.new(id_vds_file)
  idvd = xlsx.sheet(sheet)
  pos = excel_index $pos[size]
  
  row = 9
  df = nil
  indices = [0]
  vgs = []
  id = []
  # puts "vg = #{vg}"
  -1.5.step(2, 0.02){|vg|
    # puts idvd.cell(row, pos), idvd.cell(row, pos+1)
    vgs << idvd.cell(row, pos)
    id << idvd.cell(row, pos+1)
    row = row + 1
  }
  df = Daru::DataFrame.new({vgs: vgs, id: id})
  indices << indices.size
  [df, indices]
end

def csvread_id_vds id_vds_file, stepvar='vgs'
  require 'daru'
  vgs = nil
  df = nil
  vds = []
  id1 = []
  id2 = []
  indices = [0]
  File.open(id_vds_file){|f|
    header = f.gets.split(',')
    prev = -1e36
    while line= f.gets
      # puts line
      cols = line.split(',')
      ary = cols.map{|a| a.to_f}
      vgs = ary[2]
      if ary[0] < prev
        df = setdf vgs, df, vds, id1, id2, stepvar
        indices << indices.size
        indices << indices.size        
        vds = []
        id1 = []
        id2 = []
      end
      vds << ary[1]
      id1 << ary[3]
      id2 << ary[4]
      prev = ary[1]
    end
  }
  df = setdf vgs, df, vds, id1, id2, stepvar
  indices << indices.size
  indices << indices.size        
  [df, indices]
end
alias :csvread_id_vgs :csvread_id_vds

def setdf vgs, df, vds, id1, id2, stepvar
  if df.nil?
    df = Daru::DataFrame.new({vds: vds, "id1@#{stepvar}=#{vgs.round(4)}".to_sym => id1})
    df["id2@#{stepvar}=#{vgs.round(4)}".to_sym] = id2 if id2
  else
    df["id1@#{stepvar}=#{vgs.round(4)}".to_sym] = id1
    df["id2@#{stepvar}=#{vgs.round(4)}".to_sym] = id2 if id2
  end
  df
end
private :setdf

def traces_from_df df, indices, trace_names=[], skip=[0, 0]
  xskip, yskip = skip.is_a?(Array) ? skip : [skip, 0]
  x = df[indices[0]]
  xdata = 0.step(x.size-1, xskip+1).map{|i| x[i]}
  traces = []
#  indices[1..-1].each_with_index{|i, n|
  1.step(indices.size-1, 1 + yskip){|n|
    i = indices[n]
    y = df[i]
    y_name = trace_names[n] || y.name
    traces << {x: xdata, y: 0.step(x.size-1, xskip+1).map{|j| y[j]}, mode: 'markers', name: y_name}
  }
  traces
end

def display imgfile
  type = File.extname(imgfile)[1..-1]
  if imgfile.downcase.start_with? 'http'
    require 'open-uri'
    img = URI.parse(imgfile).read 
  else
    img = File.read(imgfile)
  end
  IRuby.display img, mime: "image/#{type}"
  nil
end

def help
  puts "help:"
  puts " help --- show this message"
  puts " get_cwd --- show Current Working Directory"
  puts " alta_connect --- connect to ALTA session"
  puts " get_testbench --- show top level testbench"
  puts " get_cell --- show top level cell"
  puts " alta_close --- close ALTA session"
  puts " alta_upload --- upload current ALTA session to ALB"
end

load './customize.rb' if File.exist? './customize.rb'

if $alb
  if get_cwd()
#    cells = alta_connect
  else
    puts "After opening the circuit from ALTA, please execute 'alta_connect'."
  end
end
