#ifndef RBX_KERNEL_HPP
#define RBX_KERNEL_HPP

#include <string>

#include "prelude.hpp"
#include "compiledmethod.hpp"

namespace rubinius {
  class Kernel {
  public:
    Kernel(std::string path)
    : path_(path) {}

    void execute(STATE);

  private:
    std::string path_;

    void load(STATE, CompiledMethod**);
  };
}

#endif