
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
