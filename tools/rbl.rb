require "stringio"

RUNTIME = "#{Dir.pwd}/runtime/19"
RBC = ['alpha.rbc']

File.readlines(RUNTIME + '/index').map do |dir|
	RBC.push(*File.readlines(RUNTIME + "/#{dir.chomp}/load_order.txt").map { |line| "#{dir.chomp}/#{line.chomp}" })
end

puts RBC

class IncrementalVariable
  def initialize
    @name = 'v'
    @incr = -1
  end

  def next
    @incr += 1
    "#{@name}#{@incr}"
  end

  def reset
    @incr = -1
  end
end

class StaticStrings
  attr_reader :strings

  def initialize(var)
    @var = var
    @strings = []
    @map = {}
    @i = -1
  end

  def index(str)
    if !@map[str]
      @i += 1
      @map[str] = @i
      @strings[@i] = str
    end

    "#{@var}[#{@map[str]}]"
  end
end

class Generator
	def initialize(rbc, cpp, var, strings)
    @file = rbc
    @cpp = cpp
    @rbc = File.open(rbc, 'r')
    3.times { @rbc.readline } # Skip magic, signature and version.
    @var = var
    @strings = strings
	end

  def close
    @rbc.close
  end

  def generate(lines = [])
    line = @rbc.readline
    case line.chomp
    when 'n'
      'cNil'
    when 't'
      'cTrue'
    when 'f'
      'cFalse'
    when 'I'
      generate_int(lines)
    when 's'
      generate_string(lines)
    when 'x'
      generate_symbol(lines)
    when 'p'
      generate_tuple(lines)
    when 'd'
      generate_float(lines)
    when 'i'
      generate_iseq(lines)
    when 'M'
      generate_cmethod(lines)
    when 'c'
      generate_constant(lines)
    when 'E'
      generate_encoding(lines)
    else
      raise "Unknown marshal code: #{line}"
    end
  end

  protected

  def generate_cmethod(lines)
    i = $i += 1
    @rbc.readline # skip version.
    args = 14.times.map { generate(lines) }.join(', ')
    @cpp.puts "// #{@file}"
    @cpp.puts "CompiledMethod* get_cmethod_#{i}(STATE) {"
    lines.each { |l| @cpp.write(l) }
    @cpp.puts("  return get_cmethod(state, #{args});")
    @cpp.puts "};"
    "get_cmethod_#{i}(state)"
  end

  def generate_iseq(lines)
    count = @rbc.readline.chomp.to_i
    opcodes = @var.next
    lines << "  const long #{opcodes}[#{count}] = {"
    lines << count.times.map { "#{@rbc.readline.chomp}L" }.join(', ')
    lines << "};\n"
    iseq = @var.next
    lines << "  InstructionSequence* #{iseq} = get_iseq(state, #{count}, #{opcodes});\n"
    iseq
  end

  def generate_int(lines)
    data = @rbc.readline.chomp
    "GET_INT(state, \"#{data}\")"
  end

  def generate_tuple(lines)
    count = @rbc.readline.chomp.to_i
    t = @var.next
    if count == 0
      lines << "  Tuple* #{t} = EMPTY_TUPLE(state);\n"
    else
      tvs = @var.next
      args = count.times.map { generate }
      lines << "  Object* #{tvs}[#{count}] = {"
      lines << args.join(', ')
      lines << "};\n"
      lines << "  Tuple* #{t} = get_tuple(state, #{count}, #{tvs});\n"
    end
    t
  end

  def generate_symbol(lines)
    count = @rbc.readline.chomp.to_i
    data = escape(@rbc.read(count))
    str_index = @strings.index(data)
    @rbc.read(1) # newline
    "GET_SYMBOL(state, #{str_index})"
  end

  def generate_string(lines)
    enc = generate
    count = @rbc.readline.chomp.to_i
    data = escape(@rbc.read(count))
    str_index = @strings.index(data)
    @rbc.read(1) # newline
    "get_string(state, #{count}, #{enc}, #{str_index})"
  end

  def generate_encoding(lines)
    count = @rbc.readline.chomp.to_i
    data = @rbc.read(count)
    @rbc.read(1) # newline
    if count == 0
      'cNil'
    else
      "GET_ENCODING(state, #{data.inspect})"
    end
  end

  FLOAT_EXP_OFFSET = 58
  def generate_float(lines)
    data = @rbc.readline.chomp.to_s
    float = data[0..FLOAT_EXP_OFFSET-1]
    exp = data[FLOAT_EXP_OFFSET..-1]
    "get_float(state, #{float.inspect}, #{exp.inspect})"
  end

  def escape(str)
    # TODO: Sort this shit out!
    str = str.inspect.gsub('\\', '\\\\').gsub('\#', '#')
    str = '"\\\#"' if str == '"\#"'
    str
  end
end

File.open(Dir.pwd + '/vm/runtime/kernel19.hpp', 'w') do |hpp|
  hpp.write <<-EOS

#define EMPTY_TUPLE(state) Tuple::create(state, 0)
#define GET_ENCODING(state, data) Encoding::find(state, data)
#define GET_INT(state, data) Bignum::from_string(state, data, 16)
#define GET_SYMBOL(state, data) state->symbol(data)

namespace rubinius {
  InstructionSequence* get_iseq(STATE, size_t count, const long* opcodes);
  Tuple* get_tuple(STATE, size_t count, Object** values);
  String* get_string(STATE, size_t count, Object* raw_enc, const char* data);
  Float* get_float(STATE, const char* data, const char* exp);
  CompiledMethod* get_cmethod(STATE, Object* metadata, Object* primitive, Symbol* name, InstructionSequence* iseq,
  Object* stack_size, Object* local_count, Object* required_args, Object* post_args, Object* total_args,
  Object* splat, Tuple* literals, Tuple* lines, Symbol* file, Tuple* local_names);
}
  EOS

end

File.open(Dir.pwd + '/vm/runtime/kernel19.cpp', 'w') do |cpp|
  cpp.write <<-EOS
#include <tommath.h>
#include <gdtoa.h>

#include "prelude.hpp"

#include "builtin/array.hpp"
#include "builtin/compiledmethod.hpp"
#include "builtin/encoding.hpp"
#include "builtin/fixnum.hpp"
#include "builtin/float.hpp"
#include "builtin/iseq.hpp"
#include "builtin/string.hpp"
#include "builtin/symbol.hpp"
#include "builtin/tuple.hpp"

#include "kernel19.hpp"

namespace rubinius {

InstructionSequence* get_iseq(STATE, size_t count, const long* opcodes) {
  InstructionSequence* iseq = InstructionSequence::create(state, count);
  Tuple* ops = iseq->opcodes();

  for(size_t i = 0; i < count; i++) {  
    ops->put(state, i, Fixnum::from(opcodes[i]));
  }

  iseq->post_marshal(state);
  return iseq;
}

Tuple* get_tuple(STATE, size_t count, Object** values) {
  Tuple* tup = Tuple::create(state, count);

  for(size_t i = 0; i < count; i++) {
    tup->put(state, i, values[i]);
  }

  return tup;
}

String* get_string(STATE, size_t count, Object* raw_enc, const char* data) {
  Encoding* enc = try_as<Encoding>(raw_enc);
  String* str = String::create(state, data, count);
  if(enc) str->encoding(state, enc);
  return str;
}

Float* get_float(STATE, const char* data, const char* exp) {
  if(data[0] == ' ') {
    double x;
    long   e;

    x = ::ruby_strtod(data, NULL);
    e = strtol(exp, NULL, 10);

    // This is necessary because exp2(1024) yields inf
    if(e == 1024) {
      double root_exp = ::exp2(512);
      return Float::create(state, x * root_exp * root_exp);
    } else {
      return Float::create(state, x * ::exp2(e));
    }
  } else {
    // avoid compiler warning
    double zero = 0.0;
    double val = 0.0;

    if(!strncasecmp(data, "Infinity", 8U)) {
      val = 1.0;
    } else if(!strncasecmp(data, "-Infinity", 9U)) {
      val = -1.0;
    } else if(!strncasecmp(data, "NaN", 3U)) {
      val = zero;
    } else {
      Exception::type_error(state, "Unable to unmarshal Float: invalid format");
    }

    return Float::create(state, val / zero);
  }
}

CompiledMethod* get_cmethod(STATE, Object* metadata, Object* primitive, Symbol* name, InstructionSequence* iseq,
  Object* stack_size, Object* local_count, Object* required_args, Object* post_args, Object* total_args,
  Object* splat, Tuple* literals, Tuple* lines, Symbol* file, Tuple* local_names) {
  
  CompiledMethod* cm = CompiledMethod::create(state);

  cm->metadata(state, metadata);
  cm->primitive(state, (Symbol*)primitive);
  cm->name(state, name);
  cm->iseq(state, iseq);
  cm->stack_size(state, (Fixnum*)stack_size);
  cm->local_count(state, (Fixnum*)local_count);
  cm->required_args(state, (Fixnum*)required_args);
  cm->post_args(state, (Fixnum*)post_args);
  cm->total_args(state, (Fixnum*)total_args);
  cm->splat(state, splat);
  cm->literals(state, literals);
  cm->lines(state, lines);
  cm->file(state, file);
  cm->local_names(state, local_names);

  cm->post_marshal(state);

  return cm;
}

EOS

toplevel_cmethods = []
kernel_strings = StaticStrings.new("kernel_strings")
var = IncrementalVariable.new
$i = 0

lines = StringIO.new

RBC.each do |rbc|
  g = Generator.new(RUNTIME + "/#{rbc}", lines, var, kernel_strings)
  toplevel_cmethods << g.generate
  g.close
  var.reset
end

cpp.puts("static const char* kernel_strings[] = {#{kernel_strings.strings.join(', ')}};\n")

lines.seek 0
cpp.write(lines.read)

cpp.write <<-EOS
extern "C" void kernel_cmethods(STATE, CompiledMethod** cmethods) {
  int i = 0;
  EOS

  toplevel_cmethods.each_with_index do |call, i|
    cpp.puts("  // #{i}")
    cpp.puts("  cmethods[i++] = #{call};")
  end

  cpp.puts <<-EOS
};

}
  EOS
end
