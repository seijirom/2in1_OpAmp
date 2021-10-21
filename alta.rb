# -*- coding: utf-8 -*-
def YAML_update(lib_dir, name, lib_name)
  Dir.chdir(lib_dir){
    data_type, sch, sym, symbol_line = get_data_type()    
    unless (lib_dir != '.') || ['circuits', 'symbols'].include?(lib_name) || File.exist?(tr(name)+sch) # bug fix 2018/9/25
      name = name + '@' + lib_name
    end

    yaml_file = name + '.yaml'
    props = {}
    if properties = YAML.load(self.properties || '')
      props = properties['cells']
    end
#    if File.exist?(yaml_file) # && File.stat(yaml_file).mtime >= File.stat(asc_file).mtime
#      props = YAML.load(File.read(yaml_file).encode('UTF-8'))
#    end
#    return props if File.stat(yaml_file).mtime >= File.stat(asc_file).mtime
    asc_file = name + sch
    flag = false
    File.open(asc_file, 'r:Windows-1252').read.encode('UTF-8', invalid: :replace).each_line{|l|
#    File.read(asc_file).each_line{|l|
      if l =~ /#{symbol_line}/
        symbol = $1
        library = lib_name
        puts "symbol=#{symbol}"
        if symbol =~ /(\S+)@(\S+)/
          symbol, library = [$1, $2]     # like inv1@OR1_StdCells
        elsif symbol =~ /(\S+)\\\\(\S+)/ ||# like OR1LIB\\NMOS
              symbol =~ /(\S+):(\S+)/
          puts symbol
          library, symbol = [$1, $2]
        else
          if File.exist? symbol + sch
            # library = 'circuits'
          else
            library = 'symbols'
          end
        end
        next if ['ipin', 'opin', 'iopin', 'pad', 'spad'].include? symbol # pins are not cells v1.51y
        next if props && props['cells'] && props['cells'][symbol]
        props ||= {}
        props['cells'] ||= {}                # new device or cell
        props['cells'][symbol] = library
        puts "#{symbol} added to props['cells']"
        flag = true

        create_yaml_file symbol, library, sch, symbol_line
      end
    }
    if flag
      if File.exist? yaml_file
        puts "YAML file '#{yaml_file}' updated for library=#{library}"
      else
        puts "YAML file '#{yaml_file}' created for library=#{library}"
      end
      File.open(yaml_file, 'w'){|f| f.puts props.to_yaml}
    end
    props
  }
end
      
def create_yaml_file cell_name, lib_name, sch, symbol_line
  asc_file = cell_name + sch
  yaml_file = cell_name + '.yaml' 
  return unless File.exist? asc_file # devices do not need yaml file
  return if File.exist?(yaml_file) && File.stat(yaml_file).mtime >= File.stat(asc_file).mtime
  props = {}
  props['cells'] = {}
  data_type, = get_data_type()
  current = data_type_to_class data_type
  children = current.search_symbols(cell_name+sch)
  children.each{|cell|
#    lib = base_props[cell] || symbols.include?(cell) ? 'symbols' : library_name
    props['cells'][cell] = lib_name
#    base_props[cell] = lib_name
    create_yaml_file cell, lib_name, sch, symbol_line
  }
  File.open(yaml_file, 'w'){|f| f.puts props.to_yaml}
end

def extract_control_and_modify cell
  return nil unless get_schematic_view(cell, 'ltspice') =~ /^SHEET \d+ \d+ \d+\r*$/
  schematic_view = ''
  text = ''
  control = ''
  get_schematic_view(cell, 'ltspice').each_line{|l|
    if l =~ /TEXT .*!(.*)$/
      ctrl_lines = $1.split('\n')
      ctrl_lines.each{|ctrl|
        unless ctrl.start_with? '*' # discard comments
          control << '* ' if ctrl.downcase =~ /\.include/
          control << ctrl + "\n"
        end
      }
      text << l
    else
      schematic_view << l
    end
  }
  return nil if control == ''
  set_schematic_view(cell, 'ltspice', schematic_view)
  cell.save!
  [control, text]
end

def extract_control cell
  control = ''
  get_schematic_view(cell, 'ltspice').each_line{|l|
    if l =~ /TEXT .*!(.*)$/
      ctrl_lines = $1.split('\n')
      ctrl_lines.each{|ctrl|
        unless ctrl.start_with? '*' # discard comments
          control << '* ' if ctrl.downcase =~ /\.include/
          control << ctrl + "\n"
        end
      }
    end
  }
  return nil if control == ''
  control
end
private :extract_control_and_modify, :extract_control 

def is_circuit? c
  if File.exist?(c + '.asc') # c is just a symbol
    asc_contents = File.open(c + '.asc', 'r:Windows-1252').read.encode('UTF-8', invalid: :replace)
    asc_contents.include? 'SYMBOL' # asc actually had nothing like a 'gnd'
  end
end

private :is_circuit?

def data_type_to_class data_type
  case data_type
  when 'ltspice'
    LTspice.new
  when 'qucs'
    QUCS.new
  when 'eeschema'
    EEschema.new
  when 'xschem'
    Xschem.new
  end
end

def alta_children project, cell_name, lib_name = nil
  result = []
  if File.exist?(yaml_file = File.join(lib_name||'.', cell_name+'.yaml'))
    children = (YAML.load(File.read(yaml_file).encode('UTF-8'))||{})['cells']
    children && children.each_pair{|c, lib|
      child = File.join(lib_name ? lib : '.', c)
      raise "#{c} symbol does not exist under '#{lib}'" unless File.exist? child + '.asy'
      next unless is_circuit?(child)
      library = project.libraries.find_by_name lib
      cell = library.cells.find_by_name c
      result << cell
    }
  else
    base_props = ((YAML.load(project.properties||'')||{})['cells'])||{}
    Dir.chdir(lib_name&&File.directory?(lib_name) ? lib_name : '.'){
      data_type, sch, sym, symbol_line_pattern = get_data_type()
      current = data_type_to_class data_type
      symbols = current.search_symbols cell_name+'.asc'
      symbols.each{|c|
        next unless is_circuit?(c)
        lib = base_props[c] || lib_name
        library = project.libraries.find_by_name lib
        if library && cell = library.cells.find_by_name(c)
          result << cell
        end
      }
    }
  end
  result
end

def get_data_type type=nil
  if ['qucs', 'ltspice', 'eeschema', 'xschem'].include? type
    data_type = type
  elsif File.exist? 'data_type'
    data_type = File.read('data_type').strip
  elsif File.directory?('user_lib')
    data_type = 'qucs'
  elsif Dir.glob('*.asc').size > 0
    data_type = 'ltspice'
  elsif File.exist?('sym-lib-table') || Dir.glob('*.sch').size + Dir.glob('*.lib').size > 0
    data_type = 'eeschema'
  else
    data_type = 'xschem'
  end

  case data_type
  when 'ltspice'
    sym = '.asy'
    sch = '.asc'
    symbol_line = 'SYMBOL +(\S+) +'
  when 'qucs'
    sym = '.sym'
    sch = '.sch'
    symbol_line = '<Sub \S+ \S+ \S+ \S+ \S+ \S+ \S+ \S+ \"(\S+)\.sch\"'
  when 'eeschema', 'xschem'
    sym = '.sym'
    sch = '.sch'
    symbol_line = '^L ((\S+):(\S+))'
  end
  [data_type, sch, sym, symbol_line]
end

def check_data_type obj, first_choice, preferences = ['ltspice', 'qucs', 'xschem', 'eeschema']
  preferences = [first_choice] + (preferences - [first_choice])
  if obj.class == Library
    data_type = check_data_type_sub obj.cells.first, preferences
  elsif obj.class == Cell
    data_type = check_data_type_sub obj, preferences
  elsif obj.class == Testbench
    if get_schematic_view(obj, 'ltspice').blank?
      data_type = check_data_type_sub obj.instance.cell, preferences
    else
      data_type = 'ltspice'
    end
  end
  data_type
end

def check_data_type_sub obj, preferences
  preferences.find{|s| !get_schematic_view(obj, s).blank?} || preferences.first
end

# include Alta

def gather_ckt_data cells=nil, symbol_lib_path = File.join(ENV['HOME'], 'ドキュメント/LTspiceXVII/lib/sym')
  data_type, sch, sym, symbol_line_pattern = get_data_type()
  current = data_type_to_class data_type
  if cells.nil?
    cells, symbols = current.get_cells_and_symbols
  end
  lib_symbols = cells.map{|c| current.search_symbols c}.flatten.uniq
  symbols.concat lib_symbols

  topcells = cells - symbols
  topcells.delete_if{|cell| File.exist? cell+sym}
  symbols = symbols - cells
  # symbols.delete_if{|cell| File.exist?(cell+'.asc')  && cells << cell}
  cells = cells - topcells
  puts "topcells: #{topcells.inspect}"
  puts "cells: #{cells.inspect}"
  # puts "symbols: #{symbols.inspect}"

  lib_info = {}
  if topcells.size + cells.size > 0
    FileUtils.mkdir 'circuits' unless File.directory? 'circuits'
    #topcells.each{|cell| FileUtils.cp cell+'.asc', 'circuits' if File.exist? cell+'.asc'}
    topcells.each{|cell|
      if File.exist? cell+'.asc'
        File.open(File.join('circuits', cell+'.asc'), 'w'){|f| f.puts asc2cdraw(cell+'.asc')}
      end
    }
    cells.each{|cell|
      # FileUtils.cp cell+'.asc', 'circuits'
      File.open(File.join('circuits', cell+'.asc'), 'w'){|f| f.puts asc2cdraw(cell+'.asc')}
      # FileUtils.cp cell+'.asy', 'circuits'      
      File.open(File.join('circuits', cell+'.asy'), 'w'){|f| f.puts asy2cdraw(cell+'.asy')}

      lib_info[cell] = 'circuits'
    }
  end
  if symbol_lib_path
    puts "lib_symbols=#{lib_symbols}"
    symbols.size > 0 && symbols.each{|sym|
      if sym =~ /(\S+)\\\\(\S+)/
        lib_name = $1
        sym = $2
        sym_src = File.join symbol_lib_path, lib_name, sym+'.asy'
      else
        lib_name = 'symbols'
        sym_src = File.join symbol_lib_path, sym+'.asy'
      end
      lib_info[sym] = lib_name
      FileUtils.mkdir lib_name unless File.directory? lib_name
      # FileUtils.cp sym_src, lib_name if File.exist? sym_src
      FileUtils.cp sym_src, lib_name if File.exist? sym_src
      File.open(File.join(lib_name, sym+'.asy'), 'w'){|f| f.puts asy2cdraw(sym_src)}
    }
  end
  cells.each{|cell|
    props = {'cells' =>  {}}
    symbols = current.search_symbols cell
    symbols.each{|sym|
      if sym =~ /(\S+)\\\\(\S+)/
        sym = $2
      end
      props['cells'][sym] = lib_info[sym]
    }
    File.open(File.join(lib_info[cell], cell+'.yaml'), 'w'){|f| f.puts props.to_yaml}
  }
  [topcells, cells, symbols]  
end

=begin
def search_symbols cell, symbol_line_pattern='SYMBOL +(\S+) +'
  symbols = []
#  File.exist?(cell) && File.read(cell).each_line{|l|
  File.exist?(cell) && File.open(cell, 'r:Windows-1252').read.encode('UTF-8', invalid: :replace).each_line{|l|
    if l =~ /#{symbol_line_pattern}/
      symbols << $1
    end
  }
  symbols.uniq
end
private :search_symbols
=end

class String
  def downcase_
    self == self.downcase ? self.downcase + '_' : self.downcase
  end
end

module Alta  # included in cell.rb and testbench.rb except alta_upload
  def existing_editor_views field
    result = []
    return result unless desc = self.send(field)
    editor = nil
    desc.each_line{|l|
      if editor
        if l =~ /^<\/#{editor}/
          result << editor.downcase.to_s  # editor.class is HoboFields::Types::Text 
          editor = nil
        end
      elsif l =~ /^<(\S+)/
        editor = $1
        next
      end
    }
    result
  end

  def delete_view editor, field
    if desc = self.send(field)
      result = ''
      flag = nil
      desc.each_line{|l|
        if flag
          flag = false if l.downcase =~ /^<\/#{editor}/
          next
        elsif l.downcase =~ /^<#{editor}/
          flag = true
          next
        end
        result << l
      }
      self.send "#{field}=", result if desc != result
    end
  end
  
  def prep_start_tool simulator, testbench_name=nil, control=nil, postpr=nil
    ci = self.find_or_new_cell_implementation self.name+'_'+ simulator.name
    files = []
    if simulator.name == 'Simulink'
      if ci.netlist.index("\n") == 60
        files << fout_print(ci.cell.name + '.slx', Base64.decode64(ci.netlist), true)
      else
        files << fout_print(ci.cell.name + '.mdl', ci.netlist)    
      end
      
      if testbench_name
        if ci.cell.name == testbench_name # need to avoid .m to shadow .mdl
          files << fout_print(testbench_name + '_test.m', control)
        else
          files << fout_print(testbench_name + '.m', control)
        end
      end
      
      cell_props = YAML.load(ci.cell.properties||'')||{}
      cell_props['Simulink'] ||= {} 
      m_files = cell_props['Simulink']['m_files'] and m_files.each_pair{|mf, script|
        files << fout_print(mf, script)
      }
      print_all = <<EOF
mdl = '#{self.name}'
open_system(mdl)
print -s#{self.name} -dpng -r150 #{self.name}.png
all=find_system('#{self.name}', 'BlockType', 'SubSystem')
for n=1:size(all)
  mdl = all{n}
  open_system(mdl)
  print(strcat('-s', mdl), '-dpng', '-r150', strcat(strrep(mdl, '/', '_'), '.png'))
end
EOF
      files << fout_print('print_all.m', print_all)
      if postpr
        postpr.values.each{|pp|
          if pp =~ /get_csv +['"]([^ ,'"]+)['"] *, *(['"'].*)$/
            csv_file = $1
            variables = $2.gsub(/["' ]/, '').split(',')
            files << fout_print('write_csv.m', <<EOF
f=fopen('#{csv_file}', 'w')
fprintf(f, '#{variables.join(', ')}')

# [time, vin] = stairs(1:N,Vin(1:N),'b')
# [time2, vout] = stairs(1:N,Vout(1:N),'r')

for i = 1 : size(vin, 'r')
  fprintf(f, "%g, %g, %g\\n", #{variables.map{|v| "#{v}(i)"}.join(', ')})
end
fclose(f)
EOF
                          ) 
          end
        }
      end
    elsif simulator.name == 'Xcos'
      if ci && ci.netlist
        files << fout_print(self.name + '.xcos', ci.netlist)
        cell_props = YAML.load(self.properties||'')||{}
        cell_props['Xcos'] ||= {} 
        sci_files = cell_props['Xcos']['sci_files'] and sci_files.each_pair{|mf, script|
          files << fout_print(mf, script)
        }
        if sci_files && sci_files.size > 0
          exec_sci_files = sci_files.keys.map{|sf| "exec('#{sf}')"}.join("\n")
        else
          exec_sci_files = nil
        end
        context = ''
	control && control.each_line{|l|
          l.chomp!
          context << "'#{l}';\n"
        }
        files << fout_print('startup.sci', <<EOF
importXcosDiagram('#{self.name}.xcos')
xcos('#{self.name}.xcos')
#{exec_sci_files}
typeof(scs_m)
scs_m.props.context = [#{context}]

//clear pre_xcos_simulate;
//xcos_simulate(scs_m, 4);

EOF
                            )
      else
        files << fout_print('startup.sci', <<EOF
//importXcosDiagram('#{self.name}.xcos')
xcos('#{self.name}.xcos')
typeof(scs_m)

//clear pre_xcos_simulate;
//xcos_simulate(scs_m, 4);

EOF
                            )
      end
      files << fout_print('save_context.sci', <<EOF
importXcosDiagram('#{self.name}.xcos')
fd = mopen('#{self.name}.cxt', 'w')
mputl(scs_m.props.context, fd)
mclose(fd)
EOF
                          )
      if postpr
        postpr.values.each{|pp|
          if pp =~ /get_csv +['"]([^ ,'"]+)['"] *, *(['"'].*)$/
            csv_file = $1
            variables = $2.gsub(/["' ]/, '').split(',')
            files << fout_print('write_csv.sci', <<EOF
f=mopen('#{csv_file}', 'w')
mputl('#{variables.join(', ')}', f)
#{variables[0].downcase_} = getfield(4, #{variables[1]})
#{variables[1..-1].map{|v| "#{v.downcase_} = getfield(3, #{v})"}.join("\n")}

for i = 1 : size(vin, 'r')
  mfprintf(f, "%g, %g, %g\\n", #{variables.map{|v| "#{v.downcase_}(i)"}.join(', ')})
end
mclose(f)
EOF
                          ) 
          end
        }
      end
    end
    files
  end

  def import file
    filename = file.original_filename
    extname = File.extname(filename)
    if extname == '.net'
      dispose_net(file.read.encode('UTF-8'))
    elsif extname == '.asc'
      dispose_schematic(file.read.encode('UTF-8'))
    elsif extname == '.asy'
      dispose_symbol(file.read.encode('UTF-8'))
    elsif extname == '.zip'
      dispose_zip file.read
    end
  end

  def dispose_net net
    ci = self.find_or_new_cell_implementation File.basename(filename)
    ci.netlist = net
    ci.simulator = self.simulator
    ci.save!
  end

  def dispose_schematic schema
    set_schematic_view(self, 'ltspice', schema)
    self.save!
  end

  def dispose_symbol symbol
    set_symbol_view(self, 'ltspice', symbol)
    self.save!
  end

  def dispose_zip file
  end

#  include Alta2il

  def ade_export_core_prep src_path
    $terminals = {}
    with_directory(src_path){
      File.open(self.name+'.asc', 'w'){|f|
        f.print get_schematic_view(self)
        File.open(self.name+'.yaml', 'w'){|f|
          f.print self.properties
        } if self.properties
      } if !(sv=get_schematic_view(self)).blank? && sv =~ /^SHEET \d+ \d+ \d+\r*$/
      File.open(self.name+'.asy', 'w'){|f|
        f.print get_symbol_view(self)
      } if !get_symbol_view(self).blank?
    }
  end

  def ade_export_core src_path
    with_directory(src_path){
      props=(self.properties&&YAML.load(self.properties))||{}
      unless $grid_size = props['grid_size']
        props=(self.library.properties&&YAML.load(self.library.properties))||{}
        unless $grid_size = props['grid_size']
          props=(self.project.properties&&YAML.load(self.project.properties))||{}
          $grid_size = props['grid_size'] || 0.0625
        end
      end
      puts "grid_size for #{self.name} = #{$grid_size}"
      File.open(self.name+'.il', 'w'){|f|
        a2il = Alta2il.new src_path, self.name, self.library.name
        a2il.prepare_symbols f
        pins = a2il.alta2il f 
        a2il.alta2il_sym pins, f
      }
    }
  end

  def ade_export job_id, lib_name=self.library.name
    proj_dir = File.join($proj_repo_dir, self.project.name)
    proj_dir_init proj_dir, self.project.name
    src_path = File.join(proj_dir, 'pictures', lib_name)
    FileUtils.mkdir_p src_path unless File.directory? src_path
    ade_export_core_prep src_path
    ade_export_core src_path
    alta_dir = File.join(proj_dir, 'alta')
    FileUtils.mkdir_p alta_dir unless File.directory? alta_dir
    alta_file = File.join(alta_dir, "#{job_id}.alb" )
    Dir.chdir(File.join proj_dir, 'pictures'){
      system "zip -r '#{alta_file}' #{lib_name}/#{self.name}.*"
    }
    alta_file
  end

  def alta_export_job local_job, control=nil, model_script=nil, model_choices=nil, mos_models=nil, lw_correction=nil
    file_name = "#{local_job.id}.alb"
    description = YAML.load local_job.description || {}
    if self.class == Cell && description['cell'] != self.name
      if description['editor'] == 'ltspice'
        ltsp_append file_name, model_choices, mos_models, lw_correction
      elsif ['eeschema', 'xschem', 'qucs'].include? description['editor']
        alb_append description['editor'], file_name, model_choices, mos_models, lw_correction
      end
    else 
      if (description['editor'] == 'ltspice') && (check_data_type(self, 'ltspice') == 'ltspice')
        ltsp_export file_name, control, model_choices, mos_models, lw_correction
      else
        alb_export file_name, description['editor'], control, model_script, model_choices, mos_models, lw_correction
      end
    end
  end
    
  EESCHEMA_BLANK_SCHEMATIC = <<EOF
EESchema Schematic File Version 4
EELAYER 30 0
EELAYER END
\$Descr A4 11693 8268
encoding utf-8
Sheet 1 1
Title ""
Date ""
Rev ""
Comp ""
Comment1 ""
Comment2 ""
Comment3 ""
Comment4 ""
 \$EndDescr
\$EndSCHEMATC
EOF
  
  XSCHEM_BLANK_SCHEMATIC = <<EOF
v {xschem version=2.9.7 file_version=1.1}
G {}
V {}
S {}
E {}
EOF


# converters list
#                   cdraw          qucs             eeschema           xschem  
# cdraw                            cdraw2target     cdraw2target       cdraw2target
# qucs              qucs2cdraw     alb2qucs       (qucs2eeschema)    (qucs2xschem) 
# eeschema          eeschema2cdraw eeschema2qucs  alb2eeschema        eeschema2xschem
# xschem            xschem2cdraw   xschem2qucs         -               alb2xschem

  def alb_convert data_type, target, model_script=nil
    case data_type 
    when 'ltspice'
      cdraw2target target, 'cdraw', File.expand_path(target), model_script
      if target == 'qucs'
        Dir.chdir('qucs'){
          qucs2alb_back
        }
      elsif target == 'eeschema'
        Dir.chdir('eeschema'){
          eeschema2alb_back
        }
      elsif target == 'xschem'
        Dir.chdir('xschem'){
          xschem2alb_back
        }
      end
    when 'eeschema'
      alb2eeschema 'cdraw', File.expand_path('eeschema')
      if target == 'qucs'
        eeschema2qucs 'eeschema', File.expand_path('qucs')
        Dir.chdir('qucs'){
          qucs2alb_back
        }
      elsif target == 'xschem'
        eeschema2xschem 'eeschema', File.expand_path('xschem')
        Dir.chdir('xschem'){
          xschem2alb_back
        }
      elsif target == 'ltspice'
        eeschema2cdraw 'eeschema', File.expand_path('alta')
        Dir.chdir('alta'){
          cdraw2alb_back
        }
      end
    when 'xschem'
      if target == 'qucs'
        xschem2qucs 'cdraw', File.expand_path('qucs')
      elsif target == 'xschem'
        alb2xschem 'cdraw', File.expand_path('xschem')
      elsif target == 'eeschema'
        xschem2eeschema 'cdraw', File.expand_path('eeschema')
      elsif target == 'ltspice'
        alb2xschem 'cdraw', File.expand_path('xschem')
        xschem2cdraw 'xschem', File.expand_path('alta')
        Dir.chdir('alta'){
          cdraw2alb_back
        }
      end
    when 'qucs'
      if target == 'qucs'
        alb2qucs 'cdraw', File.expand_path('qucs'), model_script
      elsif target == 'eeschema'
        qucs2eeschema 'cdraw', File.expand_path('qucs'), model_script
      elsif target == 'xschem'
        qucs2xschem 'cdraw', File.expand_path('qucs'), model_script
      elsif target == 'ltspice'
        qucs2cdraw nil, self.project.name, File.expand_path('alta')
        Dir.chdir('alta'){
          cdraw2alb_back
        }
      end
    end
  end

  def alb_export file_name, target, control=nil, model_script=nil, model_choices=nil, mos_models=nil, lw_correction=nil
    proj_dir = File.join($proj_repo_dir, self.project.name)
    proj_dir_init proj_dir, self.project.name
    data_type = check_data_type self, target

    out_dir=File.join(proj_dir, 'cdraw')
    files = []
    File.directory?(out_dir) && FileUtils.rm_rf(out_dir)
    FileUtils.mkdir(out_dir) 
    Dir.chdir(out_dir) {
      if self.class == Library
        self.cells.each{|symbol|
          files = symbol.alb_export_prep target, data_type, files, control, true, model_choices, mos_models, lw_correction 
        }
      else
        if (get_schematic_view(self, data_type).blank? && self.class == Testbench && !(get_symbol_view self.instance.cell, data_type).blank?)
          self.properties = {'cells'=>{self.instance.cell.name => self.library.name}}.to_yaml
          case data_type
          when 'ltspice'
            set_schematic_view(self, data_type, "Version 4\nSHEET 1 880 680\n" +
                                                "SYMBOL #{self.instance.cell.name} 128 256 R0\n" +
                                                "SYMATTR InstName X1\n")
          when 'eeschema'
            set_schematic_view(self, data_type, EESCHEMA_BLANK_SCHEMATIC)
          when 'xschem'
            set_schematic_view(self, data_type, XSCHEM_BLANK_SCHEMATIC)
          when 'qucs'
            set_schematic_view(self, data_type, "<Qucs Schematic 0.0.21>\n" +
                                                "<Properties>\n" +
                                                "<View=0,0,800,800,1,0,0>\n" +
                                                "<Grid=10,10,1>\n" + 
                                                "<DataSet=#{self.name}.dat>\n" +
                                                "<DataDisplay=#{self.name}.dpl>\n" +
                                                "<OpenDisplay=1>\n" +
                                                "<Script=#{self.name}.m>\n" +
                                                "<RunScript=0>\n" +
                                                "<showFrame=0>\n" +
                                                "<FrameText0=Title>\n" +
                                                "<FrameText1=Drawn By:>\n" +
                                                "<FrameText2=Date:>\n" +
                                                "<FrameText3=Revision:>\n" +
                                                "</Properties>\n" +
                                                "<Symbol>\n" +
                                                "</Symbol>\n" +
                                                "<Components>\n" +
                                                "</Components>\n" +
                                                "<Wires>\n" +
                                                "</Wires>\n" +
                                                "<Diagrams>\n" +
                                                "</Diagrams>\n" +
                                                "<Paintings>\n" +
                                                "</Paintings>\n" +
                                                "</Qucs Schematic 0.0.21>")
          end
          self.save!
        end
        files = self.alb_export_prep target, data_type, files, control, true, model_choices, mos_models, lw_correction
      end
    }
    out_dir=File.join(proj_dir, target)
    out_dir=File.join(proj_dir, 'alta') if target == 'ltspice'
    FileUtils.mkdir(out_dir) unless File.directory?(out_dir) 
    if target == 'qucs'
      Dir.chdir(out_dir) {
        Dir.mkdir 'old' unless File.directory? 'old'
        system "tar czf old.tgz *_prj user_lib"
        Dir.glob('*_prj').each{|f| FileUtils.rm_rf f}
        FileUtils.rm_rf 'user_lib'
      }
    end
    Dir.chdir(proj_dir){
      alb_convert data_type, target, model_script
    }
    Dir.chdir(out_dir){
      system "cp -r ../alta/models ." if File.directory? '../alta/models'
      if target == 'ltspice'
        system "zip -r '#{file_name}' *.asc *.asy ./models"
      elsif target == 'qucs'
        system "zip -r '#{file_name}' *_prj user_lib ./models"
      elsif target == 'eeschema' 
        system "zip -r '#{file_name}' *.sch *.lib ./models sym-lib-table"
      elsif target == 'xschem' 
        system "zip -r '#{file_name}' *.sch *.sym ./models"
      end
    }
    puts "Exported to :#{File.join(out_dir, file_name)}"
    File.join(out_dir, file_name)
  rescue => error
    puts error
    puts error.backtrace
  end

  def cdraw2alb_back
    Dir.glob('*').each{|lib|
      next unless File.directory? lib
      library = self.project.libraries.find_by_name lib
      Dir.chdir(lib){
        Dir.glob('*.asy').each{|file|
          sym = file.sub('.asy', '')
          puts "set desc for sym=#{sym} under library=#{library.name}"
          if symbol = library.cells.find_by_name(sym)
            set_symbol_view symbol, 'ltspice', asy2cdraw(file)
            symbol.save!
          end
        }
        cells = Dir.glob('*.asc').map{|a| a.sub('.asc','')}
        name = nil
        cells.each{|c|
          if cell = library.cells.find_by_name(c.sub '.asc', '')
            set_schematic_view cell, 'ltspice', asc2cdraw(c+'.asc')
            cell.save!
          end
        }
      }
    }
  end

  def qucs2alb_back
    libraries = Dir.glob('*')
    libraries.each{|lib|
      if lib == 'user_lib'
        Dir.glob('user_lib/*.lib'){|file|
          flag = nil
          library = self.project.libraries.find_by_name File.basename(file).sub('.lib', '')
          
          desc = sym = nil
          File.read(file).each_line{|l|
            if flag
              if l=~/<\/Symbol>/
                flag = nil
                puts "set desc for sym=#{sym} under library=#{library.name}"
                if symbol = library.cells.find_by_name(sym) # this check became necessary since 'voltage' derives 'vsin' etc.
                  set_symbol_view symbol, 'qucs', desc
                  symbol.save!
                end
              else
                desc << l
              end
            elsif l=~ /<Symbol>/
              desc = ''
              flag = true
            elsif l=~/<Component (\S+)>/
              sym = $1
            end
          }
        }
        next
      end
      next unless File.directory? lib
      library = self.project.libraries.find_by_name lib.sub('_prj','')
      puts "chdir to lib=#{lib}, pwd=#{Dir.pwd}"
      Dir.chdir(lib){
        cells = Dir.glob('*.sch').map{|a| a.sub('.sch','')}
        name = nil
        cells.each{|c|
          cell = library.cells.find_by_name c.sub('.sch', '')
          if cell.nil? && self.class == Testbench && self.name + '.sch' == c
            cell = self
          end
          sch_txt = ''
          sym_txt = ''
          context = nil
          qucs_version=nil
          File.read(c+'.sch').each_line{|l|
            if context == 'Components'
              if l.include? '</Components>'
                context = nil
              end
              sch_txt << l
            elsif context == 'Symbol'
              if l.include? '</Symbol>'
                context = nil
              else
                sym_txt << l
              end
            elsif l.include? '<Components>'
              context = 'Components'
              sch_txt << l
            elsif l.include? '<Symbol>'
              context = 'Symbol'
            elsif l=~/<Qucs Schematic (\S+)>/
              qucs_version = $1
              sch_txt << l
            else
              sch_txt << l
            end
          }
          if qucs_version
            cell = self if cell.nil?
            set_schematic_view cell, 'qucs', sch_txt + "</Qucs Schematic #{qucs_version}>" 
          end
          if sym_txt != ''
            set_symbol_view cell, 'qucs', "<Qucs Symbol #{qucs_version}>\n#{sym_txt}\n</Qucs Symbol #{qucs_version}>\n" if cell
          end
          cell.save! if cell
        }
      }
    }
  end

  def xschem2alb_back
    if self.class == Library
      library = self
    else
      library = self.library
    end

    Dir.glob('*.sym').each{|file|
      sym = file.sub('.sym', '')
      # library = self.project.libraries.find_by_name 'symbols'
      puts "set desc for sym=#{sym} under library=#{library.name}"
      if symbol = library.cells.find_by_name(sym)
        set_symbol_view symbol, 'xschem', File.read(file)
        symbol.save!
      end
    }

    cells = Dir.glob('*.sch').map{|a| a.sub('.sch','')}
    # library = self.project.libraries.find_by_name 'circuits'
    cells.each{|c|
      if cell = library.cells.find_by_name(c.sub '.sch', '')
        set_schematic_view cell, 'xschem', File.read(c+'.sch')
        cell.save!
      end
    }
  end

  def eeschema2alb_back
    libraries = Dir.glob('*.lib').map{|l| l.sub('.lib', '')}
    libraries.each{|lib|
      file = lib+'.lib'
      flag = nil
      library = self.project.libraries.find_by_name lib
      desc = sym = nil
      File.read(file).each_line{|l|
        if flag
          if l=~/^ENDDEF/
            flag = nil
            desc << l
            puts "set desc for sym=#{sym} under library=#{library.name}"
            if symbol = library.cells.find_by_name(sym)
              set_symbol_view symbol, 'eeschema', desc
              symbol.save!
            end
          else
            desc << l
          end
        elsif l=~ /^DEF (\S+)/
          desc = l
          flag = true
          sym = $1
        end
      }
      next if self.class == Library
      
      cells = Dir.glob('*.sch').map{|a| a.sub('.sch','')}
      cells.each{|c|
        cell = library.cells.find_by_name c.sub('.sch', '')
        if cell.nil? && self.class == Testbench && self.name + '.sch' == c
          cell = self
        end
        if cell
          cell.reload
          sch_txt = File.read(c+'.sch')
          set_schematic_view cell, 'eeschema', sch_txt
          cell.save!
        end
      }
    }
  end

  def alb_export_prep target, data_type, files, control=nil, recursion=false, model_choices=nil, mos_models=nil, lw_correction=nil
    target = self
    if self.class == Testbench && (get_schematic_view(self, data_type).blank? || (data_type == 'ltspice' &&(not get_schematic_view(self, data_type) =~ /^SHEET \d+ \d+ \d+\r*$/)))
      target = self.instance.cell
      control = get_schematic_view(self, data_type)
    end
    lib_name = target.library.name
    Dir.mkdir lib_name unless File.directory? lib_name
    data_type, sch, sym, = get_data_type(data_type)
    flag = nil
    unless files.include? file = File.join(lib_name, target.name+sch)
      flag = true
      if (desc = get_schematic_view(target, data_type)).blank?
        case data_type
        when 'eeschema'
          set_schematic_view(self, data_type, desc=EESCHEMA_BLANK_SCHEMATIC)
        when 'xschem'
          set_schematic_view(self, data_type, desc=XSCHEM_BLANK_SCHEMATIC)
        when 'qucs'
          set_schematic_view(self, data_type, desc="<Qucs Schematic 0.0.21>\n" +
                                                   "<Properties>\n" +
                                                   "<View=0,0,800,800,1,0,0>\n" +
                                                   "<Grid=10,10,1>\n" + 
                                                   "<DataSet=#{self.name}.dat>\n" +
                                                   "<DataDisplay=#{self.name}.dpl>\n" +
                                                   "<OpenDisplay=1>\n" +
                                                   "<Script=#{self.name}.m>\n" +
                                                   "<RunScript=0>\n" +
                                                   "<showFrame=0>\n" +
                                                   "<FrameText0=Title>\n" +
                                                   "<FrameText1=Drawn By:>\n" +
                                                   "<FrameText2=Date:>\n" +
                                                   "<FrameText3=Revision:>\n" +
                                                   "</Properties>\n" +
                                                   "<Symbol>\n" +
                                                   "</Symbol>\n" +
                                                   "<Components>\n" +
                                                   "</Components>\n" +
                                                   "<Wires>\n" +
                                                   "</Wires>\n" +
                                                   "<Diagrams>\n" +
                                                   "</Diagrams>\n" +
                                                   "<Paintings>\n" +
                                                   "</Paintings>\n" +
                                                   "</Qucs Schematic 0.0.21>")
        end
        self.save!
      end
      File.open(file, 'w'){|f| f.print desc}
      files << file
    end
    
    unless files.include? file = File.join(lib_name, target.name+sym)
      flag = true
      unless (desc = get_symbol_view(target, data_type)).blank?
        File.open(file, 'w'){|f| f.print desc} 
        files << file
      end
    end
    props=(target.properties&&YAML.load(target.properties))||{}
    fixed_props = {}
    recursion && props['cells'] && props['cells'].each_pair{|sym, lib|
      next if sym =~ /(\\\\|@)/ # just ignore
      if library = target.project.libraries.find_by_name(lib)
        if symbol = library.cells.find_by_name(sym)                      # note:find_by_name is case insensitive
          if lib == 'symbols' || !get_symbol_view(symbol, data_type).blank?
            files = symbol.alb_export_prep target, data_type, files, nil, recursion, model_choices, mos_models, lw_correction
          elsif (library2 = self.project.libraries.find_by_name('symbols')) && # this part is a dirty fix to cope with old LTspice
                symbol2 = library2.cells.find_by_name(sym)                      # data which mishandled case sensitivity
            files = symbol2.alb_export_prep target, data_type, files, nil, recursion, model_choices, mos_models, lw_correction
            fixed_props[sym.downcase] = 'symbols'
          else
            files = symbol.alb_export_prep target, data_type, files, nil, recursion, model_choices, mos_models, lw_correction
          end
        end
      end
    }
    fixed_props.each_pair{|sym, lib|
      props.delete sym.upcase
      props['cells'][sym] = lib
    }

    File.open(file = File.join(lib_name, target.name+'.yaml'), 'w'){|f|
      yaml = {'grid_size' => props['grid_size']||0.0625,
        'cells' => props['cells'], 'thick_wires' => props['thick_wires']}
      f.print yaml.to_yaml
    }
    puts "#{target.name} exported" if flag
    files
  end

  def alb_append target, file_name, model_choices=nil, mos_models=nil, lw_correction=nil
    proj_dir = File.join($proj_repo_dir, self.project.name)
    proj_dir_init proj_dir, self.project.name
    data_type = check_data_type(self, target)

    out_dir=File.join(proj_dir, target)
    out_dir=File.join(proj_dir, 'alta') if target == 'ltspice'

    files = []
    Dir.chdir(out_dir) {
      files = self.alb_export_prep target, data_type, files, nil, true, model_choices, mos_models, lw_correction
    }
    Dir.chdir(proj_dir){
      alb_convert data_type, target
    }
    Dir.chdir(out_dir){
      if target == 'qucs'
        system "zip -r '#{file_name}' *_prj user_lib"
      elsif target == 'eeschema'
        system "zip -r '#{file_name}' *.sch *.lib"
      elsif target == 'xschem'
        system "zip -r '#{file_name}' *.sch *.sym"
      end
    }
    puts "Exported to :#{File.join(out_dir, file_name)}"
    File.join(out_dir, file_name)
  end

  def ltsp_export file_name, control=nil, model_choices=nil, mos_models=nil, lw_correction=nil
#    proj_dir = File.join($proj_repo_dir, self.project_name)
#    proj_dir_init proj_dir, self.project_name
#    out_dir=File.join(proj_dir, 'alta')
    out_dir = '.'

    FileUtils.mkdir(out_dir) unless File.directory?(out_dir) 
    Dir.chdir(out_dir) {
      Dir.mkdir 'old' unless File.directory? 'old'
      %W[*.asc *.asy *.yaml *.net *.plt *.raw *.log].map{|pat| Dir.glob(pat)}.flatten.each{|src|
        FileUtils.mv src, 'old', :force=>true
      }
#      if target.schematic_view && target.schematic_view =~ /^SHEET \d+ \d+ \d+\r*$/
#        files = target.alta_export_prep files, control, true, true, model_choices, mos_models, lw_correction

      files = ltsp_export_sub(control, model_choices, mos_models, lw_correction).map{|a| "'#{a}'"}
      puts "zip -r '#{file_name}' *.net *.plt ap_save.ap ./models #{files.join(' ')} -x *.rb created"
      system "zip -r '#{file_name}' *.net *.plt ap_save.ap ./models #{files.join(' ')} -x *.rb created"
      system '(sleep 3; touch created)&' # 'created' file must have newer timestamp
    }
    puts "Exported to :#{File.join(out_dir, file_name)}"
    File.expand_path(File.join(out_dir, file_name))
  end

  def ltsp_export_sub control=nil, model_choices=nil, mos_models=nil, lw_correction=nil
    target = self
    if self.class == Instance
      target = target self.cell
    elsif self.class == TestbenchAssignment
      target = self.testbench
    end
    @@target = target
    files = []
    globals = []
    cell2libs = {}
    cdf = {}
    ltspice = Simulator.find_by_name 'LTspice'
    if self.class == Library
        self.cells.each{|symbol|
          files, glbls, noconn_conv = symbol.ltsp_export_prep files, cdf, cell2libs, control, true, true, model_choices, mos_models, lw_correction
        }
    elsif get_schematic_view(target).blank? || (not get_schematic_view(target) =~ /^SHEET \d+ \d+ \d+\r*$/)
      if get_symbol_view(target).blank?
        if target.class == Cell
          if target.cell_type
            ports = target.cell_type.ports.gsub(',', ' ').split
            set_symbol_view(target, 'ltspice', create_symbol_from_ports(ports))
            target.save!
            files << target.name + '.asy'
            File.open(target.name + '.asy', 'w:UTF-8'){|f| f.puts get_symbol_view(target).encode('UTF-8', invalid: :replace)}
          elsif (ci = pick_object(target.cell_implementations, ltspice)) && (not ci.netlist.blank?)
            set_symbol_view(target, 'ltspice', create_symbol_for_netlist(target.name, ci.netlist))
            target.save!
            files << target.name + '.lib'
            files << target.name + '.asy'
            File.open(target.name + '.asy', 'w:UTF-8'){|f| f.puts get_symbol_view(target).encode('UTF-8', invalid: :replace)}
          else
            if control && control != '' 
              set_schematic_view(target, 'ltspice', "Version 4\nSHEET 1 880 680\nTEXT 0 300 Left 2 !" + control.gsub("\n", '\n'))
            else
              set_schematic_view(target, 'ltspice', "Version 4\nSHEET 1 880 680\n")
            end
            target.save!
            files << target.name + '.asc'
            schematic = get_schematic_view(target).encode('UTF-8', invalid: :replace).gsub("\n", "\r\n")
            File.open(target.name + '.asc', 'wb:Windows-1252'){|f| f.print schematic}
          end
        elsif target.class == Testbench # self.class is Testbench or TestbenchAssignment 
          cell = self.instance.cell
          if get_schematic_view(cell, 'ltspice').blank? && get_symbol_view(cell).blank?
            File.open(self.name+'.net', 'w:UTF-8'){|f|
              f.puts "*\n#{target.netlist(ltspice)}\n#{cell.netlist(ltspice)}\n#{target.control(ltspice)}".encode('UTF-8', invalid: :replace)
            }
            files << target.name+'.net'
          else
            if target.cell_type # shared testbench
              if get_schematic_view(target).blank? || (not get_schematic_view(target) =~ /^SHEET \d+ \d+ \d+\r*$/)
                File.open(target.name+'.net', 'w:UTF-8'){|f|
                  f.puts "*\n#{target.netlist(ltspice)}\n".encode('UTF-8', invalid: :replace)
                  f.puts ".subckt #{self.instance.cell.name} #{target.cell_type.ports.gsub(',', ' ')}\n".encode('UTF-8', invalid: :replace)
                  f.puts ".include '#{self.instance.cell.name}.net'\n".encode('UTF-8', invalid: :replace)
                  f.puts ".ends #{self.instance.cell.name}\n".encode('UTF-8', invalid: :replace)
                  f.puts "#{target.control(ltspice)}".encode('UTF-8', invalid: :replace)
                }
                files << target.name+'.net'
              end
              target = self.instance.cell
              cell2libs = target.ltsp_check_hier
              files, glbls, noconn_conv = target.ltsp_export_prep files, cdf, cell2libs, control, true, true, model_choices, mos_models, lw_correction
              target.reload
              files << noconn_symbol_special if noconn_conv
              globals = globals + glbls if glbls
            elsif target.instance
              if !(symbol = get_symbol_view(target.instance.cell)).blank?
                target.properties = {'cells'=>{target.instance.cell.name => target.library.name}}.to_yaml
                if !get_schematic_view(target.instance.cell).blank?
                  inst_name = 'X1'
                else
                  symbol =~ /SYMATTR +Prefix +(\S+)/
                  inst_name = $1 + '1'
                end
                set_schematic_view(target, 'ltspice', "Version 4\nSHEET 1 880 680\n" +
                                   "SYMBOL #{self.instance.cell.name} 128 256 R0\n" +
                                   "SYMATTR InstName #{inst_name}\n")
                target.save!
              end
              if get_schematic_view(target).blank? || (not get_schematic_view(target) =~ /^SHEET \d+ \d+ \d+\r*$/)
                target = target.instance.cell
                #                  control = target.schematic_view unless target.schematic_view.blank?
              end
              cell2libs = target.ltsp_check_hier
              files, glbls, noconn_conv = target.ltsp_export_prep files, cdf, cell2libs, control, true, true, model_choices, mos_models, lw_correction
              target.reload
              files << noconn_symbol_special if noconn_conv
              globals = globals + glbls if glbls
            end
          end
        end
      else # only symbol view
        target_name = target.name
        unless ['circuits', 'symbols', @@target.library.name].include? target.library.name
          target_name = target.name + '@' + target.library.name
        end
        files << target_name + '.asy'
        File.open(target_name + '.asy', 'w:UTF-8'){|f| f.puts get_symbol_view(target).encode('UTF-8', invalid: :replace)}
      end
    else # schematic view is not blank
=begin
         target = self.instance.cell if self.class == Testbench && self.instance
         if (self.schematic_view.blank? || (not self.schematic_view =~ /^SHEET \d+ \d+ \d+\r*$/))
           control = self.schematic_view # control is TEXT ... !.global ...
         end
=end
      cell2libs = target.ltsp_check_hier
      files, glbls, noconn_conv = target.ltsp_export_prep files, cdf, cell2libs, control, true, true, model_choices, mos_models, lw_correction
      self.reload
      files << noconn_symbol_special if noconn_conv
      globals = globals + glbls if glbls 
    end
    
    puts "*** Duplicated cell names:"
    cell2libs.each_pair{|c, l| puts "#{c} exists in: #{l.join(', ')}" if l.size > 1}

    if self.class == Testbench && !File.exist?(self.name+'.asc') && (self.instance && !get_symbol_view(self.instance.cell).blank?)
      ltsp_export_testbench_netlist ltspice
    elsif self.class == Instance
      self.testbenches.each{|tb|
        tb.ltsp_export_testbench_netlist ltspice, tb.name
      }
    end

    File.open('created', 'w'){|f|
      f.puts({'comment'=>"Created for #{self.project.name} by ALB v#{ALB_VERSION}",
               'files'=>files}.to_yaml)
    }
    files
  end

  def ltsp_export_testbench_netlist ltspice=Simulator.find_by_name('LTspice'), tb_name=nil
    File.open(self.name+'.net', 'w:UTF-8'){|f|
      params = []
      if ti = pick_object(self.testbench_implementations, ltspice)
        if self.instance && cell = self.instance.cell
          if ci = pick_object(cell.cell_implementations, ltspice)
            cell.parameters && params << cell.parameters
            self.parameters && params << self.parameters
            self.instance.parameters && params << self.instance.parameters
            ti_netlist = ti.netlist and ti_netlist.chomp!
            ci_netlist = ci.netlist and ci_netlist.chomp!
            ltsp_export_testbench_netlist_sub f, tb_name, control, params, ti_netlist, ci_netlist
          else # no cell implemenation
            self.parameters && params << self.parameters
            self.instance.parameters && params << self.instance.parameters
            ti_netlist = ti.netlist and ti_netlist.chomp!
            ltsp_export_testbench_netlist_sub f, tb_name, control, params, ti_netlist, nil
          end
        else 
          self.parameters && params << self.parameters
          f.puts replace_parameters "* #{self.name}.net\n#{ti.netlist.chomp}\n#{control}", params, 'ltsp_export'
          ltsp_export_testbench_netlist_sub f, tb_name, control, params, ti.netlist.chomp, nil
        end
      else
        puts "#{self.name} has no tesbench implementation for #{ltspice}"
      end
      if self.view_settings.size > 0 && ti && ti.postprocess
        #            postpr, atype = yaml_like_load ti.postprocess
        view, script, type = get_base_script ti.postprocess
        if type == 'dc'
          title = 'DC transfer characteristic'
        elsif type == 'ac'
          title = 'AC Analysis'
        elsif type == 'tran'
          title = 'Transient Analysis'
        end
        plt = PltSettings.new title
        self.view_settings.each{|vs|
          plt.pane << create_pane(plt.color_table, script, vs)
        }
        plt.save self.name + '.plt'
      end
    }
  end
  
  def ltsp_export_testbench_netlist_sub f, tb_name, control, params, ti_netlist, ci_netlist=nil 
    f.puts replace_parameters("* #{self.name}.net\n#{ti_netlist}\n#{ci_netlist}\n#{control}", params, 'ltsp_export').encode('UTF-8', invalid: :replace)
    File.open("#{tb_name}.testbench_netlist", 'w:UTF-8'){|f| f.puts "#{ti_netlist}".encode('UTF-8', invalid: :replace)}
    File.open('.cell_netlist', 'w:UTF-8'){|f| f.puts "#{ci_netlist}".encode('UTF-8', invalid: :replace)} unless File.exist? '.cell_netlist'
    File.open("#{tb_name}.control", 'w:UTF-8'){|f| f.puts control.encode('UTF-8', invalid: :replace)} if control
  end

  def create_pane color_table, script, vs
    pane = Pane.new
    pane.x = ["' '", 1, 0, 0, 0] # auto
    pane.y0 = ["'?'", 0, 0, 0, 0] # auto 
    pane.log = [vs.xscale == 'log'? 1:0, vs.yscale == 'log'? 1:0, 0]
    script =~ /@ltspice.save *\S+, *\S+,  *(\S+), *(\S+)/
    name = $2 && $2.gsub("'", "\"")
    magic_number = 1*16**6 + 1*16**4 + 1*16**2 + 0
    pane.traces = [[magic_number, 0, name]]
    pane
  end
  private :create_pane

  def create_symbol_for_netlist name, netlist
    netlist.each_line{|l|
      break if l.downcase =~ /subckt +(\S+) +(.*)$/
    }
    if ckt_name = $1 
      ports = $2.split
      File.open(name+'.lib', 'w'){|f| f.puts netlist}
      result = create_symbol_from_ports ports
      result << "SYMATTR ModelFile #{name}.lib\n"
      result << "SYMATTR SpiceModel #{ckt_name}\n"
    end
  end

  def create_symbol_from_ports nets
    result = "Version 4\nSymbolType Cell\n"
    height = width = ((nets.size/4).ceil + 2)*16
    height = [height, 3*16].max
    width = [width, 4*16].max
    origin_x = ((width/32).ceil)*16
    origin_y = ((height/32).ceil)*16
    result << "RECTANGLE Normal #{origin_x} #{origin_y} #{origin_x-width} #{origin_y-height}\n"
    nets.each_with_index{|net, i|
      result << "PIN #{origin_x+16} #{origin_y-height + i*16} LEFT 8\n"
      result << "PINATTR PinName #{net}\n"
      result << "PINATTR SpiceOrder #{i+1}\n"
    }
    result << "SYMATTR Prefix X\n"
    result
  end

  private :create_symbol_for_netlist, :create_symbol_from_ports

  def ltsp_append file_name, model_choices=nil, mos_models=nil, lw_correction=nil
    proj_dir = File.join($proj_repo_dir, self.project.name)
    proj_dir_init proj_dir, self.project.name
    out_dir=File.join(proj_dir, 'alta')
    files = []
    with_directory(out_dir) {
# it is unnecessary to create blank schematic especially for symbols
#      if self.schematic_view.blank?
#        self.schematic_view = "Version 4\nSHEET 1 880 680\n"
#        self.save!
#      end
      
      files, glbls, noconn_conv = self.ltsp_export_prep files, {}, {}, nil, true, true, model_choices, mos_models, lw_correction
      files << noconn_symbol_special if noconn_conv

      system "zip -r '#{file_name}' #{files.join(' ')}"
    }
    puts "Exported to :#{File.join(out_dir, file_name)}"
    File.join(out_dir, file_name)
  end

  def ltsp_check_hier cell2libs = {}
    if cell2libs == {}
      print "Check_hier entered ... " 
    else
      print "#{self.name} .. "
    end
    props=(self.properties&&YAML.load(self.properties))||{}
    props['cells'] && props['cells'].each_pair{|sym, lib|
      next if sym =~ /(\\\\|@)/ # just ignore
      if (library = self.project.libraries.find_by_name(lib)) &&
          symbol = library.cells.find_by_name(sym)
        cell2libs[sym] ||= []
        unless cell2libs[sym].include? lib
          cell2libs[sym] << lib 
          symbol.ltsp_check_hier cell2libs
        end
      end
    }
    cell2libs
  end

  def ltsp_convert_sym_name_with_lib props # , cell2libs # Note: cell2libs is no longer used
    result = ''
    get_schematic_view(self).each_line{|l|
      if l =~ /SYMBOL +(\S+) +(.*$)/
        sym = $1
        rest = $2
        if sym =~ /(\S+)\\\\(\S+)/
          lib = $1
          sym = $2
          puts "Warning "#{lib}\\#{sym} may be defined in library #{props[sym]}" if lib != props[sym]
        end
        #if cell2libs[sym] && cell2libs[sym].size > 1 # sym in more than two libraries
        #  result << "SYMBOL #{sym}@#{props[sym]} #{rest}\n"
        #else
        lib=props[sym] 
        if lib =~ /(\S+)\\\\(\S+)/ # just in case props is :{"NMOS"=>"OR1LIB\\\\NMOS", "inv1"=>"OR1_StdCells_v1"}
          lib = $1
        end
        if lib and not ['circuits', 'symbols', @@target.library.name].include? lib
          library = self.project.libraries.find_by_name(lib)
          # cell = library.cells.find_by_name(sym) ### why is this needed???
          result << "SYMBOL #{props[sym]}\\\\#{sym} #{rest}\n"
        else
          result << l
        end
      else
        result << l
      end
    }
    result
  end

  def ltsp_export_prep files, cdf, cell2libs={}, control=nil, conversion=false, recursion=false, model_choices=nil, mos_models=nil, lw_correction=nil
#    self_name = (cell2libs[self.name].nil? || cell2libs[self.name].size <= 1) ? self.name : self.name + '@' + self.library.name
    self_name = self.name
    unless (@@target.class == Library) || ['circuits', 'symbols', @@target.library.name].include?(self.library.name)
      self_name = self.name + '@' + self.library.name
    end

    props=(self.properties&&YAML.load(self.properties))||{}
    noconn_conv = nil
    globals = nil

    recursion && props['cells'] && props['cells'].each_pair{|sym, lib|
      # next if sym =~ /(\\\\|@)/ || sym == self.name # this should not happen!!! 
      next if sym == self.name # this should not happen!!! 
      if (library = self.project.libraries.find_by_name(lib)) &&
          symbol = library.cells.find_by_name(sym)
        files, glbls, nc = symbol.ltsp_export_prep files, cdf, cell2libs, nil, conversion, recursion, model_choices, mos_models, lw_correction
        self.reload
        if glbls
          globals ||= [] 
          globals = globals + glbls 
        end
        noconn_conv ||= nc 
      end
    }

    flag = nil
    unless files.include?(self_name+'.asc')
      flag = true
      if get_schematic_view(self).blank? && get_symbol_view(self).blank?
        set_schematic_view(self, 'ltspice', "Version 4\nSHEET 1 880 680\n")
        self.save!
      else
        unless glbls = props['globals']
          get_schematic_view(self) && get_schematic_view(self).each_line{|l|
            l.chop!
            if l =~ /^FLAG.* (\w+!)$/
              glbls ||= []
              glbls << $1.to_s
            elsif l =~ /^SYMATTR Value (wavefile|WAVEFILE) *= *(\S+.(wav|WAV))/
              wavefile = $2
              self.documents.each{|doc|
                if doc.document_file_name == wavefile 
                  path = File.join RAILS_ROOT, 'public','system', 'documents', doc.id.to_s, 'original', wavefile
                  next unless File.exist? path
                  FileUtils.ln_s path, wavefile unless File.exist? wavefile
                  files << wavefile
                end
              }
            end
          }
          if glbls != props['globals'] 
            props['globals'] = glbls
            self.properties = props.to_yaml
            self.save!
          end
        end
        if glbls
          globals ||= []
          globals = globals + glbls 
        end
      end

      (not get_schematic_view(self).blank?) && File.open(self_name+'.asc', 'w:Windows-1252'){|f|
        self_schematic_view = ltsp_convert_sym_name_with_lib props['cells']
        #debugger if cell2libs[self.name] && cell2libs[self.name].size > 1 && @debugger.nil?
        if conversion
#          if self.class == Testbench && globals
          if globals
            globals.uniq! 
            if control =~ /^TEXT.*!(\.global .*?)\\n/
              control.sub! $1, '.global ' + globals.join(' ')
            else
              control = ".global #{globals.join(' ')}\n" + control if control
            end
          end
          result, noconn_conv = cdraw2asc(self_schematic_view, control, model_choices, mos_models, lw_correction)
          f.print result.encode('UTF-8', invalid: :replace).gsub("\n", "\r\n")
          f.print control.encode('UTF-8', invalid: :replace).gsub("\n", "\r\n") if control =~ /^TEXT /  # control actually was testbench's schematic_view
        else
          f.print self_schematic_view.encode('UTF-8', invalid: :replace).gsub("\n", "\r\n")
        end
        files << self_name+'.asc'
      } 
    end
    
    unless files.include?( self_name+'.asy')
      flag = true
      unless get_symbol_view(self).blank?
        File.open(self_name+'.asy', 'w:UTF-8'){|f|
          f.print cdraw2asy(get_symbol_view(self))
        }
      end
      files << self_name+'.asy'
      
      simulator = Simulator.find_by_name 'LTspice'
      if (self.class == Cell && ci = pick_object(self.cell_implementations, simulator)) && (not ci.netlist.blank?)
        File.open(self_name+'.lib', 'w'){|f| f.puts ci.netlist}
        files << self_name + '.lib'
      end
    end
################ next part has been moved above
=begin
    recursion && props['cells'] && props['cells'].each_pair{|sym, lib|
      if (library = self.project.libraries.find_by_name(lib)) &&
          symbol = library.cells.find_by_name(sym)
        files, glbls, nc = symbol.ltsp_export_prep files, cell2libs, nil, conversion, recursion, model_choices, mos_models, lw_correction
        if glbls
          globals ||= [] 
          globals = globals + glbls 
        end
        noconn_conv ||= nc 
      end
    }
=end
    props['cells'] && File.open(self_name+'.yaml', 'w'){|f|
      yaml = {'grid_size' => props['grid_size']||0.0625,
        'cells' => props['cells'], 'thick_wires' => props['thick_wires']}
      f.print yaml.to_yaml
    }
    if flag
      if props['cdf']
        cdf[self.name] = props['cdf']
        print "*** cdf registered and "
      end
      puts "#{self_name} exported" 
    end
    globals.uniq! if globals
    [files, globals, noconn_conv]
  end

  def set_spicenet obj, spicenet, name = obj.name.downcase
    return if spicenet == {}
#debugger
    unless ci = pick_object(obj.cell_implementations, obj.simulator)
      ci = obj.find_or_new_cell_implementation obj.name+'_'+obj.simulator.name
    end
    ci.simulator = obj.simulator
    if ci.netlist.blank?
      if name != obj.name.downcase
        ci.netlist = spicenet[:main] if spicenet[:main]
      else
        if spicenet[:subckt] != {}
          ci.netlist = spicenet[:subckt][name] 
        elsif spicenet[:main]
          ci.netlist = spicenet[:main] + spicenet[:control]
        end
      end
    end
    ci.save!
  end    
  private :set_spicenet
    
  def alb_import_sub lib_dir, target, recursion, imported, spicenet={}, data_type='ltspice', sch='.asc', sym='.asy'
    if props = YAML_update(lib_dir, tr(target.name), target.library.name) 
      props['cells'] && props['cells'].each_pair{|s, lib|
#        lib = lib_dir unless lib_dir == '.'  ### lib_dir = 'JEPICO', lib='umc...'
        puts "s=#{s}, lib=#{lib} under lib_dir=#{lib_dir}" 
        unless target.project && (library = target.project.libraries.find_by_name(lib))
          library = Library.new :name => lib
          library.project = target.project
          library.save!
        end
        unless cell = library.cells.find_by_name(s)
          cell = library.find_or_new_cell s
          puts "*** cell.name = #{cell.name}"
          cell.save!
        end
        if imported.nil? || !imported.include?(cell)
          imported = cell.alb_import(lib, recursion, imported, spicenet, data_type, sch, sym) if recursion
        end
      }
      target_props = (target.properties ? YAML.load(target.properties) : {}) || {}
      target_props['cells'] = props['cells']
      target.reload if target.id
      target.properties = target_props.to_yaml
      target.save!
    end
    imported
  end

  def alb_import lib_dir, recursion=nil, imported=[], spicenet={}, data_type='ltspice', sch='.asc', sym='.asy'
    self.reload if self.id # this helped to avoid 'update a stale object error'
    self_name = self.name
    if data_type == 'ltspice'
      unless (lib_dir != '.') || ['circuits', 'symbols'].include?(self.library.name) || File.exist?(tr(self.name)+sch) # bug fix 2018/9/25
        self_name = self.name + '@' + self.library.name
      end
    end
    flag = nil
    if File.exist? asc_file = File.join(lib_dir, tr(self_name)+sch)
      print "alb_import #{self.class.name} (under #{lib_dir}): '#{self_name}', imported=#{imported.inspect}"
      puts recursion ? 'recursively' : ''
      # imported = alb_import_sub lib_dir, self, recursion, imported, spicenet, data_type, sch, sym
      self.simulator = Simulator.find_by_name('LTspice') # if self.simulator.nil?
      set_spicenet self, spicenet
      # if true # base_time.nil? || File.stat(asc_file).mtime > base_time
      if !File.exist?('created') || (File.stat(asc_file).mtime >= File.stat('created').mtime)
        if File.basename(Dir.pwd) == 'pictures'
          set_schematic_view(self, 'ltspice', File.open(asc_file, 'r:Windows-1252').read.encode('UTF-8', invalid: :replace))
        else
          case data_type
          when 'ltspice'
            set_schematic_view(self, 'ltspice', asc2cdraw(asc_file))
          when 'eeschema'
            set_schematic_view(self, 'eeschema', File.read(asc_file))
            if File.exist? cache_file = tr(self_name)+'-cache.lib'
              cache = QucsLibrary.new(tr(self_name)).extract_eeschema_components(File.read(cache_file))
              schema = QucsSchematic.new tr(self_name)
              schema.eeschema_schema_in
              schema.components.each{|comp|
                next unless comp[:lib_path] && comp[:cell_name]
                if desc = cache[comp[:lib_path] + '_' + comp[:cell_name]]
                  FileUtils.mkdir comp[:lib_path] unless File.directory?(comp[:lib_path])
                  File.open(File.join(comp[:lib_path], comp[:cell_name]+'.sym'), 'w'){|f|
                    f.puts desc.gsub! comp[:lib_path] + '_', ''
                  }
                  cache[comp[:lib_path] + '_' + comp[:cell_name]] = nil
                end
              }
            end
          when 'xschem'
            set_schematic_view(self, 'xschem', File.read(asc_file))
          when 'qucs'
            set_schematic_view(self, 'qucs', File.read(asc_file))
          end
          self.save!
        end
        flag = true
      end
      imported = alb_import_sub lib_dir, self, recursion, imported, spicenet, data_type, sch, sym
    end
    if File.exist? asy_file = File.join(lib_dir, tr(self_name)+sym)
      if !File.exist?('created') || (File.stat(asy_file).mtime >= File.stat('created').mtime)
        case data_type
        when 'ltspice'
          set_symbol_view(self, 'ltspice', asy2cdraw(asy_file))
        when 'qucs'
          set_symbol_view(self, 'qucs', File.read(asy_file))
        when 'eeschema'
          set_symbol_view(self, 'eeschema', File.read(asy_file))
        when 'xschem'
          set_symbol_view(self, 'xschem', File.read(asy_file))
        end
        flag = true
        if File.exist? yaml_file = File.join(lib_dir, tr(self_name)+'.yaml')
          props = YAML.load(File.read(yaml_file).encode('UTF-8')) || {}
          self.properties = props.to_yaml
        end
      end
    end
    #    end
    if flag
 puts "self.inspect=#{self.inspect}"
      if (sv=self.symbol_view) && sv.size >= 65535
        puts "symbol_view.size exceeded 65535!!!"
        self.symbol_view[65534..-1]=''
      end
      self.save!
      puts "#{self.name} imported"
      imported << self
    end
    imported
  end

  def alb_import_testbench_here data_type, sch, sym, recursion=true
    changed_cells = []
    imported = []
    print "alb_import_testbench_here #{self.class.name}: '#{self.name}' w/ sch='#{sch}'"
    puts recursion ? 'recursively' : ''
#    target = self.instance.cell
#    asy_file = tr(target.name)+sym
#    target = self if File.exist? asy_file
    target = self # to process testbench even if cell is a symbol
    target_name = target.name
    unless ['circuits', 'symbols'].include?(target.library.name) || File.exist?(tr(target_name)+sch)
      target_name = target.name + '@' + target.library.name
    end
    control = nil
    if File.exist? asc_file = tr(target_name)+sch
      spicenet = Spice.new.read_spice_net tr(self.name)+'.net', false
      unless target.name == target.instance.cell.name # special case when testbench name and cell name are the same
        if !File.exist?('created') || File.stat(asc_file).mtime >= File.stat('created').mtime
          if File.basename(Dir.pwd) == 'pictures'
            set_schematic_view(target, 'ltspice', File.open(asc_file, 'r:Windows-1252').read.encode('UTF-8').gsub('µ', 'u').scrub)
          else
            case data_type
            when 'ltspice'
              set_schematic_view(target, 'ltspice', asc2cdraw(asc_file))
            when 'eeschema'
              set_schematic_view(target, 'eeschema', File.read(asc_file))
            when 'xschem'
              set_schematic_view(target, 'xschem', File.read(asc_file))
            when 'qucs'
              set_schematic_view(target, 'qucs', File.read(asc_file))
            end
          end
          target.save!  # missing!
          changed_cells << target
        end
=begin
         if target != self
          control, self_schematic_view = extract_control_and_modify(target)
          set_schematic_view(self, 'ltspice', self_schematic_view)
          self.save!
        else
          control = extract_control target
        end
=end
      end
      imported = alb_import_sub '.', target, recursion, imported, spicenet, data_type, sch, sym
      if File.exist? raw_file = tr(target_name)+'.raw'
        project_sim_dir = self.project.project_sim_dir
        resultsDir = File.join project_sim_dir, self.instance.cell.name, self.instance.name, self.name, self.simulator.name
        if File.directory? resultsDir
          FileUtils.cp raw_file, resultDir
          File.open(File.join(resultsDir, 'completed'), 'w'){}
        end
      end
      
      ti = self.find_or_new_testbench_implementation self.name+'_'+self.simulator.name
      if ti.simulator.nil?
        ti.simulator = self.simulator 
        ti.save!
      end
      if spicenet[:main]
        ti.netlist = spicenet[:main] if ti.netlist.blank? && target == self
        ti.control = control || (spicenet[:control] if ti.control.blank?)
        if target != self
          target.simulator = Simulator.find_by_name('LTspice') if target.simulator.nil?
          set_spicenet target, spicenet, nil
          ti.import_plot '.', tr(target_name)
          target.save!
        else
          ti.import_plot '.', tr(self.name)
        end
        ti.save!
      end
      puts "#{target.class.name} #{target_name} imported"
      puts "#{self.class.name} #{self.name} imported" if target != self
    end
    changed_cells
  end

  def alb_import_testbench lib_dir='.', recursion=true, alb_conf={}
    changed_cells = []
    imported = []
    print "alb_import_testbench #{self.class.name}: '#{self.name}' under '#{lib_dir}' ..."
    puts recursion ? 'recursively' : ''
    target = self.instance.cell
    asy_file = File.join(lib_dir, tr(target.name)+'.asy')
    target = self if File.exist? asy_file
    if File.exist? asc_file = File.join(lib_dir, tr(target.name)+'.asc')
      if !File.exist?('created') || File.stat(asc_file).mtime >= File.stat('created').mtime
        if File.basename(Dir.pwd) == 'pictures'
          set_schematic_view(target, 'ltspice', File.open(asc_file, 'r:Windows-1252').read.encode('UTF-8').gsub('µ', 'u').scrub)
        else
          set_schematic_view(target, 'ltspice', asc2cdraw(asc_file))
        end
        changed_cells << target
      end
      imported = alb_import_sub lib_dir, target, recursion, imported
      ti = self.find_or_new_testbench_implementation self.name+'_'+self.simulator.name
      ti.simulator = self.simulator if ti.simulator.nil?
      lib_temp, artist_states = alb_conf[:topcells][self.name]
      ti.import_plot lib_dir, tr(self.name), artist_states
      target.save!
      puts "#{target.class.name} #{target.name} imported"
      puts "#{self.class.name} #{self.name} imported" if target != self
    end
    changed_cells
  end

  NUMBER_OF_FINGERS = 'nf' unless defined? NUMBER_OF_FINGERS  # Caution! this name depends on PDK

  def get_mos_models done_cells=[]
    models = {}
    return [done_cells, models] if done_cells.include?(self) || get_schematic_view(self).blank?
    inst_name = value = value2 = nil
#    puts "** Schematic view for: '#{self.name}'"
    get_schematic_view(self).each_line{|l|
#      puts l
      if l =~ /SYMATTR +InstName +(\S+)/
        inst_name = $1
      elsif l =~ /SYMATTR +Value +(\S+)/
        value = $1
      elsif l =~ /SYMATTR +Value2 +(.*)/
        value2 = $1
      elsif l =~ /SYMBOL +(\S+) +(\S+) +(\S+) +(\S+)/
        models = get_model_properties models, inst_name, value, value2 
        value = value2 = nil
      end
    }
    models = get_model_properties models, inst_name, value, value2 
    done_cells << self

    props = ((YAML.load(self.properties||'')||{})['cells'])||{}
    props.each_pair{|c, lib|
      library = self.project.libraries.find_by_name lib
      next if library.nil? # special case
      cell = library.find_or_new_cell c
      done_cells, m = cell.get_mos_models done_cells
      puts "mos_models for #{cell.name} = #{m.inspect}"
      models.merge! m
    }
    models.each_value{|v| v.uniq!}
    [done_cells, models]
  end

  def get_model_properties models, name, value, value2 
    return models unless name && name.downcase[0,1] == 'm' && value && value2
    parms, = parse_parameters value2
    models[value] ||= []
    # debugger if parms['l'].nil? || parms['w'].nil?
    models[value] << {'l'=> parm_eval(parms['l']),
                      'w'=> parm_eval2(parms['w'], parms[NUMBER_OF_FINGERS])}
    models
  end
  private :get_model_properties
    
  def create_cdraw_figure
    proj_dir = File.join($proj_repo_dir, self.project.name)    
    pictures_dir = File.join proj_dir, 'pictures', self.library.name, self.name
    pwd = nil
    with_directory(pictures_dir){  # create under self.name temporary directory
      File.open(self.name+'.asc', 'w:Windows-1252'){|f| f.puts get_schematic_view(self).encode('UTF-8', :undef => :replace)}
      props = ((YAML.load(self.properties||'')||{})['cells'])||{}
      lib = nil
      props.each_pair{|c, lib|
        if c.include? '\\\\'
          lib, c = c.split('\\\\')
        end
        library = self.project.libraries.find_by_name lib
        cell = library.find_or_new_cell c
        if cell
          File.open(cell.name+'.asy', 'w:UTF-8'){|f| f.puts get_symbol_view(cell).encode('UTF-8', :undef => :replace)}
        else
          debugger
        end
      }
      props['gnd'] = lib
      File.open(self.name+'.yaml', 'w'){|f|f.puts props.to_yaml}
      File.open('gnd.asy', 'w'){|f| f.puts <<EOH
Version 4
SymbolType BLOCK
LINE Normal -16 48 16 48
LINE Normal 16 48 0 64
LINE Normal 0 64 -16 48
LINE Normal 0 0 0 48
WINDOW 0 48 32 Invisible 0
WINDOW 3 48 64 Invisible 0
PIN 0 0 BOTTOM 0
PINATTR PinName gnd!
PINATTR SpiceOrder 1
EOH
      }
      

#      Dir.chdir('..')
#      self.create_figure # move self.name directory to 'ltspice' under figure directory created
      pwd = File.expand_path(Dir.pwd)
    }
    Dir.chdir(File.join(pwd, '..')){
      self.create_figure # move self.name directory to 'ltspice' under figure directory created
    }
  end

  def on_WSL?
    File.exist?('/proc/version') && `grep -E "(MicroSoft|Microsoft|WSL)" /proc/version` != ''
  end
  private :on_WSL?

  def create_figure
    puts "debug: create_figure called for '#{self.name}' at #{Dir.pwd}"
    figure = nil

    Dir.chdir(self.name) { 
      figure = self.cdraw_figure  # create png and replace figure
    }

    if figure
      ltspice_dir = File.join(RAILS_ROOT, "public/system/figures/#{figure.id}/ltspice")
      FileUtils.rm_r(ltspice_dir, {:force => true}) if File.exist? ltspice_dir
      FileUtils.move(ltspice_dir, ltspice.dir.sub('ltspice', 'broken')) if File.exist? ltspice_dir ### if still exists
      if /mswin32|mingw|cygwin/ =~ RUBY_PLATFORM || on_WSL?()
        FileUtils.cp_r self.name, ltspice_dir
      else
        FileUtils.move self.name, ltspice_dir
      end
      if File.exist? pic = File.join(ltspice_dir, self.name)
        puts "'#{pic}' created"
      end
    end
  end  
  
  def cdraw_figure dir = '.'
    figure = nil
    self.figures.each{|f|
      if f.figure.original_filename == tr(self.name) + '.png'
        figure = f
      end
    }

    asc_file = File.join(dir, tr(self.name)+'.asc')
    if figure
      puts "#{asc_file} modified at #{File.stat(asc_file).mtime}"
      puts "figure #{figure.id} updated at #{figure.updated_at}"
    end
    if figure && (update = figure.updated_at) > (mtime=File.stat(asc_file).mtime)
      puts "png for #{asc_file} (modified at #{mtime}) is not updated (already updated at #{update})"
      return nil
    end
    
    data = cdraw asc_file, '.png'
    unless data
      puts "error: '#{tr(self.name)}.png' was not created due to failure in cdraw"
      return nil
    end
    
    file = StringIO.new data
    file.class.class_eval { attr_accessor :original_filename, :content_type }
    file.original_filename = tr(self.name) + '.png'
    file.content_type = 'application/png'
    
    figure ||= Figure.new
    figure.figure = file
    figure.send("#{self.class.name.downcase}=", self)
    if figure.id
      puts "'#{figure.figure.url}' replaced"
    else
      puts "'#{figure.figure.url}' created"
    end
    figure.save!
    figure
  end    

  def cdraw2asc schematic_view, control, model_choices, mos_models, lw_correction, cdf=nil
    c2a = Cdraw2ltsp.new cdf
    c2a.cdraw2ltsp(schematic_view, control, model_choices, mos_models, lw_correction)
  end

  def cdraw2asy symbol_view
    c2a = Cdraw2ltsp.new
    c2a.cdraw2ltsp_symbol(symbol_view).encode('UTF-8', invalid: :replace)
  end

  def asc2cdraw asc_file
    a2c = Ltsp2cdraw.new
    a2c.ltsp2cdraw(File.open(asc_file, 'r:Windows-1252').read.encode('UTF-8', invalid: :replace))
  end

  def asy2cdraw asy_file
    a2c = Ltsp2cdraw.new
    a2c.ltsp2cdraw_symbol(File.open(asy_file, 'r:Windows-1252').read.encode('UTF-8').gsub('µ', 'u').scrub)
  end
end
