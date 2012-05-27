#include "call_frame.hpp"

#include "capi/capi.hpp"
#include "capi/19/include/ruby/ruby.h"

using namespace rubinius;
using namespace rubinius::capi;

extern "C" {
	ID rb_frame_this_func() {
    NativeMethodEnvironment* env = NativeMethodEnvironment::get();
    CallFrame* cf = env->current_call_frame();

    if (cf->native_method_p()) {
    	NativeMethodFrame* nmf = cf->native_method_frame();
    	NativeMethod* nm = try_as<NativeMethod>(nmf->get_object(nmf->method()));
      return env->get_handle(nm->name());
    } else {
      return env->get_handle(cf->name());	
    }
  }
}
