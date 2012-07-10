#include <dlfcn.h>

#include "prelude.hpp"
#include "environment.hpp"
#include "objectmemory.hpp"
#include "arguments.hpp"
#include "kernel.hpp"
#include "constantscope.hpp"

#include "builtin/array.hpp"
#include "builtin/class.hpp"
#include "builtin/exception.hpp"
#include "builtin/string.hpp"
#include "builtin/symbol.hpp"
#include "builtin/module.hpp"
#include "builtin/nativemethod.hpp"

namespace rubinius {
	void Kernel::load(STATE, CompiledMethod** cmethods) {
    void* handle = dlopen(path_.c_str(), RTLD_LAZY);
    if (!handle) {
      std::cerr << "Cannot open " << path_ << ": " << dlerror() << std::endl;
      exit(1);
    }

    typedef void (*kernel_cmethods_t)(STATE, CompiledMethod**);

    dlerror();
    kernel_cmethods_t kernel_cmethods = (kernel_cmethods_t) dlsym(handle, "kernel_cmethods");
    const char *dlsym_error = dlerror();

    if (dlsym_error) {
      std::cerr << "Cannot load symbol 'kernel_cmethods': " << dlsym_error << std::endl;
      dlclose(handle);
      exit(1);
    }

    kernel_cmethods(state, cmethods);
    dlclose(handle);
  }

  void Kernel::execute(STATE) {
    CompiledMethod* cmethods[1024];
    load(state, cmethods);

    for (int i = 0; i < 1024; i++) {
      if (cmethods[i]) {
        printf("%d\n", i);
        TypedRoot<CompiledMethod*> cm(state, as<CompiledMethod>(cmethods[i]));

        state->thread_state()->clear(); // Required for each time?

        Arguments args(state->symbol("script"), G(main), 0, 0);

        cm.get()->scope(state, ConstantScope::create(state));
        cm.get()->scope()->module(state, G(object));

        cm->execute(state, NULL, cm.get(), G(object), args);

        if(state->vm()->thread_state()->raise_reason() == cException) {
          Exception* exc = as<Exception>(state->vm()->thread_state()->current_exception());
          std::ostringstream msg;

          msg << "exception detected at toplevel: ";
          if(!exc->message()->nil_p()) {
            if(String* str = try_as<String>(exc->message())) {
              msg << str->c_str(state);
            } else {
              msg << "<non-string Exception message>";
            }
          } else if(Exception::argument_error_p(state, exc)) {
            msg << "given "
                << as<Fixnum>(exc->get_ivar(state, state->symbol("@given")))->to_native()
                << ", expected "
                << as<Fixnum>(exc->get_ivar(state, state->symbol("@expected")))->to_native();
          }
          msg << " (" << exc->klass()->debug_str(state) << ")";
          std::cout << msg.str() << "\n";
          exc->print_locations(state);
          Assertion::raise(msg.str().c_str());
        }
      } else {
        break;
      }
    }
  }
}