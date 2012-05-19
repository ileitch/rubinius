#include "builtin/nativemethod.hpp"
#include "objectmemory.hpp"
#include "gc/baker.hpp"
#include "capi/capi.hpp"
#include "capi/handle.hpp"
#include "capi/18/include/ruby.h"

namespace rubinius {
  namespace capi {

    bool Handle::valid_handle_p(STATE, Handle* handle) {
      Handles* global_handles = state->shared().global_handles();
      for(Allocator<Handle>::Iterator i(global_handles->allocator()); i.more(); i.advance()) {
        if(i.current() == handle) return true;
      }
      return false;
    }

    void Handle::free_data() {
      if(as_.cache_data) {
        switch(type_) {
        case cRArray:
          delete[] as_.rarray->dmwmb;
          delete as_.rarray;
          break;
        case cRString:
          delete as_.rstring;
          break;
        case cRFloat:
          delete as_.rfloat;
          break;
        case cRIO:
          // When the IO is finalized, the FILE* is closed.
          delete as_.rio;
          break;
        case cRFile:
          delete as_.rfile;
          break;
        case cRData:
          delete as_.rdata;
          break;
        default:
          break;
        }
        as_.cache_data = 0;
      }

      type_ = cUnknown;
    }

    void Handle::debug_print() {
      std::cerr << std::endl << "Invalid handle usage detected!" << std::endl;
      std::cerr << "  handle:     " << this << std::endl;
      std::cerr << "  checksum:   0x" << std::hex << checksum_ << std::endl;
      std::cerr << "  references: " << references_ << std::endl;
      std::cerr << "  type:       " << type_ << std::endl;
      std::cerr << "  object:     " << object_ << std::endl;
    }

    Handles::~Handles() {
      delete allocator_;
    }


    Handle* Handles::allocate(STATE, Object* obj) {
      bool needs_gc = false;
      Handle* handle = allocator_->allocate(&needs_gc);
      handle->set_object(obj);
      handle->validate();
      if(needs_gc) {
        state->memory()->collect_mature_now = true;
      }
      return handle;
    }

    void Handles::deallocate_handles(std::list<Handle*>* cached, int mark, BakerGC* young) {

      std::vector<bool> chunk_marks(allocator_->chunks_.size(), false);

      size_t i = 0;

      for(std::vector<Handle*>::iterator it = allocator_->chunks_.begin();
          it != allocator_->chunks_.end(); ++it) {
        Handle* chunk = *it;

        for(size_t j = 0; j < allocator_->cChunkSize; j++) {
          Handle* handle = &chunk[j];

          Object* obj = handle->object();

          if(!handle->in_use_p()) {
            continue;
          }

          // Strong references will already have been updated.
          if(!handle->weak_p()) {
            chunk_marks[i] = true;
            continue;
          }

          if(young) {
            if(obj->young_object_p()) {

              // A weakref pointing to a valid young object
              //
              // TODO this only works because we run prune_handles right after
              // a collection. In this state, valid objects are only in current.
              if(young->in_current_p(obj)) {
                chunk_marks[i] = true;
              // A weakref pointing to a forwarded young object
              } else if(obj->forwarded_p()) {
                handle->set_object(obj->forward());
                chunk_marks[i] = true;
              // A weakref pointing to a dead young object
              } else {
                handle->clear();
              }
            } else {
              // Not a young object, so won't be GC'd so mark
              // chunk as still active
              chunk_marks[i] = true;
            }

          // A weakref pointing to a dead mature object
          } else if(!obj->marked_p(mark)) {
            handle->clear();
          } else {
            chunk_marks[i] = true;
          }
        }
        ++i;
      }

      // Cleanup cached handles
      for(std::list<Handle*>::iterator i = cached->begin(); i != cached->end();) {
        Handle* handle = *i;
        if(handle->in_use_p()) {
          ++i;
        } else {
          i = cached->erase(i);
        }
      }

      i = 0;
      for(std::vector<Handle*>::iterator it = allocator_->chunks_.begin();
          it != allocator_->chunks_.end();) {
        // No header was marked, so it's completely empty. Free it.
        if(!chunk_marks[i]) {
          Handle* chunk = *it;
          delete[] chunk;
          it = allocator_->chunks_.erase(it);
        } else {
          ++it;
        }
        ++i;
      }

      allocator_->rebuild_freelist();
    }

    HandleSet::HandleSet()
      : slow_(0)
    {
      for(int i = 0; i < cFastHashSize; i++) {
        table_[i] = 0;
      }
    }

    void HandleSet::deref_all() {
      for(int i = 0; i < cFastHashSize; i++) {
        if(table_[i]) table_[i]->deref();
      }

      if(slow_) {
        for(SlowHandleSet::iterator i = slow_->begin();
            i != slow_->end();
            ++i) {
          capi::Handle* handle = *i;
          handle->deref();
        }
      }
    }

    void HandleSet::flush_all(NativeMethodEnvironment* env) {
      for(int i = 0; i < cFastHashSize; i++) {
        if(table_[i]) table_[i]->flush(env);
      }

      if(slow_) {
        for(SlowHandleSet::iterator i = slow_->begin();
            i != slow_->end();
            ++i) {
          capi::Handle* handle = *i;
          handle->flush(env);
        }
      }
    }

    void HandleSet::update_all(NativeMethodEnvironment* env) {
      for(int i = 0; i < cFastHashSize; i++) {
        if(table_[i]) table_[i]->update(env);
      }

      if(slow_) {
        for(SlowHandleSet::iterator i = slow_->begin();
            i != slow_->end();
            ++i) {
          capi::Handle* handle = *i;
          handle->update(env);
        }
      }
    }

    bool HandleSet::slow_add_if_absent(Handle* handle) {
      for(int i = 0; i < cFastHashSize; i++) {
        if(table_[i] == handle) return false;
      }

      SlowHandleSet::iterator pos = slow_->find(handle);
      if(pos != slow_->end()) return false;

      slow_->insert(handle);
      handle->ref();

      return true;
    }

    void HandleSet::make_slow_and_add(Handle* handle) {
      // Inflate it to the slow set.
      slow_ = new SlowHandleSet;
      slow_->insert(handle);
      handle->ref();
    }
  }
}
