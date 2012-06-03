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
end

class Generator
	def initialize(rbc, cpp, var)
    @cpp = cpp
    @rbc = File.open(rbc, 'r')
    3.times { @rbc.readline } # Skip magic, signature and version.
    @var = var
	end

  def close
    @rbc.close
  end

  def generate
    line = @rbc.readline
    case line.chomp
    when 'n'
      'cNil'
    when 't'
      'cTrue'
    when 'f'
      'cFalse'
    when 'I'
      generate_int
    when 's'
      generate_string
    when 'x'
      generate_symbol
    when 'p'
      generate_tuple
    when 'd'
      generate_float
    when 'i'
      generate_iseq
    when 'M'
      generate_cmethod
    when 'c'
      generate_constant
    when 'E'
      generate_encoding
    else
      raise "Unknown marshal code: #{line}"
    end
  end

  protected

  def generate_cmethod
    @rbc.readline # skip version.
    args = 14.times.map { generate }.join(', ')
    "get_cmethod(state, #{args})"
  end

  def generate_iseq
    count = @rbc.readline.chomp.to_i
    opcodes = @var.next
    @cpp.write("const char* #{opcodes}[] = {")
    @cpp.write(count.times.map { "\"#{@rbc.readline.chomp}\"" }.join(', '))
    @cpp.puts("};")
    iseq = @var.next
    @cpp.puts("InstructionSequence* #{iseq} = get_iseq(state, #{count}, #{opcodes});")
    iseq
  end

  def generate_int
    data = @rbc.readline.chomp
    "get_int(state, \"#{data}\")"
  end

  def generate_tuple
    count = @rbc.readline.chomp.to_i
    if count == 0
      "get_tuple(state, #{count})"
    else
      args = count.times.map { generate }
      "get_tuple(state, #{count}, #{args.join(', ')})"
    end
  end

  def generate_symbol
    count = @rbc.readline.chomp.to_i
    data = escape(@rbc.read(count))
    @rbc.read(1) # newline
    "get_symbol(state, #{data})"
  end

  def generate_string
    enc = generate
    count = @rbc.readline.chomp.to_i
    data = escape(@rbc.read(count))
    @rbc.read(1) # newline
    "get_string(state, #{count}, #{enc}, #{data})"
  end

  def generate_encoding
    count = @rbc.readline.chomp.to_i
    data = @rbc.read(count)
    @rbc.read(1) # newline
    if count == 0
      'cNil'
    else
      "get_encoding(state, #{count}, #{data.inspect})"
    end
  end

  FLOAT_EXP_OFFSET = 58
  def generate_float
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

namespace rubinius {

Symbol* get_symbol(STATE, const char* data) {
  Symbol* sym = state->symbol(data);  
  return sym;
}

InstructionSequence* get_iseq(STATE, size_t count, const char** opcodes) {
  InstructionSequence* iseq = InstructionSequence::create(state, count);
  Tuple* ops = iseq->opcodes();

  long op = 0;
  for(size_t i = 0; i < count; i++) {  
    op = strtol(opcodes[i], NULL, 10);
    ops->put(state, i, Fixnum::from(op));
  }

  iseq->post_marshal(state);
  return iseq;
}

Object* get_int(STATE, const char *data) {
  return Bignum::from_string(state, data, 16);
}

Tuple* get_tuple(STATE, size_t count, ...) {
  Tuple* tup = Tuple::create(state, count);

  va_list objs;
  va_start(objs, count);

  for(size_t i = 0; i < count; i++) {
    Object* obj = va_arg(objs, Object*);
    tup->put(state, i, obj);
  }
          
  va_end(objs);
  return tup;
}

String* get_string(STATE, size_t count, Object* raw_enc, const char* data) {
  Encoding* enc = try_as<Encoding>(raw_enc);
  String* str = String::create(state, data, count);
  if(enc) str->encoding(state, enc);
  return str;
}

Object* get_encoding(STATE, size_t count, const char* data) {
  return Encoding* enc = Encoding::find(state, data);
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

extern "C" void kernel_cmethods(STATE, CompiledMethod** cmethods) {
  int i = 0;
  EOS

  var = IncrementalVariable.new
  RBC.each do |rbc|
    g = Generator.new(RUNTIME + "/#{rbc}", cpp, var)
    line = g.generate
    cpp.puts("cmethods[i++] = #{line};")
    g.close
  end

  cpp.puts <<-EOS
};

}
  EOS
end
