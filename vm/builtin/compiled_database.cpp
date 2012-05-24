#include <string>
#include <db_cxx.h>

#include "prelude.hpp"
#include "ontology.hpp"

#include "builtin/class.hpp"
#include "builtin/string.hpp"
#include "builtin/compiled_database.hpp"

namespace rubinius {
	void CompiledDatabase::close() {
	   try {
	        db_->close(0);
	    } catch(DbException &e) {
	        std::cerr << e.what() << std::endl;
	    } catch(std::exception &e) {
	        std::cerr << e.what() << std::endl;
	    }
	}

	CompiledDatabase* CompiledDatabase::open(STATE, Object* self, String* path) {
		CompiledDatabase* db = state->new_object<CompiledDatabase>(as<Class>(self));
		db->open_db(path->c_str(state));
	    return db;
	}

	void CompiledDatabase::open_db(const char* path) {
		db_ = new Db(NULL, 0);

		try {
			db_->open(NULL, path, NULL, DB_BTREE, DB_CREATE, 0);	
		} catch (DbException &e) {
		    std::cerr << e.what() << std::endl;
		} catch (std::exception &e) {
			std::cerr << e.what() << std::endl;
		}
	}

	Object* CompiledDatabase::write(STATE, String* file, String* sha, String* body) {
    	Dbt key(const_cast<void *>(reinterpret_cast<const void *>(file->c_str(state))), strlen(file->c_str(state)));
		Dbt data(const_cast<char*>(body->c_str(state)), strlen(body->c_str(state)));

		try {
        	db_->put(NULL, &key, &data, 0);
		} catch (DbException &e) {
		    std::cerr << e.what() << std::endl;
		} catch (std::exception &e) {
			std::cerr << e.what() << std::endl;
		}

		return cNil;
	}

	Object* CompiledDatabase::get(STATE, String* file) {
		Dbt key(const_cast<void *>(reinterpret_cast<const void *>(file->c_str(state))), strlen(file->c_str(state)));
		Dbt data;

		try {	
		    if (db_->get(NULL, &key, &data, 0) != DB_NOTFOUND) {
		    	return String::create(state, (char*)data.get_data(), data.get_size());
		    } else {
		    	return cNil;
		    }
	    } catch (DbException &e) {
	    	std::cerr << e.what() << std::endl;
		} catch (std::exception &e) {
			std::cerr << e.what() << std::endl;
		}

		return cNil;
	}
}
