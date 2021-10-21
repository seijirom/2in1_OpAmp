class CompactModel
  attr_accessor :type, :name, :model_params, :file
  require 'spice_parser'
  require 'alb_lib'
  def initialize file, name=nil
    @file = file
    @type, @name, @model_params = load file, name
    @orig_params = @model_params.dup
  end

  def help
  puts "help:"
  puts " help --- show this message"
  puts " model_params --- show current model parameters"
  puts " file --- show default file name"
  puts " type --- show current model type"
  puts " reset --- reset to initial CompactModel(file) parameters"
  puts " update model_params[, file] --- modify model parameters in a file"
  puts " load file --- replace model parameters with loaded from file"
  puts " save [file] --- save model parameters in a file"
  puts " set parm1: value, param2: value ... --- change model parameters"
  puts " get param --- get model parameter value" 
  puts " show parm1, param2, ... --- show specified model parameters"
  puts " delete param --- delete model parameter and value"
  end

  def reset
    @model_params = @orig_params.dup
  end

  def load file, name=nil
    @type, @name, @model_params = parse_model File.read(file), name
  end

  def update model_params_temp = @model_params, file = @file
    description = ''
    model_params = {}
    model_params_temp.each_pair{|k, v|
      model_params[k.to_s] = v
    }
    model_found = nil 
    File.read(file).each_line{|l|
      if l.downcase =~ /\.model +(\S+)/
        if $1.downcase == name.downcase
          model_found = true
        else
          model_found = nil
        end
      elsif model_found
        if l =~ /^ *\+ *(\S+)( *= *(\S+))/
          p=$1
          pattern = $2
          v=$3
          if model_params[p] && (model_params[p] != v)
            print l
            l.sub!(pattern, " = #{model_params[p]}")
            puts " ===> #{l}"
          end
        end
      end
      description << l
    }
    File.open(file, 'w'){|f|
      f.puts description
    }
  end

  def save file = @file
    description = File.read @file
    File.open(file, 'w'){|f|
      model_found = nil
      description.each_line{|l|
        if l.downcase =~ /\.model +(\S+)/
          if $1.downcase == @name.downcase
            model_found = true
          elsif model_found
            f.puts ".MODEL #{@name} #{@type}"
            @model_params.each_pair{|k, v|
              f.puts "+ #{k} = #{v}"
            }
            model_found = nil
            f.puts l
          else
            f.puts l 
          end
        elsif model_found.nil?
          f.puts l
        end
      }
      if model_found
        f.puts ".MODEL #{@name} #{@type}"
        @model_params.each_pair{|k, v|
          f.puts "+ #{k} = #{v}"
        }
      end
    }
  end

  def set props
    actual_props = {}
    props.each_pair{|p, v|
      a = actual p
      @model_params[a] = v.to_s
      actual_props[a] = v
    }
    actual_props
  end

  def get param
    @model_params[actual param]
  end
  
  def actual p
    @model_params[s = p.to_s] and return s
    @model_params[u = s.upcase] and return u
    @model_params[l = s.downcase] and return l
    @model_params[c = s.capitalize] and return c
    s
  end
  private :actual

  def show *params
    params.map{|param|
      get param
    }
  end

  def delete param
    @model_params.delete param.to_s
  end
end

=begin
def modify_model inputs
  vt0 = inputs[:vt0].to_f
  vt0 = vt0*1.2
  outputs = {}
  outputs[:vt0] = vt0
  outputs
end

def activate_model file, params
  require 'spice_parser'
  type, name, model_params = parse_model File.read(file)
  outputs = modify_model vt0: model_params['VTH0']
end

def write_model model_params, file
  description = ''
  File.read(file).each_line{|l|
    if l =~ /^ *\+ *(\S+) *= *(\S+)/
      p=$1
      v=$2
      if model_params[p] != v
        print l
        l.sub!(/ *= *#{v}/, " = #{model_params[p]}")
        puts " ===> #{l}"
      end
    end
    description << l
  }
  File.open(file, 'w'){|f|
    f.puts description
  }
end

=end
