# -*- coding: utf-8 -*-
require 'pp'
require 'fileutils'
require 'rubygems'
#require 'ruby-debug'
#load 'ltspice.rb'
#load 'spectre.rb'

#def name
#  self.class.name
#end
#public :name

def jupyter_ready?
  true
end

def get_schematic_view target, type='ltspice', view_type='schematic'
  start_tag, end_tag = type_tags type, view_type
#  puts "start_tag=#{start_tag}, end_tag=#{end_tag} for type='#{type}'&view_type='#{view_type}'&target=#{target.inspect}"
  if target.nil? || (result = target.send("#{view_type}_view")).nil?
    return ''
  else
    new_result = nil
    result.each_line{|l|
      #      puts "l=#{l}, new_result=#{new_result.inspect}"
      l.chomp!   # l seems to end with ^M followed by LF, so chomp!
      if new_result
        if l.include? end_tag[0..20]
          return new_result.strip + "\n"
        end
        new_result << l + "\n"
      elsif l.include? start_tag[0..20]
        new_result = (type=='qucs' && view_type=='schematic')? l + "\n" : ''  # <Qucs Schematic 0.0.19>\n needed
      end
    }
    result.strip!
    return (type == 'ltspice' && result[0,1]!='<')? result : '' # backward compatibility for ltspice data
  end
end

def get_symbol_view target, type='ltspice'
  get_schematic_view target, type, 'symbol'
end

def set_schematic_view target, type, view_txt, view_type='schematic'
  start_tag, end_tag = type_tags type, view_type
  new_lines = "#{start_tag}\n"
  if view_txt
    view_txt.each_line{|l|
      l.chomp!
      next if type == 'qucs' && ((view_type == 'symbol' && l.include?('Qucs Symbol'))||
                                 (view_type == 'schematic' && l.include?('Qucs Schematic')))
      new_lines << l+"\n"
    }
  end
  new_lines << "#{end_tag}\n"
  
  if lines = target.send("#{view_type}_view")
    result = ''
    flag = 0
    flag_old_format = 1
    lines.each_line{|l|
      flag_old_format = 0 if l =~ /<\/#{type_tags 'all'}/
      if flag == 1
        if l.include? end_tag[0..20]
          flag = -1
          result << new_lines
        end
        next
      elsif l.include? start_tag[0..20]
        flag = 1
        next
      else
        result << l
      end
    }
    if flag == 0
      if flag_old_format == 1
        target.send("#{view_type}_view=", "<ltspice #{view_type}>\n" + lines.chomp + "\n" + "</ltspice #{view_type}>\n" + new_lines)
      else
        target.send("#{view_type}_view=", lines.chomp + "\n" + new_lines)
      end
    else
      target.send("#{view_type}_view=", result)
    end
  else
    target.send("#{view_type}_view=", new_lines)
  end
  new_lines
end
  
def set_symbol_view target, type, view_txt
  set_schematic_view target, type, view_txt, 'symbol'
end

def type_tags type, view_type=nil
  case type
  when 'ltspice'
    start_tag = "<ltspice #{view_type}>"
    end_tag = "</ltspice #{view_type}>"
  when 'eeschema'
    start_tag = "<eeschema #{view_type} Version 4>"
    end_tag = "</eeschema #{view_type} Version 4>"
  when 'xschem'
    start_tag = "<xschem #{view_type} file_version 1.1>"
    end_tag = "</xschem #{view_type} file_version 1.1>"
  when 'qucs'
    start_tag = "<Qucs #{view_type.capitalize} 0.0.21>"
    end_tag = "</Qucs #{view_type.capitalize} 0.0.21>"
  when 'all'
    return 'ltspice|eeschema|xschem|Qucs'
  end
  [start_tag, end_tag]
end
private :type_tags

require 'tmpdir'

def mytmp file=''
  file.sub!(/\/tmp\/*/, '')
  if file.strip == '' 
    Dir.tmpdir
  else
    File.join Dir.tmpdir, file
  end
end

def append_url obj, header, url_text, tags
  description = obj.body || ''
  append_text = "<div style=\"text-align: right;\"><a href=\"http:#{url_text}\" title=\"#{tags}\">#{header}</a></div>\r\n"
  return if description.include? append_text 
  description << append_text
  obj.body = description
  obj.save!
end

def write_models resultsDir, model_libraries, sections, mappings, sim, params=nil, mos_models=nil, param_vals=nil, temperature=27
  simtype = sim.name
  simulator = eval(simtype).new
  model_choices = {}
  lw_correction = {}
  model_script = '' 
  
  model_libraries.each_with_index{|model_lib, i|
    next if model_lib.nil?
    model_lib.reload   # this is nessary to avoid 'stale object'
    unless model_lib.simulator == sim
      model_lib.simulator = sim
      model_lib.save!  # convert models if necessary
      model_lib.reload # this is necessry for model_lib.model_library_implementatins to work
    end
    
    #      if model_lib.models.blank? || (mappings[i] && mappings[i].downcase == 'none')
    if model_lib.models.blank? && (mappings[i] && mappings[i].downcase == 'none') # special tricky case
      included=[]
      model_file = nil
      #        raise "#{model_lib.original_path} does not exist" unless File.exist? model_lib.original_path
      Dir.chdir(File.dirname(model_lib.original_path)){
        model_file = set_models_sub(File.basename(model_lib.original_path), absolute_path(resultsDir+'/models'), params, included)
        model_file = File.join('./models', model_file)
      }
      ahdl_files = Dir.glob(File.dirname(absolute_path(model_lib.original_path))+'/*.va')
      ahdl_files.each{|f| FileUtils.cp f, resultsDir}
    else	# normal case 
      mapping = nil
      mapping = eval( '{' + mappings[i] + '}' ) if mappings[i] && mappings[i].strip.size > 0
      dir = File.join resultsDir, 'models', File.dirname(model_lib.name)
      FileUtils.mkdir_p dir unless File.directory? dir
      Dir.chdir(dir){
        if simulator.use_section_in_model_library?
          mc, lw_c = model_lib.write [], sim, temperature, params, nil, mapping, nil, param_vals
        else
          #          puts "sections[i] = #{sections[i]}"
          #          debugger if sections[i] == '*tt'
          mc, lw_c = model_lib.write [], sim, temperature, params, mos_models, mapping, sections[i], param_vals
          model_choices.merge! mc
          lw_correction.merge! lw_c
        end
      }
      #        if object.class == Instance
      #          @models_used.each{|m| m.instance = object; m.save}
      #        end
      #        model_file = './models/' + File.basename(model_lib.name)
      
      model_file = './models/' + model_lib.name
    end
    
    if simtype.include?('spectre') || simtype.include?('Spectre')
      include = 'include'
    else
      include = '.include'
    end
    if sections[i] && sections[i] != ''
      secs = sections[i].gsub(',',' ').split
      flag = true
      secs.each{|sec| flag = false if sec.start_with? '*'}
      secs.each{|section|
        unless flag || section.start_with?('*')
          if simtype.include?('spectre') || simtype.include?('Spectre')
            model_script << '//' 
          else
            model_script << '*' 
          end
        end
        section.sub! /^\*/,''
        if simtype == 'Hspice'
          model_script << ".lib \"#{model_file}\" #{section}\n"
        else
          if simulator.use_section_in_model_library?
            model_script << "#{include} \"#{model_file}\" section=#{section}\n"
          else
            model_script << "#{include} \"#{model_file}+#{section}\"\n"
          end
        end
      }
    else
      model_script << "#{include} \"#{model_file}\"\n"        
    end
  }
=begin
  if sim.name == 'QUCS'
    Dir.chdir(resultsDir){
      model_script = expand_include model_script
    }
  end
=end
  return [model_script, model_choices, lw_correction]
end

def eng2number val
  return val.to_f if numeric?(val)
  if val.strip.downcase =~ /(^.*\d)(meg)([^fpnumkg]*)/
    return $1.to_f * 1e6
  end
  val.strip.downcase =~ /(^.*\d)([fpnumkg])([^fpnumkg]*)/
  number = $1
  unit = $3
  m=1
  case $2
  when 'f'; m = 1e-15
  when 'p'; m = 1e-12
  when 'n'; m = 1e-9
  when 'u', 'µ'; m = 1e-6
  when 'm'; m = 1e-3
  when 'k'; m = 1e3
  when 'g'; m = 1e9
  end
  number.to_f * m
end
  
def remove_curly_brackets v
  if v =~ /^\{(.*)\}/
    v = $1
  end
  return v
end

def parse_params_wo_singles line
  params = {}
  line.scan(/(\S+) *= *([^ =]+)( +|$)/).each{|n, v,|
    params[n] = remove_curly_brackets v
  }
  params
end

def parse_parameters line
  start = Time.now
  params = {}
  singles = []
  return [params, singles] if line.nil?
  line2 = line.strip.dup
  pa = nil
  count = 0
  while line2.size > 0 && count < 10000
    count = count + 1
    if line2 =~ /^( *([^ =]+) +)[^ =]/
      singles << $2
      line2.sub! $1, ''
#    elsif line2 =~ /^( *([^ =><]+) *= *)/
    elsif line2 =~ /^( *(\w+) *= *)/
      pa = $2.strip
      line2.sub! $1, ''
#      i = (line2 =~ /( +([^ =\)\(><]+) *=[^=] *)/) || -1
      i = (line2 =~ /( +(\w+) *=[^=] *)/) || -1
      v = line2[0..i]
      line2[0..i] = ''
      params[pa] = v.strip if v
    elsif line2 =~ /^( *(\S+) *)$/
      singles << $2
      line2.sub! $1, ''
    end
    puts "!!! #{count}:#{line2}" if count == 10000
  end
=begin
  puts "singles: #{singles.inspect}"
  puts "params: #{params.inspect}"
  puts "Elapse: #{Time.new - start}"
=end
  [params, singles]
end

def split_parameters line
  result = []
  return result if line.nil?
  line2 = line.strip.dup
  pa = nil
  count = 0
  while line2.size > 0
    count = count + 1
    if line2 =~ /^( *([^ =]+) +)[^ =]/
      line2.sub! $1, ''
      #        result << $1 # maybe .params
    elsif line2 =~ /^( *(\w+) *= *)/
      pa = $2.strip
      line2.sub! $1, ''
      i = (line2 =~ /( +(\w+) *=[^=] *)/) || -1
      v = line2[0..i].strip
      line2[0..i] = ''
      if v
        if v.start_with? "{"
          result << [pa, v[1..-2]]
        elsif v =~ /^ *(-*[0-9]+) *([fpnumkKMgGtT])/ || v =~ /^ *(-*[0-9]+\.[0-9]*) *([fpnumkKMgGtT])/ 
          val = $1.to_f
          case $2
          when 'f'; eng = 1e-15
          when 'p'; eng = 1e-12
          when 'n'; eng = 1e-9
          when 'u'; eng = 1e-6
          when 'm'; eng = 1e-3
          when 'k', 'K'; eng = 1e3
          when 'M'; eng = 1e6
          when 'g', 'G'; eng = 1e9
          when 't', 'T'; eng = 1e9
          end
          result << [pa, val*eng]
        else
          result << [pa, v]
        end
      end
    end
  end
  result
end


def slice_block line2
  c = 1
  for i in 1..line2.length-1
    if line2[i,1] == '('
      c = c + 1
    elsif line2[i,1] == ')'
      c = c - 1
      return i if c == 0
    end
  end
  puts "line2='#{line2}'"
debugger
  raise "Syntax error: '#{line2}' is not closed"
end

def convert_to_if orig_line
  line = orig_line.dup
  # convert c? d:e like : ((pm>=0)?((pm==0)?1000:pm):pmc)
  #     (c==0)?(zzrecm15_cap_area*zzrecm15_area+zzrecm15_cap_peri*zzrecm15_perim):c
  #     ((zzrecm15_cc<zzrecm15_c_bound)?1:0)*((area==0)?1:0)*((perim==0)?1:0)
  #     (perim==0)?4*sqrt(zzrecm15_area):(perim)
  # to below
  # "if(#{c}, #{convert_to_if d.strip}, #{convert_to_if e.strip})"
  if i = line.index('(')
#  puts "convert_to_if: #{line}"
    k = slice_block line[i..-1]
 #   puts "core: #{line[i+1..i+k-1]}, rest: #{line[i+k+1..-1]}, i = #{i}"
    if i == 0
      '(' + convert_to_if_core(line[i+1..i+k-1]) + ')' + convert_to_if(line[i+k+1..-1])
    else
      line[0..i-1] + '(' + convert_to_if_core(line[i+1..i+k-1]) + ')' + convert_to_if(line[i+k+1..-1])
    end
  else
    line
  end
end

def convert_to_if_core v2
#  puts "[v2=]#{v2}" # v2=((z1 - min(zzd1,zdth)) * 1e+6),zc2hm
  if v2[0,1] == '('   # (....)?v3 
    i = slice_block v2
    c = v2[0..i]
    v2[0..i] = ''
#    puts " c=#{c}, v2=#{v2}"
    if v2 =~ /\?(.*)/
      v3 = $1
    else
      return "#{convert_to_if c}#{v2}" # c is a function arguments!
    end
  elsif v2 =~ / *([^?\(\)]+) *\?(.*)/ # c?v3
    c = $1
    v3 = $2
  elsif v2 =~ /^ *! *\((.*)\)/ #     like '! (lp!= 1)'
    return "inv(#{convert_to_if_core $1})"
  elsif v2 =~ /^[^\(]*[><=]/ || v2 =~ /^[^\(]*!=/
    return "if(#{v2}, 1, 0)"
  else
    return convert_to_if v2
  end

  raise "Error: '#{c} + #{v3}' cannot be converted to if clause" unless v3.include?(':')
#  puts "v3=#{v3}"
  if v3[0,1] == '('      # (d):e
    i = slice_block v3
    d = v3[0..i]
    v3[0..i] = ''
    v3 =~ /:(.*)/
    e = $1
    raise "Error: cannot convert '#{d}:' to if clause" if e.nil? 
  elsif v3 =~ /([^\(\)]*):(.*)/ # d:e
    d = $1
    e = $2
    raise "Error: cannot convert '#{v3}:' to if clause" if d.nil? || e.nil? 
  end
  "if(#{c}, #{convert_to_if d.strip}, #{convert_to_if e.strip})"
end

def get_upload_dir project
  if File.directory? File.join(RAILS_ROOT, 'public/system/simulation')
    dir = project.create_repo 'public/system/simulation'
  else
    dir = project.create_repo 'public/simulation'
  end
  puts "upload_dir='#{dir}'"
  dir
end

def with_directory out_dir 
  FileUtils.mkdir_p(out_dir) unless File.directory?(out_dir) 
  Dir.chdir(out_dir){|dir|
    yield dir
  }
end

def get_base_script pp
  postpr, atype = yaml_like_load pp
  atypes = analysis_types(atype)
  postpr.each_key{|view|
    if atypes.include?(atype[view])
      return [view, postpr[view], atype[view]]
    end
  }
  nil
end

def analysis_types atype
  (atype.values - atype.keys.map{|k| atype[k] == k ? nil : k}).uniq
end

def yaml_like_load text
  result = {}
  analysis_type = {}
  key=nil
  text && text.each_line{|l|
    l.chomp!
    next if l.strip.size == 0
    next if /^ *[#\*]/ =~ l        # skip comments
    next if /^ *([^ ]*): *$/ =~ l  # keep contents intact if only key is given
    if /^ *([^ ]*): *(\S*) *$/ =~ l || /^#* *(\S+) *: *(\S+) *\{ *(\S+) *, *(\S*) *\} *$/ =~ l
      key = $1
      result[key] = '# ' + l +"\n"
      analysis_type[key] = $2
      #      analysis_type[$1] << '.'+$2 unless $2.include?('.') || $2.size==0
      sweep = $3     # not used
      parameter = $4 # not used
    else
      result[key] << l + "\n" if key
    end
  }
  return result, analysis_type
end

def script2performances script
  return nil if script.nil? 
  perfs = []
  script.each_line{|l|
    l.sub!(/\".*$/, '')
    l.sub!(/\'.*$/, '')
    if l =~ /(@\S+) *=/
      perfs << $1
    end
  }
  perfs.uniq
end

def postprocess_sequentially resultsDir, sim, tb
  Dir.chdir(resultsDir){
    ti = pick_object tb.testbench_implementations, tb.simulator
    @ltspice = @spectre = eval(tb.simulator.name).new
    pp = "#{ti.postprocess}\n#{tb.postprocess}\n#{self.postprocess}"
    start, = get_base_script pp
    pp_seq = postpr_seq pp, start
    eval self.control.gsub(/\n/, ";\n") # set @parameters and @assignments
    pp_seq[1..-1] && pp_seq[1..-1].each{|script|
      do_postprocess tb, sim, resultsDir, script
    }
  }
end

def postpr_seq pp, view
  postprocess, atype = yaml_like_load pp
  link = {}
  atype.each_pair{|key, a|
    link[a] ||= []
    link[a] << key
  }
  puts "link: #{link.inspect}"
  pp_seq = postpr_seq_sub link, view, seq = []
  puts "postprocess_sequence: #{pp_seq.inspect}"
  pp_seq.map{|p| postprocess[p]}
end

def postpr_seq_sub link, a, seq = []
  if link[a] && link[a].size > 0
    result = []
    link[a].each{|b|
      result = result + postpr_seq_sub(link, b, [b])
    }
    [a] + result
  else
    seq
  end
end
private :postpr_seq_sub

def do_postprocess tb, sim, resultsDir, script
  puts "***postprocess script:\n#{script}"
  view, parent, sweep, parameter = parse_script_header script
  ti = pick_object tb.testbench_implementations, sim
  parent_script, = get_script parent, "#{ti.postprocess}\n#{tb.postprocess}\n#{self.postprocess}"
  return if parent_script.nil?
  @performances = script2performances(parent_script)
  raise "results for #{parent}(#{@performances}) not available" unless File.exist? @performances.join
  @result = Results.new
  parameters, @assignments = @result.restore @performances.join
  return unless sweep.nil? || parameters.include?(sweep)
  new_parameters = parameters - [sweep]
  new_performances = script2performances script
  new_result = Results.new
  puts "new_performances = #{new_performances.inspect}"
  puts "new_parameters = #{new_parameters.inspect}"
  new_result.init new_performances, new_parameters
  data = []

  new_assignments = []
  @assignments.each{|values|
    new_values = []
    (new_parameters - [parameter]).each{|p|
      new_values << values[@parameters.index(p)]
    }
    unless new_assignments.include? new_values
      new_assignments << new_values 
    end
  }
  new_assignments.each{|new_values|
    if parameter && parameter.strip != ''
      y_fields = []
      p_values = @result.get(parameter).uniq

      if vs = tb.view_settings.find_by_name(view)
        plot = self.find_or_new_plot_instance self.name + '_' + vs.name
        plot.xaxis = 'auto'
        plot.yaxis = 'auto'
        plot.view_setting = vs if plot.class == PlotInstance
        plot.save!
      end
      p_values.each_with_index{|pv, y_index|
        condition = ''
        (new_parameters - [parameter]).each_with_index{|p, i|
          eval "#{p}=#{new_values[i]}"
          puts "#{p}=#{new_values[i]}"
          new_result.set p, new_values[i]
          condition << " && value('#{p}', i) == #{new_values[i]}"
        }
        @indices = assignments_filter "value('#{parameter}', i) == #{pv}" + condition
        new_result.set parameter, pv
        dir = "#{parameter}=#{pv}" 
        File.directory?(dir) || Dir.mkdir(dir)
        Dir.chdir(dir){
          puts "*** eval at #{Dir.pwd}"
          eval script
          if vs = tb.view_settings.find_by_name(view)
            plotData = File.join(resultsDir, dir, vs.file)
            #  debugger unless File.exist? File.join(RAILS_ROOT, plotData)
            if self.class == CellView
              simulation = Simfile.new
              simulation.name = plotData
              simulation.simulator = sim.name
              simulation.plot_instance = plot
              simulation.save!
            elsif self.class == ModelView
              simulation = ModelSimulation.new
              simulation.name = plotData
              simulation.simulator = sim.name
              simulation.model_plot = plot
              simulation.save!
            end
          end
        }
        new_performances && new_performances.each{|p|
          new_result.set p, eval(p)
        }
      }
      new_result.save new_performances.join if new_performances.size > 0
    else
      @indices = assignments_filter ''
      puts "*** eval at #{Dir.pwd}"
      eval script
      if vs = tb.view_settings.find_by_name(view)
        plot = self.find_or_new_plot_instance self.name + '_' + vs.name
        plot.xaxis = 'auto'
        plot.yaxis = 'auto'
        plot.view_setting = vs if plot.class == PlotInstance
        plot.save!
        plotData = File.join(resultsDir, vs.file)
        #  debugger unless File.exist? File.join(RAILS_ROOT, plotData)
        if self.class == CellView
          simulation = Simfile.new
          simulation.name = plotData
          simulation.simulator = sim.name
          simulation.plot_instance = plot
          simulation.save!
        elsif self.class == ModelView
          simulation = ModelSimulation.new
          simulation.name = plotData
          simulation.simulator = sim.name
          simulation.model_plot = plot
          simulation.save!
        end
      end
    end
  }
end

def assignments_filter condition
  indices = @assignments.search_indices{|i|
    if condition && condition.strip != ''
      eval condition
    else
      true
    end
  }
end
private :assignments_filter

def get_script view, pp
  postpr, atype = yaml_like_load pp
  atypes = analysis_types(atype)
  script = postpr[view]
  [script, atypes.include?(atype[view])]
end

def parse_script_header script
  if script =~ /^#* *(\S+) *: *(\S+) *\{ *(\S+) *, *(\S*) *\} *$/
    view = $1
    parent = $2
    sweep = $3
    parameter = $4
    return [view, parent, sweep, parameter]
  elsif script =~ /^#* *(\S+) *: *(\S+)/
    view = $1
    parent = $2
    return [view, parent]
  end
end

def get_results *nodes
  data = []
  nodes.each{|name|
    if results = @result.get(name)
      row_data = []
      @indices.each{|i|
        row_data << results[i]
      }
      data << row_data
    end
  }
  puts "nodes = #{nodes.inspect}"
  puts "data = #{data.inspect}"
  Wave.new nodes, data.transpose
end

def compare_netlist neta, sima, netb, simb, element_name_map={}, inhibited_node_map={}
  sim = Spice.new
  ckta = sim.read_spice_net_core neta
  cktb = sim.read_spice_net_core netb
  $stdout = IO_Tee.new(STDOUT)
  log = open(mytmp('/tmp/compare'),'w')
  $stdout.add(log)
  c = SPICE_compare.new ckta, sima, cktb, simb
  c.compare element_name_map, inhibited_node_map
  $stdout.flush
  $stdout = STDOUT
  result = File.read mytmp('/tmp/compare')
  File.delete mytmp('/tmp/compare')
  result
end

def instance_run_env user_instance, *opts
  unless self.class == CellView
    raise 'instance_run_env must be called from CellView'
  end
  cell = self.cell
  inst = cell.instances.find_by_name user_instance
  if opts && opts.size > 0 && tb_name = opts[:testbench]
    testbench = inst.testbenches.find_by_name tb_name
  else
    testbench = inst.testbenches.first
  end
  class_name = 'Run'+testbench.project.name+user_instance
  tmp_inst, tmp_sim, resultsDir = testbench.get_results_dir 
  Dir.chdir(resultsDir){
    file = class_name+'.rb'
    raise "#{file} does not exist" unless File.exist? file
    load file
    instance = eval(class_name).new
    yield instance
  }
end

def proj_dir_init proj_dir, name, no_models=false
  unless File.exist? proj_dir
    FileUtils.mkdir_p proj_dir
    Dir.chdir(proj_dir){|dir|
      system "git init"
      File.open('.git/description', 'w'){|f| 
        f.puts "ADE repository for '#{name}'"
      }
      FileUtils.mkdir 'models' unless no_models
    }
  end
end

def parm_eval p
  return if p.nil?
  def pPar p
    p
  end
  # 	p is like: "{(2u)*(8)}"
  begin
    value = eval p.gsub(/[\{\}]/,'').gsub('u','*1e-6').gsub('n','*1e-9')
    return value.to_s
  rescue Exception => exc # if p is like p='{L}';  Exception captures any error in eval
    return nil
  end
end  

def parm_eval2 p1, p2
  return nil if p1.nil?
  # p is like: "{(2u)*(8)}"
  begin
    value1 = eval p1.gsub(/[\{\}]/,'').gsub('u','*1e-6').gsub('n','*1e-9')
    return value1.to_s unless p2
    value2 = eval p2.gsub(/[\{\}]/,'').gsub('u','*1e-6').gsub('n','*1e-9')
    return (value1/value2).to_s
  rescue Exception => exc
    return nil
  end
end  

def name_addition parameters
  idx = parameters.index /$/
  parameters[0, idx].strip.gsub(/[ ;,'] */,'')
end

def db_migrate
  log = ''
  Dir.chdir(File.join(RAILS_ROOT)){
    log = `rake db_migrate`
  }
  printf log << "*** database migrated\n"
  log
end


def wget_install file
  log = ''
  Dir.chdir(mytmp '/tmp'){
    log << `rm -f #{file}` if File.exist? file
    if RUBY_PLATFORM =~ /darwin/
      log << `wget --no-cache http://alb.anagix.com:8180/dist/MacOSX/#{file}`
    elsif RUBY_PLATFORM =~ /freebsd/
      log << `wget --no-cache http://alb.anagix.com:8180/dist/freebsd/#{file}`
    elsif RUBY_PLATFORM =~ /x86_64-linux/
      log << `wget --no-cache http://alb.anagix.com:8180/dist/x86_64/#{file}`
    else
      log << `wget --no-cache http://alb.anagix.com:8180/dist/#{file}`
    end
  }
  if RUBY_PLATFORM =~ /darwin/
    Dir.chdir('/Applications'){
      puts log << "Current directory is '#{Dir.pwd}'\n"
      log << `tar xvzf #{mytmp file}`
      log << `rm #{mytmp file}`
    }
  else
    Dir.chdir(ENV['HOME']){
      puts log << "Current directory is '#{Dir.pwd}'\n"
      log << `tar xvzf #{mytmp file}`
      log << `rm #{mytmp file}`
    }
  end
  printf log << "*** #{file} installed\n"
  log
end

def gem_install file
  log = ''
  puts log << `gem install #{file} --no-ri --no-rdoc`
  log
end

def tr str
  str.tr('\/:*?"><|', '_________') # avoid DOS inhibited chars
end

def create_figures src_path, library
#  debugger if src_path.nil? || library.name.nil?
  dir = File.join(src_path, 'pictures', library.name) 
  File.directory?(dir) && Dir.chdir(dir){ 
    library.cells.each{|cell|
      copy_asys(src_path, cell.name) && cell.create_figure
      cell.instances.each{|inst|
        inst.testbenches.each{|tb|
          if tb.properties && lib_name = (YAML.load(tb.properties)||{})['lib_name']
            lib_dir = File.join(dir, '..', lib_name)
            File.directory?(lib_dir) && Dir.chdir(lib_dir){
              copy_asys(src_path, tb.name) && tb.create_figure
            }
          else
            copy_asys(src_path, tb.name) && tb.create_figure
          end
        }
      }
    }
  }
end

def copy_asys src_path, name
  if File.exist? yf=name+'.yaml'
    Dir.mkdir name unless File.directory? name
    if File.exist? name+'.asc'
      File.open(name+'/'+tr(name)+'.asc', 'w'){|f|
        File.read(name+'.asc').encode('UTF-8', invalid: :replace).each_line{|l|
          if l =~ /SYMBOL +([^ ]+) +(.*)$/
            f.puts "SYMBOL #{tr($1)} #{$2}"
          else
            f.print l
          end
        }
      }
      cells = (YAML.load(File.read(yf).encode('UTF-8', invalid: :replace))||{})
      if cells.include?('cells') && cells = cells['cells'] 
        cells && cells.each_pair{|s, l|
          #      FileUtils.cp File.join(src_path, 'pictures', l, s+'.asy'), name+'/'
          next if s == 'thick_wires' #### until YAML file structure is changed
          File.open(name+'/'+tr(s)+'.asy', 'w'){|f|
            src = File.join(src_path, 'pictures', l, s+'.asy')
            f.print File.read(src).encode('UTF-8') if File.exist? src
          }
          src=File.join(src_path, 'pictures', l, s+'.asc')
          FileUtils.cp src, name+'/' if File.exist? src
        }
        FileUtils.cp yf, name + '/' # copy yaml file as well
        true	
      end
    end
  end
end

def project_repository name
  return nil unless $proj_repo_dir
  path = File.join $proj_repo_dir, name
  return repo = Repo.new(path) if File.exist?(path) and File.exist?(File.join(path, '.git'))
end

def assist_dir obj
  dir = File.join(RAILS_ROOT, 'public/system/assist', obj.project.name.gsub(' ', '_'))
  FileUtils.mkdir_p dir unless File.directory? dir
  dir
end

def delete_repo obj, tool
  Dir.chdir(assist_dir obj){
    ass_dir = File.join obj.class.name.tableize, obj.id.to_s, tool
    if File.directory? ass_dir
      FileUtils.chmod_R(0777, ass_dir)
      FileUtils.rm_rf ass_dir
      puts flash[:notice] = "#{File.expand_path ass_dir} removed"
    else
      puts flash[:error] = "#{File.expand_path ass_dir} does not exist"
    end
    redirect_to :controller => obj.class.name.tableize, :action => 'show', :id => obj.id
  }
end

def create_repo obj, tool, redirect=true
  Dir.chdir(assist_dir obj){
    ass_dir = File.join obj.class.name.tableize, obj.id.to_s, tool
    flash[:notice] = ''
    if File.directory? ass_dir
      FileUtils.chmod_R(0777, ass_dir)
      FileUtils.rm_rf ass_dir
      puts flash[:notice] << "#{File.expand_path ass_dir} removed; "
    end
    FileUtils.mkdir_p ass_dir
    Dir.chdir(ass_dir){
      system 'git init'
      system "touch created; git add .; git commit -am 'init'"
    }
    puts flash[:notice] << "#{File.expand_path ass_dir} created"
    redirect_to :controller => obj.class.name.tableize, :action => 'show', :id => obj.id if redirect
  }
end

def send_rev obj, tool, target_version = 'HEAD'
  gzip_file = "#{obj.name}_#{target_version}.tar.gz".gsub(' ','_')
  ass_dir = File.join(assist_dir(obj), obj.class.name.tableize,
                      obj.id.to_s, tool)
  if File.directory? ass_dir
    Dir.chdir(ass_dir){
      mytmp_gzip_file = mytmp gzip_file
      system "git archive --format=tar #{target_version} | gzip > #{mytmp_gzip_file}"
      if File.exist? mytmp_gzip_file
        send_file mytmp_gzip_file
      else
        redirect_to :controller => obj.class.name.tableize, :action => 'show', :id => obj.id
      end
    }
  else
    flash[:error] = _("#{ass_dir} is not a repository")
    redirect_to :controller => obj.class.name.tableize, :action => 'show', :id => obj.id
  end
end

def writable? url
  url && url =~ /https:\/\/(\S+):(\S+)@github.com\/(\S+)\/(\S+)\.git/ # password given
end

def ltsp_export_all proj
  files = []
  cdf = {}
  proj.libraries.each{|lib|
    lib.cells.each{|cell|
      cell2libs = cell.ltsp_check_hier
      files, = cell.ltsp_export_prep files, cdf, cell2libs, nil, true, false
      cell.instances.each{|inst|
        inst.testbenches.each{|tb|
          files, = cell.ltsp_export_prep files, cdf, {}, nil, true, false
        }
      }
    }
  }
  files
  puts "#{files.inspect} created"
end

def export_all lib, tool, sf_scr, sf_mdl
  files = []
  lib.cells.each{|cell|
    ci = pick_object cell.cell_implementations, tool
    f = cell.name + sf_mdl
    fout_print f, ci.netlist
    files << f
    
    cell_props = YAML.load(cell.properties || '') || {}
    scr_files = cell_props[tool.name][sf_scr.sub('.','')+'_files']
    scr_files.each_pair{|f, c|
      fout_print f, c
      files << f
    }
    
    cell.instances.each{|inst|
      inst.testbenches.each{|tb|
        if ti = pick_object(tb.testbench_implementations, tool)
          f = tb.name + sf_scr
          fout_print f, ti.control
          files << f
        end
      }
    }
  }
  files
  puts "#{files.inspect} created"
end
  
def manage_repository_sub obj, tool, command, github=nil
  ass_dir = File.join(assist_dir(obj), obj.class.name.tableize, obj.id.to_s, tool)
  unless File.exist?(ass_dir)
    if command == 'browse'
      send_data({}.to_yaml, :type => 'application/alb', :disposition => 'inline')
      return
    end
    create_repo obj, tool, false 
  end
  repo = Repo.new ass_dir
  config = Grit::Config.new(repo)
  Dir.chdir(ass_dir){
    case command
    when 'browse'
      repo = Repo.new ass_dir
      config = Grit::Config.new(repo)
      if writable?(config['remote.origin.url'])   # always sync if remote origin exists (and writeable)
        puts `git pull origin master`
      end
      data = send_rev_list obj, tool, repo, config
    when 'push'
      if github
        if tool == 'LTspice' && obj.class == Project
          ltsp_export_all obj
        elsif tool == 'Simulink' && obj.class == Library
          export_all obj, Simulator.find_by_name(tool), '.m', '.mdl'
        elsif tool == 'Xcos' && obj.class == Library
          export_all obj, Simulator.find_by_name(tool), '.sci', '.xcos'
        end
        system "git add .; git commit -am 'init'"
        if config['remote.origin.url'] = github
          data = `git push origin master`
        end
      end
    when 'pull'
      if github
        config['remote.origin.url'] = github
        data = `git pull origin master`
        if tool == 'LTspice' 
          if obj.class == Library
            obj.project.alta_build '.', obj.name
          else
            obj.alta_build '.'
          end
        end
      end
    end
    send_data data.to_yaml, :type => 'application/alb', :disposition => 'inline'
  }
end

def send_rev_list obj, tool, repo, config
  if repo
    data = {:rev_list => obj.rev_list(repo), :remote => config['remote.origin.url'],
            :obj_id => "#{obj.class.name.tableize}.#{obj.id}"}
  else
    data = {:obj_id => "#{obj.class.name.tableize}.#{obj.id}"}
  end
end

=begin
def project_repository name
  path = project_source_exist?(name)
  return repo = Repo.new(path) if path && File.exist?(File.join(path, '.git'))
end

def project_source_exist? name
  return nil unless $proj_repo_dir
  path = File.join $proj_repo_dir, name
  path if File.exist? path
end
=end

def copy_file_to_load file
  FileUtils.copy File.join(RAILS_ROOT, 'lib', file), file
  return "load '#{file}'\n"
end

def limit string, length
  return '' unless string
  if string.length > length
    string[0..length]+'...'
  else
    string
  end
end

# def eval_script script
#   eval '"'+script.gsub("\\", "\\\\\\\\").gsub("\"","\\\"")+'"'
# end

def unzip gzip_file
  puts "unzip #{gzip_file} at #{Dir.pwd}"
  basename = File.basename(gzip_file)   # .downcase --- for some reason converted to downcase
  if File.extname(gzip_file) =~ /\.alb|\.zip/
    files = []
    `unzip -o '#{gzip_file}'`.each_line{|l| # -o overwrite
      l =~ / *inflating: +(\S+)/
      files << $1
    }
    return [basename.gsub('.zip', ''), files.compact]
  elsif File.extname(gzip_file) == '.gz' || File.extname(gzip_file)== '.tgz'
    files = `tar xvzf '#{gzip_file}'`.split("\n")
    return [basename.gsub('.tgz', '').gsub('.tar.gz', ''), files]
  elsif File.extname(gzip_file) == 'bz2'
    files =`tar xvjf '#{gzip_file}'`.split("\n")
    return [basename.gsub('.bz2', ''), files]
  elsif File.extname(gzip_file) == '.tar'
    files =`tar xvf '#{gzip_file}'`.split("\n")
    return [basename.gsub('.tar', ''), files]
  end
end

def list_files gzip_file
  output = `unzip -l #{gzip_file}`
  flag = nil
  files = []
  output.each_line{|l|
    if l =~ /^ *---/
      break if flag 
      flag = true 
      next
    end
    next unless flag
    length, date, time, name = l.split
    unless name.end_with? '/'
      files << name
    end
  }
  files
end

def relative_path path, root=RAILS_ROOT
  path.sub(/#{root.sub(/\/$/, '')}\//, '') if path
end

def absolute_path path, root=RAILS_ROOT
  return path if path.start_with? '/'
  File.join root, path
end

def canonical_path path
  if File.file? path
    Dir.chdir(File.dirname path){return File.join(Dir.pwd, File.basename(path))}
  elsif File.exist? path
    Dir.chdir(path){return Dir.pwd}
  else
    nil
  end
end    

def longest_common_substr(strings)
  shortest = strings.min_by &:length
  maxlen = shortest.length
  maxlen.downto(1) do |len|
    0.upto(maxlen - len) do |start|
      substr = shortest[start,len]
      return substr if strings.all?{|str| str.include? substr }
    end
  end
end

def pick_object testbench_implementations, simulator
  #    pp 'ti=', testbench_implementations
  #    pp 'sim=', simulator
  testbench_implementations.each{|tb|
    #      pp 'tb=', tb
    return tb if tb.simulator == simulator
  }
  
  testbench_implementations.each{|tb|
#    return tb if simulator.name.include? tb.simulator.name
    return tb if tb.simulator && simulator && simulator.name == tb.simulator.name # to simulate all if simulator is nil
  }
  return nil
end

def scr_to_abs path, xs, ys, xe, ye, width, height, view_setting
  settings=eval(File.read(path+'.settings'))
    pp 'settings=', settings
    if view_setting && view_setting.xscale == 'log'
      xmin=Math.log10 settings['XMIN']
      xmax=Math.log10 settings['XMAX']
    else
      xmin=settings['XMIN']
      xmax=settings['XMAX']
    end
    if view_setting && view_setting.yscale == 'log'
      ymin=Math.log10 settings['YMIN']
      ymax=Math.log10 settings['YMAX']
    else
      ymin=settings['YMIN']
      ymax=settings['YMAX'] 
    end
    rectangle={'AREALEFT' => settings['AREALEFT'].to_f, 
               'AREABOTTOM' => settings['AREABOTTOM'].to_f,
               'AREARIGHT' => settings['AREARIGHT'].to_f,
               'AREATOP' => settings['AREATOP'].to_f}
    pp 'rectangle=', rectangle
    arealeft, areabottom, arearight, areatop = pick_numbers path+'.debug'
    boundingbox={'AREALEFT' => arealeft.to_f-0.2, 
                 'AREABOTTOM' => areabottom.to_f-0.2,
                 'AREARIGHT' => arearight.to_f+0.2,
                 'AREATOP' => areatop.to_f+0.2}
    pp 'boundingbox=', boundingbox

    xamin=(xs/width)*(boundingbox['AREARIGHT']-boundingbox['AREALEFT']) + boundingbox['AREALEFT']
    newxmin = ((xmax-xmin)/(rectangle['AREARIGHT']-rectangle['AREALEFT']))*(xamin-rectangle['AREALEFT'])+xmin
    xamax=(xe/width)*(boundingbox['AREARIGHT']-boundingbox['AREALEFT']) + boundingbox['AREALEFT']
    newxmax = ((xmax-xmin)/(rectangle['AREARIGHT']-rectangle['AREALEFT']))*(xamax-rectangle['AREALEFT'])+xmin
    yamin=(1.0-ye/height)*(boundingbox['AREATOP']-boundingbox['AREABOTTOM']) + boundingbox['AREABOTTOM']
    newymin = ((ymax-ymin)/(rectangle['AREATOP']-rectangle['AREABOTTOM']))*(yamin-rectangle['AREABOTTOM'])+ymin
    yamax=(1.0-ys/height)*(boundingbox['AREATOP']-boundingbox['AREABOTTOM']) + boundingbox['AREABOTTOM']
    newymax = ((ymax-ymin)/(rectangle['AREATOP']-rectangle['AREABOTTOM']))*(yamax-rectangle['AREABOTTOM'])+ymin

    if view_setting && view_setting.xscale == 'log'
      newxmin = 10.0 ** newxmin
      newxmax = 10.0 ** newxmax
    end
    if view_setting && view_setting.yscale == 'log'
      newymin = 10.0 ** newymin
      newymax = 10.0 ** newymax
    end
    puts 'xs='+xs.to_s+',ys='+ys.to_s+',xe='+xe.to_s+',ye='+ye.to_s+',height='+height.to_s+',width='+width.to_s
    puts '(xamin, xamax, yamin, yamax)=('+xamin.to_s+','+xamax.to_s+','+yamin.to_s+','+yamax.to_s+')'
    puts '(newxmin, newxmax, newymin, newymax)=('+newxmin.to_s+','+newxmax.to_s+','+newymin.to_s+','+newymax.to_s+')'
  return newxmin, newymin, newxmax, newymax
end

def pick_numbers file
  inf = File.open file
  while line=inf.gets
    if /.*ounding box is: (\d+\.\d+) *, *(\d+\.\d+) *to *(\d+\.\d+) *, *(\d+\.\d+)/ =~ line
      return [$1, $2, $3, $4]
    end
  end
end

def create_netlist path, *nets
  FileUtils.mkdir_p File.dirname(path)
  fout = File.open(path, 'w')
  nets.each{|net|
    if File.exists? net
      fout.print File.open(net).read 
    else
      fout.print net 
    end
  }
  fout.close
  netlistHeader = "simulator lang=spectre\nglobal 0 vcc!\n"
  netlistFooter = ""
  fout_print path+'Header', netlistHeader
  fout_print path+'Footer', netlistFooter
  return path
end

def quote_unless_numeric a
  if a.nil?
    return 'nil' 
  elsif numeric? a
    return a
  else
    return "'"+a+"'"
  end
end

def numeric?(object)
  true if Float(object) rescue false
end

def lib_feature instance
  print 'instance.cell.cell_type.name=', instance.cell.cell_type.name, " => label="
  if instance.cell.cell_type.name =~ /HBT|hbt|Hbt|BJT|Bjt|bjt/
    puts 'Emitter'
    return 'Emitter'
  elsif instance.cell.cell_type.name =~ /Mos|MOS|mos/
    puts 'Gate'
    return 'Gate'
  end
end

def pair_join ps, as, j=''
  #    ps=['@l','@w']
  #    as=['1u','3u']
  
  r = []
  ps.each_with_index{|a, i|
    r << "#{a}=#{as[i]}"
  }                  
  #    p r.join
  r.join j
end

def erase_lw str
  str.gsub(/[;]* *@[lw] *=[^;]*;*/,'')
end

def fout_print path, text, binary=nil
  directory = File.dirname path
  FileUtils.mkdir_p directory unless File.directory? directory
  if binary
    fout = File.open(path, 'wb')
  else
    fout = File.open(path, 'w')
  end
  fout.puts text.chomp
  fout.close
  path
end

class Array
#  def index_all( val = nil )
#    result = []
#    each_with_index { |x, i|
#      result << i if x == val or block_given? && yield(x, i)
#    }
#    result
#  end
  def search_indices
    result = []
    each_index { |i|
      result << i if yield(i)
    }
    result
  end

  def values a
    a.map{|i| self[i]}
  end
end

def hello_alta mac, alb_version, hostname=nil
  [$lmhost || 'not available',  
   $expiration_date || 'no expiration', 
   $num_limit || 'unlimited', 
   if check_license() == 'License expired'
     'ALB server LICENSE EXPIRED'
   elsif alta_licensed?(mac)
     if alb_version.nil?
       "your version of alta is no longer supported --- please update" 
     elsif alb_version.to_f < ALB_VERSION.to_f
       "alta for alb v#{alb_version} is no longer supported --- please update alta" 
     else
       'your machine is licensed to use Alta' 
     end
   elsif hostname == `hostname`.chop
       'your machine is licensed to use Alta' 
   else
     "your machine (#{mac}) IS NOT LICENSED to use Alta --- please request"
   end 
  ]
end

def alta_version
  if alta_installed?
    ver_file = File.join(RAILS_ROOT, '..', 'lib', 'ruby', '1.8', 'alta_version.rb')
    load ver_file if File.exist? ver_file
  end
  [$alta_version, $alta_release_date]
end

def alta_installed?
  File.exist? File.join(RAILS_ROOT, '..', 'bin', 'alta')
#  File.exist? File.join(ENV['HOME'], 'anagix_tools', 'bin', 'alta')
end

def alta_license_ready? groups=Group.all
  if num_lim = ($num_limit && $num_limit.to_i)
    return true if num_lim <=1 || num_lim >= 1000
  end
  groups.each{|gr|
    return true if gr.name && gr.name.gsub(/[ :-]/,'').sub(/#.*/, '').downcase == $lmhost
  }
  File.exist? File.join(RAILS_ROOT, 'alta_license.dat')
end

def alta_licensed? mac, groups=Group.all
  return nil if mac.nil?
  if num_lim = ($num_limit && $num_limit.to_i)
    return true if num_lim <=1 || num_lim >= 1000
  end
  genuine_mac = mac.gsub(/[ :-]/,'').sub(/#.*/, '').downcase
  return true if $lmhost && genuine_mac == $lmhost.gsub(/[ :-]/,'').downcase
  groups.each{|gr|
    if gr.name && gr.name.gsub(/[ :-]/,'').sub(/#.*/, '').downcase == $lmhost
      count = 0
      gr.description.each_line{|l|
        l.chomp!
        count = count + 1
        break if num_lim && count > num_lim
        return true if l.gsub(/[ :-]/,'').sub(/#.*/, '').downcase == genuine_mac
      }
    end
  }
  if genuine_mac && File.exist?(alta_license_file = 'alta_license.dat')
    if alta_licenses = YAML.load(File.read(alta_license_file))
      if $lmhost
        alta_licenses = alta_licenses[$lmhost].map{|a| a.gsub(/[ :-]/,'').sub(/#.*/, '').downcase}
      else
        alta_licenses = alta_licenses.values.flatten.map{|a| a.gsub(/[ :-]/,'').sub(/#.*/, '').downcase}
      end
      return alta_licenses[0..(num_lim||0)-1].include? genuine_mac
    end
  end
end

# $lmhosts=['001f29783614', '001f16137720']

require 'parsedate' if RUBY_VERSION == '1.8.7'

def check_license current_user=nil
  grace_period=0 
  if defined? LMHOSTID
    $lmhost = LMHOSTID.downcase 
  else
    if /mswin32/ =~ RUBY_PLATFORM || /mingw/ =~ RUBY_PLATFORM
      `getmac` =~ /\n([^ ]*) +\\Device\\Tcpip/
    else
      `get_mac` =~ /HW Address: (.*)\n/
    end
    $lmhost = $1.downcase.gsub(/[:-]/, '')
  end
  $lmhosts = []
  license = ''
  if File.exist? 'license_master.dat'
    File.read('license_master.dat').each_line{|l|
      user, email, lmhostid, num_limit, expiration_date = l.chop.split(/, */)
      next if user.nil?
      $lmhosts << lmhostid.downcase.gsub(/[:-]/, '')
      $expiration_date = expiration_date if $lmhost == lmhostid
      $num_limit = num_limit if $lmhost == lmhostid
    }
#    license = 'master'
  end

  if File.exist?('license.dat') && defined? Anagix::decrypt
    File.read('license.dat').each_line{|l|
      license << l unless l.start_with? '#'
    }
    license = Anagix::decrypt(license, 'license.dat')
    puts 'decrypted license:', license if ENV['CRYPT_KEY']

    license.each_line{|l|
      user, email, lmhostid, num_limit, expiration_date = l.chop.split(/, */)
      $lmhosts << lmhostid.downcase.gsub(/[:-]/, '')
      $expiration_date = expiration_date if $lmhost == lmhostid
      $num_limit = num_limit if $lmhost == lmhostid
    }
  end

  if RUBY_VERSION == '1.8.7'
    $expiration = Time.local *(ParseDate::parsedate "#{$expiration_date} 23:59:59") if $expiration_date
  else # needs to check if it works!
    $expiration = DateTime.parse("#{$expiration_date} 23:59:59").to_time if $expiration_date    
  end
    
  #puts "$expiration = #{$expiration}, $num_limit = #{$num_limit}"

  #  if license.length == 0               # unnecessary to check license.dat existence
  #    return "License file is missing"   # because $lmhosts is not loaded
  #  end                                  # if license.dat is missing

  if $lmhost && !$lmhosts.include?($lmhost)
    return "#{$lmhost} is not a valid MAC address"
  elsif $num_limit && logon_limit?(current_user)
    return "Maximum number of users #{$num_limit} reached"
  elsif $expiration
    if grace_period < 0
      if Time.now > $expiration
        return 'License expired'
      elsif Time.now > $expiration + grace_period
        message =  "License will expire on #{$expiration}"
        puts message
        return message
      end
    else
      if Time.now > $expiration + grace_period
        return 'License expired'
      else
        message =  "License will expire on #{$expiration + grace_period} "
        return message
      end
    end
  end
  nil
end

def choose_project

  #  Rails.application.routes.default_url_options[:host] ||= request.env['HTTP_HOST']  
  Rails.application.routes.default_url_options[:host] = request.env['SERVER_NAME']+':'+request.env['SERVER_PORT']  

  #    $repo = session[:repo]
  if !logon_continued?(current_user)
  #    redirect_to :controller=> 'logout' ### this does not work w/ rails4
  elsif current_user.administrator? 
  #    print "**** current_project = #{current_project} in choose project\n"
  elsif current_project ==  nil 
    if current_user.signed_up?
      if current_user.project_assignments.size > 0
        redirect_to :controller=> 'front', :action => 'choose_project'
      else
        redirect_to :controller=> 'front', :action => 'need_admin_help'
      end
    else
      redirect_to :controller=> 'front', :action => 'choose_project'
    end
  end
end

def logon_continued? user
#  LogonUser.all.each{|l|
  LogonUser.includes(:user).each{|l|
    return true if l.user == user
  }
  false
end

def logon_limit? user
  if user
#    LogonUser.all.each{|l|
  LogonUser.includes(:user).each{|l|
      return false if l.user == user
    }
  end
  LogonUser.all.size >= $num_limit.to_i
end

def logon_users 
  users=[]
  # return users
#  LogonUser.all.each{|l|
  LogonUser.includes(:user).each{|l|
    if l.user
      users << l.user.name
    else
      l.destroy
    end
  }
  users.join(',')
end

def LTspice_edit name, lib_name, proj_name
  dir = File.join($proj_repo_dir, proj_name, lib_name)
  file =  File.join(dir, name+'.asc')
  FileUtils.mkdir_p dir unless File.exist? dir  
  File.open(file, 'w'){} unless File.exist? file # new file
  if /mswin32|mingw|cygwin/ =~ RUBY_PLATFORM
    system "cd '#{dir}'; #{get_short_path_name(ltspice_path())} #{file}"
  else
    system "cd '#{dir}'; wine '#{ltspice_path()}' #{file} &"
  end
end
    
def yaml_load file
  return nil unless File.exist? file
  YAML.load(File.read(file).encode('UTF-8'))
end

def restore_entry table_name, columns, mapping, newobj=nil, name=nil
  klass = table_name.camelize.constantize
  if obj = newobj
#    obj.lock_version = obj.lock_version + 1
  else
    return nil if mapping[table_name] && mapping[table_name][columns['id']] # existing entry
    obj = klass.new
  end
  puts "restore '#{name}'"
  klass.columns.each{|a| 
    value = columns[a.name]
    next if a.name == 'id' || a.name == 'lock_version'
    if a.name.include? '_id'
      obj_name = a.name.sub('_id', '')
#      debugger if obj_name == 'library'
      if newobj && new_id = newobj.send(a.name)
        mapping[obj_name] ||= {}
        mapping[obj_name][value] = new_id
        puts "***#{obj_name}[#{value}] => #{new_id}"
        obj[a.name] = new_id
        next
      elsif mapping[obj_name] && new_value = mapping[obj_name][value]
        puts "#{obj_name}[#{value}] -> #{obj_name}[#{new_value}]"
        value = new_value
      end
    end
    obj[a.name] = value
  }
# debugger if name == 'ModelImplementation814'
  obj.save!
#  obj.save # save even if there are errors
  mapping[table_name] ||= {}
  mapping[table_name][columns['id']] = obj.id
  puts "#{table_name}[#{columns['id']}] => #{obj.id} restored" 
  obj
end

def fixture_entry table_name, obj, host={}
  res = []
  klass = table_name.singularize.camelize.constantize
  res << "#{table_name.singularize}#{obj['id']}:"
  klass.columns.each do |column|
    if obj[column.name]
      if column.type == :text 
        result = ''
        obj[column.name].each_line{|l|
          l.chomp!
          result << l.gsub("\\", "\\\\\\\\") + "\\n"
        }
        if obj.send(column.name).class == HoboFields::Types::HtmlString
          result.gsub! "http://#{host[:host]}:#{host[:port]}/", '#{ALB_SITE}'
        end
        res << "  #{column.name}: \"#{result.gsub(/"/,'\"')}\""
      elsif column.type == :string
        res << "  #{column.name}: \"#{obj[column.name].gsub("\\", "\\\\\\\\").gsub(/"/,'\"')}\""
      else
        res << "  #{column.name}: #{obj[column.name]}"
      end
    else
      res << "  #{column.name}: #{obj[column.name]}"
    end
  end
  res.join("\n") + "\n"
end

def obj_backup bkup_objects, cell_types, backup_dir, name, host, simulations=[], plots=[], figures=[], documents=[]
  bkup_objects.each{|objects|
    next if objects.size == 0
    table_name = objects.first.class.name.tableize
    File.open("#{File.join backup_dir, table_name}.yml", "w"){|file|
      objects.each{|obj|
        file.puts fixture_entry(obj.class.name, obj, host)
      }
    }
  }
  tar_file = "#{backup_dir}../#{name.gsub(/[ \/]/, '_')}.tar"
  tgz_file = "#{backup_dir}../#{name.gsub(/[ \/]/, '_')}.tgz"
  puts "cd '#{backup_dir}..'; /bin/tar cvf '#{tar_file}' '#{name}'"
  system "cd '#{backup_dir}..'; /bin/tar cvf '#{tar_file}' '#{name}'"
  files = []
  cell_types.each{|cell_type|
    cell_type.backup host
    files << "CellType/#{cell_type.name}"
  }
  bkup_dir2 = File.join(backup_dir, '..')
  bkup_dir2 = File.join(backup_dir, '../..') unless self.class == Project
  puts "cd '#{bkup_dir2}'; /bin/tar --append -f '#{tar_file}' #{files.join(' ')}"
  system "cd '#{bkup_dir2}'; /bin/tar --append -f '#{tar_file}' #{files.join(' ')}"

  Dir.chdir(File.join(RAILS_ROOT, 'public', 'system')){
    puts "self.name=#{self.name}, self.class=#{self.class.name}"
    unless self.class == CellType
      proj_name = ((self.class == Project)? self.name : self.project.name).gsub(' ', '_')
      proj_dir = File.join('assist', proj_name)
      files = []
      File.directory?(proj_dir) && Dir.chdir(proj_dir){
        bkup_objects.each{|objects|
          next if objects.size == 0
          table_name = objects.first.class.name.tableize
          next unless File.directory? table_name
          Dir.chdir(table_name){
            objects.each{|obj|
              if File.directory?(obj.id.to_s)
                files << File.join(proj_dir, table_name, obj.id.to_s)
              end
            }
          }
        }
      }
      files.each{|f|
        puts "/bin/tar --append -f '#{tar_file}' #{f}"
        system "/bin/tar --append -f '#{tar_file}' #{f}"
      }
    end
    if figures.size > 0 && File.directory?('figures')
      puts "/bin/tar --append -f '#{tar_file}' #{figures.map{|doc| File.join('figures', doc.id.to_s)}.join(' ')}"
      system "/bin/tar --append -f '#{tar_file}' #{figures.map{|doc| File.join('figures', doc.id.to_s)}.join(' ')}"
    end
    if documents.size > 0 && File.directory?('documents')
      puts "/bin/tar --append -f '#{tar_file}' #{documents.map{|doc| File.join('documents', doc.id.to_s)}.join(' ')}"
      system "/bin/tar --append -f '#{tar_file}' #{documents.map{|doc| File.join('documents', doc.id.to_s)}.join(' ')}"
    end
  }
  
  backup_sim_dir = false

  self.project_sim_dir && File.exist?(self.project_sim_dir) && Dir.chdir(File.join(self.project_sim_dir, '../..')){
    sim_dirs = []
    files = []
    simulations.each{|s|
      sf = s.name.split('/')
      if backup_sim_dir
        sim_dir = File.join sf[2..-2]  # 'simulation/prj_name/model_name/...'
        sim_dirs << "'#{sim_dir}'"
      else
        files << "'#{File.join sf[2..-1]}'" if sf.size >=3 && File.exist?(File.join sf[2..-1]) # v1.52q
      end
    }
    if backup_sim_dir
      puts "/bin/tar --append -f '#{tar_file}' #{sim_dirs.join(' ')}"
      system "/bin/tar --append -f '#{tar_file}' #{sim_dirs.join(' ')}"
    else
      puts "/bin/tar --append -f '#{tar_file}' #{files.join(' ')}"
      system "/bin/tar --append -f '#{tar_file}' #{files.join(' ')}"
    end
  }
  files = []
  Dir.chdir(File.join(RAILS_ROOT, 'public')){
    plots.each{|p|
      img = File.join 'images', p.image
#      puts "/bin/tar --append -f '#{tar_file}' '#{img}' #{File.exist?(img) ? '' : ' --- non existent!'}"
#      system "/bin/tar --append -f '#{tar_file}' '#{img}'" if File.exist? img
      if File.exist? img
        files << "'#{img}'"
      else
        puts "'#{img}' --- non existent!" 
      end
    }
    system "/bin/tar --append -f '#{tar_file}' #{files.join(' ')}"
    system "/bin/gzip -c '#{tar_file}' > '#{tgz_file}' && /bin/rm '#{tar_file}'"
  }
end

def reuse_cell_types backup_dir, host, mapping, top_name
  obj_reuse backup_dir, Simulator.all, 'simulators', mapping
  obj_reuse backup_dir, CellCategory.all, 'cell_categories', mapping
  cell_types_bkup = yaml_load(File.join backup_dir, 'cell_types.yml')     
  cell_types_bkup && cell_types_bkup.each_pair{|ct, ct_columns|
    if cell_type = CellType.find_by_name(ct_columns['name'])
      cell_type.reuse ct_columns, mapping, File.join(backup_dir, 'CellType', cell_type.name)
    else
      CellType.new.restore host, mapping, File.join(backup_dir, 'CellType', ct_columns['name'])
    end
  }
  if top_name == 'project'
    obj_reuse backup_dir, self.device_types, 'device_types', mapping
  end
end

def obj_reuse backup_dir, existing_objects, table_name, mapping
  bkup_table = yaml_load(File.join(backup_dir, table_name) + '.yml') 
  existing_objects.each{|obj|
    next if obj.nil?
    if id = get_backup_id_from_table(bkup_table, obj.name)
      mapping[table_name.singularize] ||= {}
      mapping[table_name.singularize][id] = obj.id
      puts "reuse: mapping[#{table_name.singularize}][#{id}] = #{obj.id}"
    end
  }
end

def get_backup_table backup_dir, objects, top_name, obj
  puts "backup_dir = #{backup_dir}"
  raise "Error: '#{top_name}.yml' is not available in the backup" unless File.exist? "#{File.join backup_dir, top_name}.yml"
  top = yaml_load("#{File.join backup_dir, top_name}.yml")
  tables = {}
  top.first.last['name'] = obj.name # rename to current library name
  objects.each{|table_name|
    tables[table_name] = yaml_load(File.join(backup_dir, table_name) + '.yml') 
  }
  tables
end

def get_backup_id_from_table backup_table, name
  backup_table && backup_table.each_pair{|item, table|
    return table['id'] if table['name'] == name
  }
  nil
end

def obj_restore backup_dir, objects, top_name, obj, mapping={}, host={}
  puts "backup_dir = #{backup_dir}"
  raise "Error: '#{top_name}.yml' is not available in the backup" unless File.exist? "#{File.join backup_dir, top_name}.yml"
  top = yaml_load("#{File.join backup_dir, top_name}.yml")
  top.first.last['name'] = obj.name if obj.name # rename to current library name
  mapping[top_name] ||= {}
  restored_objects = []
  restored_objects << restore_entry(top_name.singularize, top[top.keys.first], mapping, obj, nil)
  objects.each{|table_name|
    map_table = mapping[table_name.singularize]
    puts "yaml_load '#{table_name}.yml'"
    tables = yaml_load(File.join(backup_dir, table_name) + '.yml') 
#    tables && tables.each_pair{|name, columns|
    tables && tables.keys.sort.each{|name|
      columns = tables[name]
      if map_table.class == Array && id = map_table[columns['id']] 
        puts "#{columns['name']}(#{table_name.singularize}[id=#{columns['id']})'s existing id = #{id}"
        next 
      end
      begin
        restored_objects << restore_entry(table_name.singularize, columns, mapping, nil, name)
      rescue => error
        puts "Error while restoring #{name}: #{error}"
      end
    }
  }
  rev_map = {}
  mapping.each_pair{|m, map|
    rev_map[m] ||= {}
    map.each_pair{|o, n|
      rev_map[m][n] = o
    }
  }
  figures_dir = File.join RAILS_ROOT, 'public/system/figures'
  FileUtils.mkdir_p figures_dir unless File.directory? figures_dir
  documents_dir = File.join RAILS_ROOT, 'public/system/documents'
  FileUtils.mkdir_p documents_dir unless File.directory? documents_dir

  restored_objects.each{|obj|
    next if obj.nil? # existing entry (like simulator)
    obj.reload if obj.id
    if obj.class == Figure
      figures_bkup_dir = File.join backup_dir, 'figures'
      File.directory?(figures_bkup_dir)&& Dir.chdir(figures_bkup_dir){
        target_dir = File.join(figures_dir, obj.id.to_s)
        FileUtils.rm_rf target_dir if File.directory? target_dir
        FileUtils.mv rev_map['figure'][obj.id].to_s, target_dir if File.exist? rev_map['figure'][obj.id].to_s
      }
    elsif obj.class == Document
      documents_bkup_dir = File.join backup_dir, 'documents'
      File.directory?(documents_bkup_dir)&& Dir.chdir(documents_bkup_dir){
        target_dir = File.join(documents_dir, obj.id.to_s)
        FileUtils.rm_rf target_dir if File.directory? target_dir
        FileUtils.mv rev_map['document'][obj.id].to_s, target_dir if File.exist? rev_map['document'][obj.id].to_s
      }
    elsif [Simulation, Simfile, Measfile, ModelSimulation].include? obj.class
      Dir.chdir(backup_dir){
        new_name = nil
        if obj.class == Simulation
          next if obj.plot.nil? || obj.plot.device.nil?
          new_name = obj.plot.device.model.name
        elsif obj.class == Simfile || obj.class == Measfile
          if obj.plot_instance.instance
            next if obj.plot_instance.instance.nil?
            new_name = obj.plot_instance.instance.cell.name
          elsif obj.plot_instance.cell_view
            next if obj.plot_instance.cell_view.nil?
            new_name = obj.plot_instance.cell_view.cell.name
          end
        elsif obj.class == ModelSimulation
          next if obj.model_plot.nil? || obj.model_plot.model_view.nil?
          new_name = obj.model_plot.model_view.model.name
        end
        next if new_name.nil?
        obj.name = move_simulation_directory obj, new_name
        obj.save!
      }
      next
    elsif obj.class == Plot
#      device_id = obj.device_id
# debugger if obj.device.nil?
      next if obj.device.nil?
      model = obj.device.model

#      image = File.join(RAILS_ROOT, 'public/images', "#{device_type}/#{model.name}/#{device_id}/#{obj.id}.png")
      image = File.join(RAILS_ROOT, 'public/images', obj.image)

      device_type = model.device_type.name
      old_device_id = rev_map['device'][obj.device.id]
      old_image = "#{device_type}/#{model.name}/#{old_device_id}/#{rev_map['plot'][obj.id]}.png"

      image_dir = File.join(backup_dir, 'images')
      FileUtils.mkdir_p image_dir unless File.directory? image_dir # bug fix in v1.52p
      Dir.chdir(image_dir){
        if File.exist? old_image
          FileUtils.mkdir_p File.dirname(image)
          FileUtils.cp old_image, image if File.exist? old_image
        end
      }
      next
    elsif obj.class == PlotInstance
      if obj.instance
        cell = obj.instance.cell
        old_instance_id = rev_map['instance'][obj.instance.id]
      else
        cell = obj.cell_view.cell
        old_instance_id = rev_map['cell_view'][obj.cell_view.id] if rev_map['cell_view']
      end
      image = File.join(RAILS_ROOT, 'public/images', obj.image)
      begin
        old_cell_name = Cell.find(rev_map['cell'][cell.id]).name
        old_image = "#{cell.library.name}/#{old_cell_name}/#{old_instance_id}/#{rev_map['plot_instance'][obj.id]}.png"
        File.directory?(dir = File.join(backup_dir, 'images')) && Dir.chdir(dir){
          FileUtils.mkdir_p File.dirname(image)
          FileUtils.cp old_image, image if File.exist? old_image
        } 
      rescue => error
        puts error
      end
      next
    elsif [Project, Library, Cell, Instance, Testbench].include? obj.class
      proj_name = (self.class == Project)? self.name : self.project.name.gsub(' ', '_')
      proj_dir = File.join(RAILS_ROOT, 'public', 'system', 'assist', proj_name)
      table_name = obj.class.name.tableize
      tgt_dir = File.expand_path File.join(proj_dir, table_name) 
      assist_dir = File.join('public', 'system', 'upload', proj_name, 'assist')
      File.directory?(assist_dir) && Dir.chdir(assist_dir){
        Dir.glob("*/#{table_name}/*").each{|obj_dir|
          if File.basename(obj_dir) == rev_map[table_name.singularize][obj.id].to_s
            File.directory?(tgt_dir) || FileUtils.mkdir_p(tgt_dir) 
            FileUtils.mv obj_dir, File.join(tgt_dir, obj.id.to_s)
            puts "#{File.expand_path obj_dir} moved under #{File.join(tgt_dir, obj.id.to_s)}"
          end
        }
      }
    end
    flag = nil
    obj.class.columns.each{|c|
      value = obj.send c.name
      if (value.class == String || value.class == HoboFields::Types::HtmlString) && value.include?('href="#{ALB_SITE}')
        result = value.scan /\#\{ALB_SITE\}[^"]+\"/
        result.each{|p|
          new_str = nil
          if p =~ /\#\{ALB_SITE\}(\S+)\/(\d+)\-(\S+)\"/
            new_id = mapping[$1.singularize][$2.to_i]
            new_str = "http://#{host[:host]}:#{host[:port]}\/#{$1}\/#{new_id}-#{$3}\""
          elsif p =~ /\#\{ALB_SITE\}(\S+)\/(\d+)\"/
            new_id = mapping[$1.singularize][$2.to_i]
            new_str = "http://#{host[:host]}:#{host[:port]}\/#{$1}\/#{new_id}\""
          elsif p =~ /\#\{ALB_SITE\}(\S+)\"/
            new_str = p.gsub '#{ALB_SITE}', "http://#{host[:host]}:#{host[:port]}/" 
          end
          value.sub!(p, new_str) if new_str
          flag = true
        }
        obj.send("#{c.name}=", value) if flag
      end
    }
    obj.save! if flag
  }
end

def move_simulation_directory obj, new_name
  sf = obj.name.split('/') # public/system/simulation/fpdk200l_3.5_1PDK1/nch/100nx600n2@l=100e-9@w=600e-9/100nx600n2_nmos_Ids_Vgs/LTspice/file.csv
  sim_dir = File.join 'simulation', sf[3..-2]
  #     obj.project_sim_dir = public/system/simulation/fpdk200...
  sf[3] = obj.proj.name
  sf[4] = new_name 
  target_dir = File.join(RAILS_ROOT, obj.project_sim_dir, sf[4..-2])
  FileUtils.mkdir_p target_dir unless File.directory? target_dir
  FileUtils.rm_rf target_dir if File.directory? target_dir
  if File.directory? sim_dir
    FileUtils.mv sim_dir, target_dir 
    puts "'#{sim_dir}' moved to '#{target_dir}'"
  end
  File.join sf
rescue => error
  puts error
  obj.name
end

=begin
def extract_and_rename file, upload_dir, new_name
  filename = file.original_filename
  FileUtils.mkdir_p(upload_dir) unless File.exist?(upload_dir)
  File.open(File.join(upload_dir, filename), "wb"){ |f| f.write(file.read) }
  Dir.chdir(upload_dir){
    unzip filename
    top_name = filename.sub(File.extname(filename), '')
    unless top_name == new_name
      FileUtils.rm_r new_name if File.exist? new_name
      File.rename top_name, new_name
    end
  }
end
=end

def extract_and_rename file, upload_dir, new_name
  filename = file.original_filename
  new_dir = File.join(upload_dir, new_name)
  FileUtils.rm_r new_dir if File.exist? new_dir
  FileUtils.mkdir_p(new_dir)
  File.open(File.join(new_dir, filename), "wb"){ |f| f.write(file.read) }
  Dir.chdir(new_dir){
    unzip filename
    extracted_files = Dir.glob('*/*.yml')
    extracted_files.each{|f|
      FileUtils.move f, '.'
    }
  }
end

def unwrap netlist, ignore_comments=true    # line is like:
  result = ''         # abc
  breaks = []         #+def   => breaks[0]=[3]
  pos = 0
  line = '' 
  bs_breaks = []
  netlist && netlist.each_line{|l|  # line might be 'abc\n' or 'abc\r\n'
      next if ignore_comments && (l[0,1] == '*' || l[0,1] == '/') # just ignore comment lines
    l_chop = l.chop
#    if l.chop[-1,1] == "\\"
    if l_chop[-1,1] == "\\"
      line << l_chop
      line[-1,1] = ' '   # replace backslash with space
      bs_breaks << -(line.length-1)   # record by minus number
      next
    end
    line << l
    if /^\+/ =~ line
#      result.chop!          # remove \r and \n
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
    line = ''
  }
  [result, breaks]
end

public :unwrap

def wrap_netlist result, breaks
  netlist = ''
  count=0
  result.each_line{|line|
    line = wrap(line, breaks[count])
    count = count+1
    netlist << line
  }
  netlist
end

public :wrap_netlist 

def wrap line, breaks
  return line if breaks.size == 0
  line_copy = line.dup
#  puts "#{line}:#{breaks.inspect}"
  breaks.reverse_each{|pos|
    if pos>0
      line_copy[pos..pos] = "\n+" + line_copy[pos..pos]  # insert
    else
      line_copy[-pos..-pos] = "\\\n"    # just replace 
    end
  }
  line_copy
end

public :wrap

def new_wrap line, max_len = 80
  lines = line.split
  result = ''
  if wl = lines[0]
    lines[1..-1].each{|l|
      if wl.length + l.length <= max_len
        wl << ' ' + l
      else
        result << wl + "\n"
        wl = '+ ' + l
      end
    }
    result << wl + "\n" 
  else
    "\n"
  end
end

def subst_values wl, l, pairs
  flag = nil
  pairs.each{|k, v|
    yield k, v if block_given?
    next if numeric? v
    converted_v = convert_to_if v
    if flag
      l.sub!(/#{k} *= */, "#{k}=")
      l.sub!(" #{k}=#{v}", " #{k}=\{#{converted_v}\}") 
    else
      wl.sub!(/#{k} *= */, "#{k}=")
      wl.sub!(" #{k}=#{v}", " #{k}=\{#{converted_v}\}") 
      if $&.nil? # substitution failed
        flag = true 
      else
        wl.sub!(" #{k}=#{v}", " #{k}=\{#{converted_v}\}") 
        wl.sub!("+#{k}=#{v}", "+#{k}=\{#{converted_v}\}") 
      end
      l.sub!(/#{k} *= */, "#{k}=")
      l.sub!(" #{k}=#{v}", " #{k}=\{#{converted_v}\}") 
    end
  }
  flag ? new_wrap(l) : wl
end

# ===================================================
# see http://osdir.com/ml/lang.ruby.japanese/2006-04/msg00147.html

class IO_Tee
  def initialize(base_io, *io_list)
    @base = base_io
    @tee_list = io_list.dup
  end
  
  def add(*io_list)
    @tee_list |= io_list
  end
  
  def del(*io_list)
    @tee_list -= io_list
  end
  
  def method_missing(name, *args)
    @tee_list.each{|io| io.__send__(name, *args)}
    @base.__send__(name, *args)
  end
  
  def write(*args)
    @tee_list.each{|io| io.write(*args)}
    @base.write(*args)
  end
  
  def close
    @tee_list.each{|io| io.close}
    @base.close
  end
  
  def closed?
    @base.closed?
  end
end
=begin
$stdout = IO_Tee.new(STDOUT)
$stderr = IO_Tee.new(STDERR)

f1 = open('/tmp/asdf', 'w')
f2 = open('/tmp/qwer', 'w')

$stdout.add(f1, f2)
$stderr.add(f2)

p [1,2,3]
puts 'hogehoge'
print "fugafuga\n"

$stdout.puts "test 0"
$stdout.print "test 0"

$stdout.del(f1, f2)
$stdout.puts "test 1"
$stdout.print "test 1"

$stdout.add(f1)
$stdout.puts "test 2"
$stdout.print "test 2"

$stderr.puts "test_err"
$stderr.print "test_err"

$stdout.puts "end"
$stderr.puts "end"

$stdout.close
$stderr.close
=end

if __FILE__ == $0

$stdout = IO_Tee.new(STDOUT)
$stderr = IO_Tee.new(STDERR)

f1 = open('/tmp/asdf', 'w')
f2 = open('/tmp/qwer', 'w')

$stdout.add(f1, f2)
$stderr.add(f2)

=begin
p [1,2,3]
puts 'hogehoge'
print "fugafuga\n"

$stdout.puts "test 0"
$stdout.print "test 0"

$stdout.del(f1, f2)
$stdout.puts "test 1"
$stdout.print "test 1"

$stdout.add(f1)
$stdout.puts "test 2"
$stdout.print "test 2"

$stderr.puts "test_err"
$stderr.print "test_err"

$stdout.puts "end"
$stderr.puts "end"
=end

  netlist =<<EOF
abc def
+ghi kl\\
+hij abcd
+ efgg hijk
lmn op\\
+qrs tu miu 
xyz kkk hiu\\
jil sxxx\\
+ aaa zyx
EOF

puts "---original:", netlist
uw, breaks = unwrap netlist
puts "---Unwrapped", uw
puts "---breaks=", breaks.inspect
w = wrap_netlist uw, breaks
puts "---wrapped", w
puts "Wrapped=orignal?", netlist==w  # false is okay because of
                                     # special handling for '+'
                                     # continuation w/o space in the
                                     # previous line

puts "Wrapped.gsub(/ +\\n/,\"\\n\")=orignal.gsub(/ +\\n/,\"\\n\")?", netlist.gsub(/ +\n/,"\n")==w.gsub(/ +\n/,"\n") # false is okay because of
                                     # special handling for '+'
                                     # continuation w/o space in the
                                     # previous line

$stdout = STDOUT
$stderr = STDERR

$stdout.close
$stderr.close
end

if ENV['RUBY_PROF']
  module RubyProf
    def result
      result = RubyProf.stop
      printer = RubyProf::FlatPrinter.new(result)
      printer.print(STDOUT, 0)
      printer = RubyProf::GraphPrinter.new(result)
      printer.print(STDOUT, 0)
    end

    def profiler(&block)
      result = RubyProf.profile &block
      strio = StringIO.new
      RubyProf::FlatPrinter.new(result).print(strio)
      RubyProf::GraphPrinter.new(result).print(strio)
      strio.string
    end
    module_function :profiler, :result
  end
end

module Utility
  # see: https://rails.lighthouseapp.com/projects/8994/tickets/3545-_rails_html_safe-clutters-up-yaml  
  # ActiveSupport 2.3.5 adds @_rails_html_safe aggressively.              
  # This method removes it so you can output clean YAML.                  
  def self.plain_string(s)
    if s.instance_variable_defined?(:@_rails_html_safe)
      s.send(:remove_instance_variable, :@_rails_html_safe)
    end
    s  
  end

end

class Results
  def init performances, parameters
    @results ||= {}
    @results.clear
    @results['performances'] = performances
    @results['parameters'] = parameters
    (performances+parameters).each{|p|
      @results[p] = []
    }
  end

  def get name
    @results[name]
  end

  def set name, value 
    @results[name] << value
  end

  def save file='RESULTS'
    File.open(file, 'w'){|f|
      f.puts @results.to_yaml
    }
  end
  
  def restore file='RESULTS'
    raise "Result file (#{file}) is not available" unless File.exist? file
    @results = YAML.load(File.read(file)) || {}
    parameters = @results['parameters']
    # puts "parameters=#{parameters.inspect}"
    assignments = parameters.map{|p| @results[p]}
    [parameters, assignments.transpose]
  end
end

if ENV['MAIL_NOT_WORKING'] &&  RUBY_VERSION < '1.9.0' then # Note:
 require 'kconv'                                           # encode('UTF-8') is used in alta.rb to convert Simulink 
 class String                                              # file generated by Windows version of Matlab
   @encoding = nil

   def encoding
     if @encoding != nil then
       return @encoding
     else
       case Kconv.guess(self)
       when Kconv::JIS
         return "ISO-2022-JP"
       when Kconv::SJIS
         return "Shift_JIS"
       when Kconv::EUC
         return "EUC-JP"
       when Kconv::ASCII
         return "ASCII"
       when Kconv::UTF8
         return "UTF-8"
       when Kconv::UTF16
         return "UTF-16BE"
       when Kconv::UNKNOWN
         return nil
       when Kconv::BINARY
         return nil
       else
         return nil
       end
     end
   end

   def encode(to_encoding, from_encoding = nil, options = nil)
     if (from_encoding == nil)
       if @encoding == nil then
         f_encoding = Kconv::AUTO
       else
         f_encoding = @encoding
       end
     else
       f_encoding = get_kconv_encoding(from_encoding)
     end

     result = Kconv::kconv(self, get_kconv_encoding(to_encoding), f_encoding)
     result.set_encoding(to_encoding)
     return result
   end

   def get_kconv_encoding(encoding)
     if encoding != nil then
       case encoding.upcase
       when "ISO-2022-JP"
         return Kconv::JIS
       when "SHIFT_JIS"
         return Kconv::SJIS
       when "EUC-JP"
         return Kconv::EUC
       when "ASCII"
         return Kconv::ASCII
       when "UTF-8"
         return Kconv::UTF8
       when "UTF-16BE"
         return Kconv::UTF16
       else
         return Kconv::UNKNOWN
       end
     end
   end
   private :get_kconv_encoding

   def set_encoding(encoding)
     @encoding = encoding
   end

  def force_encoding(enc) # does nothing
    self
  end
 end

end

def fix_cell_props proj_id
  proj = Project.find proj_id
  puts "Project: #{proj.name} (#{proj.description})"
  proj.libraries.each{|lib|
    puts "Library: #{lib.name}"
    lib.cells.each{|cell|
      puts "Cell: #{cell.name}"
      if prop = YAML.load(cell.properties||'') and prop=prop['cells']
        prop.each_key{|k|
          prop.delete(k) if k =~ /(\\\\|@)/
        }
        puts prop.inspect
      end
      cell.instances.each{|inst|
        inst.testbenches.each{|tb|
          puts "Testbench: #{tb.name}"
          if prop = YAML.load(tb.properties||'') and prop=prop['cells']
            prop.each_key{|k|
              prop.delete(k) if k =~ /(\\\\|@)/
            }
            puts prop.inspect
          end
        }
      }
    }
  }
end

