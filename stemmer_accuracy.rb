def gem_available?(name)
   Gem::Specification.find_by_name(name)
rescue Gem::LoadError
   false
end

if not gem_available?('ffi')
  puts "Can't find gem - ffi. To install run '[sudo] gem install ffi'"
  exit(1)
end

$options = {}
$libvarnam_major_version = 3

def find_libvarnam
  return $options[:library] if not $options[:library].nil?
  # Trying to find out libvarnam in the predefined locations if
  # absolute path to the library is not specified
  libvarnam_search_paths = ['.', '/usr/local/lib', '/usr/local/lib/i386-linux-gnu', '/usr/local/lib/x86_64-linux-gnu', '/usr/lib/i386-linux-gnu', '/usr/lib/x86_64-linux-gnu', '/usr/lib']
  libvarnam_names = ['libvarnam.so', "libvarnam.so.#{$libvarnam_major_version}", 'libvarnam.dylib', 'varnam.dll']
  libvarnam_search_paths.each do |path|
    libvarnam_names.each do |fname|
      fullpath = File.join(path, fname)
      if File.exists?(fullpath)
        return fullpath
      end
    end
  end
  return nil
end

$options[:library] = find_libvarnam
if $options[:library].nil?
  puts "varnamc - Can't find varnam shared library. Try specifying the full path using -l option"
  puts optparse
else
  puts "Using #{$options[:library]}"
end

varnamruby_searchpaths = [".", "/usr/local/lib", "/usr/lib"]
varnamruby_loaded = false
varnamruby_searchpaths.each do |p|
  begin
    require "#{p}/varnamruby.rb"
    varnamruby_loaded = true
    break
  rescue LoadError
    # Trying next possibility
  end
end

if not varnamruby_loaded
  puts "Failed to find varnamruby.rb. Search paths: #{varnamruby_searchpaths}"
  puts "This could be because you have a corrupted installation or a bug in varnamc"
  exit(1)
end

require 'optparse'
require 'fileutils'

$options[:action] = nil
def set_action(a)
  if $options[:action].nil?
    $options[:action] = a
  else
    puts "varnamc : #{$options[:action]} and #{a} are mutually exclusive options. Only one action is allowed"
    exit(1)
  end
end


optparse = OptionParser.new do |opts|
  opts.banner = "Usage: varnamc options args"

  # ability to provide varnam library name
  $options[:symbols_file] = nil
  opts.on('-s', '--symbols VALUE', 'Sets the symbols file') do |value|
    if File.exist?(value)
      $options[:symbols_file] = value
    else
      $options[:lang_code] = value;
    end
  end

  opts.on('-f', '--source-file FILE', 'Sets the source file') do |value|
  	if File.exist?(value)
  		$options[:source_file] = value
  	end
  end

end

begin
  optparse.parse!
rescue
  puts "varnamc : incorrect arguments"
  puts optparse
  exit(1)
end


$suggestions_file = ''

def initialize_varnam_handle
  if $options[:action] == 'compile'
    $vst_file_name = $options[:file_to_compile].sub(File.extname($options[:file_to_compile]), "") + ".vst"

    if not $options[:output_directory].nil?
      $vst_file_name = get_file_path(File.basename($vst_file_name))
    end

    if File.exists?($vst_file_name)
      File.delete($vst_file_name)
    end
  else
    $vst_file_name = $options[:symbols_file]
  end

  initialized = false;
  $varnam_handle = FFI::MemoryPointer.new :pointer
  init_error_msg = FFI::MemoryPointer.new(:pointer, 1)
  if not $vst_file_name.nil?
    initialized = VarnamLibrary.varnam_init($vst_file_name, $varnam_handle, init_error_msg)
    # Configuring suggestions
    $options[:learnings_file] = get_learnings_file $vst_file_name
    configured = VarnamLibrary.varnam_config($varnam_handle.get_pointer(0), Varnam::VARNAM_CONFIG_ENABLE_SUGGESTIONS, :string, $options[:learnings_file])
    if configured != 0
        error_message = VarnamLibrary.varnam_get_last_error($varnam_handle.get_pointer(0))
        error error_message
        exit(1)
    end
  elsif not $options[:lang_code].nil?
    initialized = VarnamLibrary.varnam_init_from_lang($options[:lang_code], $varnam_handle, init_error_msg)
    if initialized == 0 and not $options[:learnings_file].nil?
      # User has specified explicit learnings file. Use that instead of the default one
      configured = VarnamLibrary.varnam_config($varnam_handle.get_pointer(0), Varnam::VARNAM_CONFIG_ENABLE_SUGGESTIONS, :string, $options[:learnings_file])
      if configured != 0
        error_message = VarnamLibrary.varnam_get_last_error($varnam_handle.get_pointer(0))
        error error_message
        exit(1)
      end
    end
  else
    puts "varnamc : Can't load symbols file. Use --symbols option to specify the symbols file"
    exit(1)
  end

  if (initialized != 0)
    ptr = init_error_msg.read_pointer()
    msg = ptr.nil? ? "" : ptr.read_string
    puts "Varnam initialization failed #{msg}"
    exit(1)
  end

end

def convert_to_text(words_ptr)
	word_ptr = VarnamLibrary.varray_get(words_ptr.get_pointer(0), 0)
	vword = VarnamLibrary::Word.new(word_ptr)
	word = VarnamWord.new(vword[:text], vword[:confidence])
	return word.text
end


initialize_varnam_handle
totl = "avaLuTe"
words_ptr = FFI::MemoryPointer.new :pointer
VarnamLibrary.varnam_transliterate($varnam_handle.get_pointer(0), totl, words_ptr)
puts "Transliteration done"
puts convert_to_text(words_ptr)


if not $options[:source_file].nil?
	total=0
	correct=0
	source = File.open($options[:source_file], "r")
	source.each_line do |line|
		words = line.split(" ")
		results = FFI::MemoryPointer.new :pointer
		VarnamLibrary.varnam_transliterate($varnam_handle.get_pointer(0), words[1], results)
		transliteration = convert_to_text(results)
		transliteration.force_encoding('UTF-8')
		if transliteration.eql? words[0]
			correct = correct + 1
		end
		VarnamLibrary.varnam_learn($varnam_handle.get_pointer(0), words[0])
		total = total + 1
	end
	source.close

	puts "accuracy ", correct.to_f/total
end
