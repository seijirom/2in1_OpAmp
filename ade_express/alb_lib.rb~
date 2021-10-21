# -*- coding: utf-8 -*-
# Copyright(C) 2009-2020 Anagix Corporation
require 'yaml'
require 'fileutils'

require 'tmpdir'
require 'erb'

def mytmp file=''
  file.sub!(/\/tmp\/*/, '')
  if file.strip == '' 
    Dir.tmpdir
  else
    if file =~ /^[0-9]+/ || RUBY_PLATFORM=~/mswin32|mingw|cygwin/
      File.join Dir.tmpdir, file
    else
      tmp_file = File.join Dir.tmpdir, `whoami`.chomp+'_'+file
      return tmp_file if File.exist? tmp_file
      tmp_file
    end
  end
end

def numeric?(object)
  true if Float(object) rescue false
end

def eng2number val
  return val if numeric?(val)
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
  when 'u'; m = 1e-6
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
=begin
  start = Time.now
  params = {}
  singles = []
  return [params, singles] if line.nil?
  line2 = line.strip.dup
  pa = nil
  count = 0
  while line2.size > 0 && count < 3000
    count = count + 1
    if line2 =~ /^( *(\w+) +)/
      singles << $2
      line2.sub! $1, ''
    elsif line2 =~ /^( *(\w+) *= *)/ || line2 =~ /^(([^= ]*) *(\w+) *= *)/
      if $3
        # puts "params[pa] = '#{params[pa]}', $2 = '#{$2}'"
        params[pa] = params[pa] + $2 if params[pa]
        # puts "--> params[pa] = '#{params[pa]}'"
        pa = $3
      else
        pa = $2
      end
      line2.sub! $1, ''
      if line2[0,1] == '('
        i = slice_block line2
        v = line2[0..i]
        line2[0..i] = ''
      elsif line2[0,1] == '['
        i = line2.index(']')
        v = line2[0..i]
        line2[0..i] = ''
      elsif line2 =~ /^([^=]+)$/
        v = $1
        line2 = ''
      else
        line2 =~ /^(([^=]*) )+\w+ *=/ || line2 =~ /^((\S+) *)/
        v = $2
        line2.sub! $1, ''
      end
      params[pa] = v.strip if v
    end
    puts "!!! #{count}:#{line2}" if count == 3000
  end
=end
  start = Time.now
  params = {}
  singles = []
  return [params, singles] if line.nil?
  line2 = line.strip.dup
  pa = nil
  count = 0
  while line2.size > 0 && count < 3000
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
    elsif line2 =~ /^( *(\w+) *)$/
      singles << $2
      line2.sub! $1, ''
    end
    puts "!!! #{count}:#{line2}" if count == 3000
  end
=begin
  puts "singles: #{singles.inspect}"
  puts "params: #{params.inspect}"
  puts "Elapse: #{Time.new - start}"
=end
  [params, singles]
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
  raise "Syntax error: '#{line2}' is not closed"
end

def convert_to_if v
  return v unless v.include? ':'
  return v unless v =~ /\( *(\S+) *\) *$/
  v2 = $1
  if v2[0,1] == '('
    i = slice_block v2
    c = v2[0..i]
    v2[0..i] = ''
    v2 =~ /\?(.*)/
    v3 = $1
  elsif v2 =~ /(\w+) *\?(.*)/
    c = $1
    v3 = $2
  end
  if v3[0,1] == '('
    i = slice_block v3
    d = v3[0..i]
    v3[0..i] = ''
    v3 =~ /:(.*)/
    e = $1
  elsif v3 =~ /(.*):(.*)/
    d = $1
    e = $2
  end
  "if(#{c}, #{convert_to_if d.strip}, #{convert_to_if e.strip})"
end

def resolve_env_var line
  if line =~ /\$(\w+)\//
    return line.sub('$'+$1, ENV[$1]) if ENV[$1]
  end
  line
end

def with_rescue alb=nil
  yield
rescue Exception, RuntimeError, SyntaxError => error
  puts error; puts error.backtrace
  if alb.nil? || alb.desc['autorun'].nil?
    Qt::MessageBox.critical(self, 'Error', error.to_s, Qt::MessageBox::Ok)
  end
end

def alb_parse_streamout_log_file run_dir, log_file
  unless log_file.start_with? '/'
    log_file = File.expand_path(File.join run_dir, log_file)
  end
  
  puts "read '#{log_file}'"
  
  run_dir = nil; gds_file = nil; lib_name = nil; primary_cell = nil; view_name = nil
  compress = nil;
  if File.exist?(log_file) 
    File.read(log_file).encode('UTF-8', invalid: :replace).each_line{|l|
      if l =~ /\'runDir\s*\"(\S+)\"/
        puts "run_dir=#{$1}"
        run_dir = $1
      elsif l =~ /\'outFile\s*\"(\S+)\"/
        puts "gds_file=#{$1}"
        gds_file = $1
      elsif l =~ /\'libName\s+(\S+)/
        lib_name = $1
      elsif l =~ /\'primaryCell\s+(\S+)/
        primary_cell = $1
      elsif l =~ /\'viewName\s+(\S+)/
        view_name = $1
      elsif l =~ /\'compression\s+(\S+)/
        compress = $1
      end
    }
  end
  
  if compress == '"compress"'
    gds_file << '.Z.pipoTMP'
  elsif compress == '"gzip"'
    gds_file << '.gz'
  elsif compress == '"bzip2"'
    gds_file << '.bz2'
    # elsif compress == '"none"'
  end
  
  if gds_file
    if gds_file.start_with? '/'
      gds_file_path = gds_file
    else
      gds_file_path = File.expand_path(File.join(run_dir, gds_file))
    end
    if log_file.start_with? '/'
      log_file_path = log_file
    else
      log_file_path = File.expand_path(File.join(run_dir, log_file))
    end
  end
  
  if gds_file
    puts     [log_file_path, gds_file_path, lib_name, primary_cell, view_name].inspect
    [log_file_path, gds_file_path, lib_name, primary_cell, view_name]
  else
    [nil, '', '', '', '']
  end
end

def copy_cds_lib ade_path
  File.open('cds.lib', 'w'){|f|
    File.read(File.join ade_path, 'cds.lib').each_line{|l|
      f.print l
    }
  }
  puts "'cds.lib' was copied from ade_path='#{ade_path}'" 
  puts 'Please edit cds.lib if necessary'
end

def alb_conf ade_path, conf_file='alb.conf', alb=nil
  copy_cds_lib ade_path unless File.exist? 'cds.lib'
  
  OPTS[:alb_site] ||= 'http://localhost:3000'
  OPTS[:browser] ||= 'localhost' 
  OPTS[:browser_port] ||= '4242'
  browser_alb_site = OPTS[:browser_alb_site] || OPTS[:alb_site] 
  browser_alb_site.sub!(/\/ *$/,'')
  OPTS[:alb] ||= parse_alb_site OPTS[:alb_site]
  OPTS[:ade] ||= `hostname`.chomp
  OPTS[:port_base] ||= '64800' # user range = 49152 - 65535
  
  if OPTS[:alb_gear_port_used]
    alb = ALBgear.new OPTS[:alb_site], OPTS[:login], OPTS[:password]
  else
    alb ||= alb_gear
  end
  if project = OPTS[:project]
    project_path = alb.open_project_or_exit project
    project_id = project_path.split('/')[2]
    puts "project_path = #{project_path}"
  end
  do_check_connection if OPTS[:check_connection]
  ade_express_ready_page = "/projects/ade_express_ready/#{project_id}?browser_port=#{OPTS[:browser_port]}&ade=#{OPTS[:ade]}&ade_path=#{ade_path}&alb_port=#{OPTS[:port_base]}&alb_version=#{ALB_VERSION}"
  
  unless conf_file
    visit_url ade_express_ready_page
  end
  
  id = alb.get_user_id
  
  puts id
  puts "project: \"#{project}\""
  puts "alb_site: \"#{OPTS[:alb_site].sub(/\/ *$/,'')}\""
  puts "browser: \"#{OPTS[:browser]}\""
  puts "browser_alb_site: \"#{browser_alb_site.sub(/\/ *$/,'')}\""
  puts "browser_port: #{OPTS[:browser_port]}"
  puts "ade: \"#{OPTS[:ade]}\""
  puts "port_base: #{OPTS[:port_base]}"
  puts "ade_path: \"#{ade_path}\""
  
  conf_file && File.open(conf_file, 'w'){|f|
    f.puts id
    f.puts "\"#{project}\""
    f.puts "\"#{OPTS[:alb_site].sub(/\/ *$/,'')}\""
    f.puts "\"#{OPTS[:browser]}\""
    f.puts "\"#{browser_alb_site.sub(/\/ *$/,'')}\""
    f.puts OPTS[:browser_port]
    f.puts "\"#{OPTS[:ade]}\""
    f.puts OPTS[:port_base]
    f.puts "\"#{ade_path}\""
    puts "#{conf_file} created for ADE"
  }
  
  unless conf_file
    puts "Please take a look at your browser and make sure that you have logged in ALB."
    puts "If you see 'ADE express ready' message on the browser, you are all set."
  end
  
  if OPTS[:alb_gear_port_used]
    start_service alb, conf_file
    sleep   
  end
end

def do_check_connection port_base = OPTS[:port_base]||64800
  require 'socket'
  begin
    timeout((port_base==64800)? 1:3){
      sock = TCPSocket.open(OPTS[:alb], port_base)
      sock.close
    }
  rescue Errno::ECONNREFUSED => error
    raise "Error: #{error} --- server #{OPTS[:alb]} (port:#{port_base}) may not be available" #; exit
  rescue Timeout::Error => error
    raise "Error: #{OPTS[:alb]} (port:#{port_base}) may be unreacheable (#{error})" #; exit
  end
end

def create_menus here=Dir.pwd
  Dir.chdir(here){
    if File.symlink?('menus')
      puts "symbolic link '#{link=File.join(here, 'menus')}' already exists"
    else
      system "/bin/ln -s /home/anagix/anagix_tools/etc/menus menus"
      puts "symbolic link '#{File.join here, 'menus'}' created"
    end
  }
end

def create_cdsinit here=Dir.pwd
  Dir.chdir(here){
    unless File.exist? '.cdsinit'
      File.open('.cdsinit', 'w'){|f|
        f.puts <<EOF
(if (isFile "~/.cdsinit") (load "~/.cdsinit"))
(let ((skillPath (getSkillPath))
      (albDir "/home/anagix/anagix_tools/etc"))
  (unless (member albDir (getSkillPath))
    (setSkillPath (append skillPath (list albDir)))
    (load "customize.il")))
EOF
      }
      puts ".cdsinit file created as below"
      puts "-------------------------------------------------------------------------"
      puts File.read('.cdsinit')
      puts "-------------------------------------------------------------------------"
    end
  }
end
      
=begin
def alb_symbols project, lib_path, lib_name, argv, grid_size
  symbols, categories = nil
  Dir.chdir(lib_path){
    symbols, categories = alb_readin(lib_name+'.TopCat', argv)
  }
  out_dir = './pictures'
  tar_file = alb_pack_symbols lib_name, symbols, categories, out_dir, grid_size
  
  comment = "symbol pictures for #{lib_name} updated"
  puts "comment: '#{comment}'"
  
  alb = alb_gear
  
  project_upload alb, project, tar_file, comment
end
=end

def start_service alb, conf_file = 'alb.conf'
  require 'drb/drb'
  if OPTS[:alb_gear_port]
    alta_server = "#{`hostname`.chomp}:#{OPTS[:alb_gear_port]}"
    uri = "druby://#{alta_server}"
  else
    uri = nil
  end
  
  DRb.start_service(uri, alb)
  (uri = DRb.uri) =~ /druby:\/\/(.*)/
  alta_server = $1
  rewrite conf_file, alta_server
  puts "ALB_Gear_server started at: '#{uri}'"
  Signal.trap(:INT){
    puts "Interrupted"; 
    alb.close
    rewrite conf_file # remove :alta_server: from alta.conf
    exit
  }
  uri
end

def rewrite conf_file='alb.conf', alta_server=nil
  unless File.exist? conf_file
    File.open(conf_file, 'w'){|f| f.print ''}
    return 
  end
  alb_conf = File.read(conf_file).encode('UTF-8', invalid: :replace)
  new_conf = ''
  flag = nil
  alb_conf.each_line{|l|
    if l =~ /:alta_server:/ 
      if alta_server
        new_conf << ":alta_server: #{alta_server}\n"
        puts "':alta_server: #{alta_server}' replaced in #{conf_file}"
      else
        puts "':alta_server: line removed from #{conf_file}" 
      end
      flag = true
    else
      new_conf << l unless l =~ /^---/
    end
  }
  if flag.nil? && alta_server
    new_conf = ":alta_server: #{alta_server}\n" + new_conf 
    puts "':alta_server: #{alta_server}' added in #{conf_file}" 
  end
  File.open(conf_file, 'w'){|f| f.print new_conf}
  new_conf
end

def project_upload alb, project, tar_file, comment
  begin
    if project_path = alb.open_project(project)
      upload_or_move_and_commit alb, project, tar_file, comment
      browser_visit project_path if OPTS[:browser] && OPTS[:browser].split != ''
      return project_path
    else
      raise "Project '#{project}' does not exist"
    end
  rescue => error
    puts error; puts error.backtrace
#    exit
  ensure
    alb_close alb
  end
end

def model_library_upload alb, project, model_library, tar_file, comment, simulator='Spectre', original_path=''
  begin
    if project_path = alb.open_project(project)
      model_library_path = alb.open_model_library model_library, simulator, original_path
      alb.model_library_upload File.expand_path(tar_file), comment
      browser_visit project_path if OPTS[:browser]
      return model_library_path
    else
      raise "Model Library '#{model_library}' does not exist under '#{project}'"
    end
  rescue => error
    puts "Error: #{error}"; puts error.backtrace
#    exit
  ensure
    alb_close alb
  end
end

def library_upload alb, project, library, tar_file, comment
  begin
    if project_path = alb.open_project(project)
      library_path = alb.open_library library, original_path=''      
      alb.library_upload File.expand_path(tar_file), comment
      return [library_path, project_path]
    else
      raise "Library '#{library}' does not exist under '#{project}'"
    end
  rescue => error
    puts "Error: #{error}"; puts error.backtrace
#    exit
  ensure
    alb_close alb
  end
end

def browser_visit project_path
  OPTS[:browser_port] ||= '4242'
  browser_alb_site = OPTS[:browser_alb_site] || OPTS[:alb_site] 
  
  dummy, project, project_id = project_path.split('/')
  puts "#{project}_path = #{project_path}"
  project_page = "/#{CGI.escape project}/#{project_id}"
  
  visit_url project_page
end

def alb_gear alta_server = OPTS[:alta_server], do_return=nil
  if alta_server
    require 'drb/drb'
    begin
#      DRb.start_service   # this is necessary when client serves variables
      alb = DRbObject.new_with_uri "druby://#{alta_server}"
      if alb.alb_site.nil?      
        return do_return ? alb : nil 
      end
      page = alb.agent.page
      server_name, = alta_server.split(':')
      host_name = `hostname`.chomp
      puts "server IP address #{server_name}: #{IPSocket.getaddress(server_name)}"   
      puts "host name: #{host_name}"
      puts "host IP address #{host_name}: #{IPSocket.getaddress(host_name)}"   
      if IPSocket.getaddress(server_name) == IPSocket.getaddress(host_name)
        puts "alb=#{alb.inspect}"
        return alb
      else
        ALBgear.new alb.alb_site, alb.abc, alb.def
      end
    rescue => error
      raise "Error: #{error} ---> server 'druby://#{alta_server}' may have aborted"
#      exit
    end
  else
    ALBgear.new OPTS[:alb_site], OPTS[:login], OPTS[:password]
  end
end

def alb_close alb
#  alb.close unless alb.alta_server # do not close anyway
end

def save_conf conf_file, keys, load_conf=true
  # puts "keys=#{keys.inspect}"
  if load_conf && File.exist?(conf_file)
    opts = YAML.load(File.read conf_file)||{}
  else
    opts = {}
  end
  File.open(conf_file, 'w'){|f|
    keys.each{|key|
      opts[key] = OPTS[key]
    }
    f.puts opts.to_yaml
  }
end

def load_conf config_file='./alb.conf'
#  puts "Load configuration from '#{File.expand_path config_file}'"
  if File.exist? config_file
    opts = YAML.load(File.read config_file) || {}
#  else 
#    file = File.join ENV['HOME'], config_file
#    if File.exist? file
#      opts = YAML.load(File.read file) || {}
#    else
#      opts = {}
#    end
  end
end

def parse_alb_site http_str
  if /https*:\/\/([^:\/]+)[:\/]/ =~ http_str +'/'
    return $1
  end
end

def check_directory path, default
  dir = File.expand_path(path || default)
  return dir if File.exist? dir
  raise "'#{dir}' does not exist"
#  exit
end

def expand_and_check ade_path
  if ade_path
    remove_trailing '/', ade_path
    if File.exist? ade_path = File.expand_path(ade_path)
      puts "ade_path=#{ade_path}" # ADE working directory (where cds.lib resides)    
    else
      raise "ADE working directory '#{ade_path}' does not exist"
    end
  else
    ade_path = '.'
  end
  ade_path
end

def remove_trailing char, string
  string[-1] = '' if string[-1, 1] == char
  string
end

def upload_or_move_and_commit alb, project, tar_file, comment
  if proj_repo_dir = ENV['PROJECT_REPO_DIR']
    gzip_file = File.expand_path tar_file
    proj_dir = File.join(proj_repo_dir, project)
    proj_dir_init proj_dir, project
    Dir.chdir(proj_dir){|dir|
      unzip gzip_file
      git_commit_cds_lib comment
    }
    print "'#{tar_file}' unzipped."
  else
    print "'#{File.expand_path tar_file}' (#{File.size tar_file} bytes) upload started.\n"
    alb.project_upload File.expand_path(tar_file), comment
    print "'#{File.expand_path tar_file}' uploaded.\n"
  end
end

def proj_dir_init proj_dir, name
  unless File.exist? proj_dir
    FileUtils.mkdir_p proj_dir
    Dir.chdir(proj_dir){|dir|
      system "git init"
      File.open('.git/description', 'w'){|f| 
        f.puts "ADE repository for '#{name}'"
      }
      FileUtils.mkdir 'models'
    }
  end
end

def git_commit_cds_lib comment
  cds_libs = Dir.glob('**/cds.lib') + Dir.glob('**/alb.lib') 
  ads_workspaces = Dir.glob('**/workspace.ads')
  if cds_libs.size > 0
      cds_lib = cds_libs.first
    unless cds_lib == 'cds.lib' || cds_lib == 'alb.lib'
      dir = File.dirname cds_lib
      system "/bin/mv #{dir}/*.* ."
    end
  elsif ads_workspaces.size > 0 
  else
    return 
  end
  now = "#{Time.now.strftime("%Y-%m-%d %X")}"
  system "git add .; git commit -am '#{comment||now}'"
end

def unzip gzip_file
  basename = File.basename(gzip_file).downcase
  if File.extname(gzip_file) =~ /\.alb|\.zip/
    system "unzip -o '#{gzip_file}'" # -o overwrite
    return basename.gsub('.zip', '')
  elsif File.extname(gzip_file) == '.gz' || File.extname(gzip_file)== '.tgz'
    system "/bin/tar xzf '#{gzip_file}'"
    return basename.gsub('.tgz', '').gsub('.tar.gz', '')
  elsif File.extname(gzip_file) == 'bz2'
    system "/bin/tar xjf '#{gzip_file}'"
    return basename.gsub('.bz2', '')
  elsif File.extname(gzip_file) == '.tar'
    system "/bin/tar xf '#{gzip_file}'"
    return basename.gsub('.tar', '')
  end
end

def create_or_copy_simulation_directory ade_path, testbenches, simulation_dir = nil
  if simulation_dir
    simulation_dir = File.expand_path(simulation_dir)
  else
    simulation_dir = File.join(ENV['HOME'], 'simulation')
  end
  testbenches ||= Dir.glob(simulation_dir+'/*').map{|tb| File.basename(tb)}
  Dir.chdir(ade_path){
    FileUtils.mkdir './simulation' unless File.exist? './simulation'
    unless simulation_dir == File.expand_path('./simulation') 
      testbenches.each{|tb|
        unless File.exist? src=File.join(simulation_dir, tb)
          raise "Error: '#{src}' does not exist"
        end
        dest = './simulation/'+tb
        FileUtils.rm_r dest, {:verbose => true} if File.exist? dest
#        FileUtils.cp_r src, dest, {:preserve => true, :verbose => true}
      }
      exclude_files = testbenches.map{|tb| excludes "simulation/#{tb}"}.join(' ')
      puts command = "(cd '#{simulation_dir}'; /bin/tar cf - #{testbenches.join(' ')} #{exclude_files})|(cd './simulation'; /bin/tar xf -)"
      system command
    end
  }
end

def excludes path, limit=10000000 # 10Mega byte
  files = Dir.glob(path + '/**/*') + Dir.glob(path + '/**/.*')
  result = []
  files.each{|f|
    if File.ftype(f) == 'file' &&  File.size(f) > limit # limit is
      result << f 
    end
  }
  if result.size > 0
    if result.size == 1
      puts "Below file will be excluded due to file size limit=#{limit}"
    else
      puts "Below files will be excluded due to file size limit=#{limit}"
    end
    result.each{|r| printf "%-16d%s\n", File.size(r), r}
    result.map{|r| "--exclude #{r}"}.join(' ')
  else
    ''
  end
end

def relative_path path, origin
  exp_path = File.expand_path path
  exp_origin = File.expand_path origin
  if exp_path.include? exp_origin
    path.sub(/#{origin.sub(/\/$/, '')}\//, '') if path
  else
    path
  end
end

def canonical_path path
  if File.file? path
    Dir.chdir(File.dirname path){return File.join(Dir.pwd, File.basename(path))}
  elsif File.exist? path
    Dir.chdir(path){return Dir.pwd}
  else
    puts "Error: #{path} does not exist!"
    raise "#{path} does not exist!"
  end
end    

def longest_common_substr(strings)
  shortest = strings.min_by &:length
if shortest.nil?
  debugger 
  return
end
  maxlen = shortest.length
  maxlen.downto(1) do |len|
    0.upto(maxlen - len) do |start|
      substr = shortest[start,len]
      return substr if strings.all?{|str| str.include? substr }
    end
  end
end

def unwrap netlist, dummy=nil    # line is like:
  result = ''         # abc
  breaks = []         #+def   => breaks[0]=[3]
  pos = 0
  line = '' 
  bs_breaks = []
  netlist.each_line{|l|  # line might be 'abc\n' or 'abc\r\n'
    next if l[0,1] == '*' || l[0,1] == '/'  # just ignore comment lines
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

def wrap line, breaks
  return line if breaks.size == 0
  line_copy = line.dup
  breaks.reverse_each{|pos|
    if pos>0
      line_copy[pos..pos] = "\n+" + line_copy[pos..pos]  # insert
    else
      line_copy[-pos..-pos] = "\\\n"    # just replace 
    end
  }
  line_copy
end

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

def wget_install file
  log = ''
  Dir.chdir(mytmp '/tmp'){
    log << `rm -f #{file}`
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

def close_help
  #    $help.close if $help && $help.id > 0
  $help.terminate if $help && $help.state != 0
  #    $user_guide.close if $user_guide && $user_guide.id > 0
  $user_guide.terminate if $user_guide && $user_guide.state != 0
end

def IO_popen(command)
  if /mswin32|mingw|cygwin/ =~ RUBY_PLATFORM
    if command.class == Array
      proc = IO.popen command.map{|f| 
        if f.include? '<%='
          ERB.new(f).result(binding)
        else
          get_short_path_name(f)
        end
      }.join(' ') 
    else
      proc = IO.popen get_short_path_name(command)
    end
  else
    sleep 0.2
    if command.class == Array
      proc = IO.popen command.map{|f| 
        if f.include? '<%='
          ERB.new(f).result(binding)
        else
          f
        end
      }.join(' ') 
    else
      proc = IO.popen ERB.new(command).result(binding)
    end
  end
  if command =~ /wine +/ && wine_version() < '1.8'
    sleep 1
    gid = Process.getpgid(proc.pid)
    puts "gid=#{gid}, proc.pid=#{proc.pid} "
    for i in 1..5
      pid_i = proc.pid + i
      begin
        print "For pid_i=#{pid_i} "
        gid_i = Process.getpgid(pid_i)
        puts "=> gid_i=#{gid_i}"
      rescue => error
        puts error
        next
      end
      return pid_i if gid_i == gid
    end
    return -1
  else
    puts "proc=#{proc.inspect}, proc.pid = #{proc.pid}"
    return proc.pid
  end
rescue => error
  raise "Error: Cannot start #{command} (#{error})"
end

def wine_version
  `wine --version` =~ /wine-(\S+)/
  version = $1
end
private :wine_version

def ltspice_sym_path ltspice_path
  if $LTspice_path =~ /scad3.exe/
    File.join(File.dirname($LTspice_path), 'lib/sym')
  elsif File.exist? File.join(ENV['HOME'], 'LTspiceXVII')
    File.join(ENV['HOME'], 'LTspiceXVII', 'lib/sym')
  elsif File.exist? File.join(ENV['HOME'], 'Documents', 'LTspiceXVII')
    File.join(ENV['HOME'], 'Documents', 'LTspiceXVII', 'lib/sym')
  elsif File.exist? File.join(ENV['HOME'], 'ドキュメント', 'LTspiceXVII')
    File.join(ENV['HOME'], 'ドキュメント', 'LTspiceXVII', 'lib/sym')
  elsif $LTspice_path
    File.join(File.dirname($LTspice_path), 'lib/sym')
  end
end

if RUBY_PLATFORM=~/mswin32|mingw|cygwin/
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
    len = GetShortPathName.call(long_name.dup, nil, 0)
    raise "File not found: #{long_name}" if len.zero?
    short_name = "\0" * len
    GetShortPathName.call(long_name.dup, short_name, len)
    short_name.gsub!(/\0/, '') # avoid string contains null byte error
    short_name.tr!('/', '\\')
    #    puts "Windows #{RUBY_VERSION}: #{long_name} => #{short_name}"
    return short_name
  end

  def windows_which tool
      tool << '.exe' unless tool.include? '.exe'
      p=IO.popen 'where ' + tool
      while l = p.gets
        if l.include? tool
          return l.chop.gsub("\\", '/')
        end
      end
    end
end

def which tool
  if RUBY_PLATFORM=~/mswin32|mingw|cygwin/
    windows_which tool
  else
    `which #{tool}`.chomp
  end
end

def visit_url url
  command = ENV['ALB_WEB_BROWSER']
  if /mswin32|mingw/ =~ RUBY_PLATFORM
    command ||= 'start'
  else
    command ||= 'xdg-open'
  end
  puts "IO.popen: #{command} #{url}"
  if /mswin32|mingw/ =~ RUBY_PLATFORM
    IO.popen("#{command} #{url}", :err =>[:child, :out]){|p|
      if message = p.gets
        raise message if message.strip != ''
      end
    }
  else
    fork do
      IO.popen("#{command} '#{url}'", :err =>[:child, :out]){|p|
        message = p.gets
        raise message if message.strip != ''
      }
    end
  end
  true
end

def linux_variant
  r = { :distro => nil, :family => nil }

  if File.exists?('/etc/lsb-release')
    File.open('/etc/lsb-release', 'r').read.each_line do |line|
      r = { :distro => $1 } if line =~ /^DISTRIB_ID=(.*)/
    end
  end

  if File.exists?('/etc/debian_version')
    r[:distro] = 'Debian' if r[:distro].nil?
    r[:family] = 'Debian' if r[:variant].nil?
  elsif File.exists?('/etc/redhat-release') or File.exists?('/etc/centos-release')
    r[:family] = 'RedHat' if r[:family].nil?
    r[:distro] = 'CentOS' if File.exists?('/etc/centos-release')
  elsif File.exists?('/etc/SuSE-release')
    r[:distro] = 'SLES' if r[:distro].nil?
  end

  return r
end

def on_WSL?
  File.exist?('/proc/version') && `grep -E "(MicroSoft|Microsoft|WSL)" /proc/version` != ''
end

def proj_match proj
  proj =~ /\(([0-9a-zA-Z|_\-=@\., \#\*]+)\((.*)\)\)$/ ||
    proj =~ /(\A[0-9a-zA-Z|_\-=@\., \#\*]+)\((.*)\)$/ ||
    proj =~ /\(([0-9a-zA-Z|_\-=@\., \#\*]+)\)/ ||
    proj =~ /(\A[0-9a-zA-Z|_\-=@\., \#\*]+)$/
  $1
end

if $0 == __FILE__
  create_or_copy_simulation_directory '.', ['testMOS2','testMOS'], simulation_dir = '/export/home/anagix/moriyama/simulation'
end
