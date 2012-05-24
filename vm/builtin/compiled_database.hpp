#ifndef RBX_COMPILED_DATABASE_HPP

#include <db_cxx.h>

#include "builtin/object.hpp"
#include "builtin/string.hpp"

#define SHA_SIZE

namespace rubinius {
	class String;

	class CompiledDatabase : public Object {
	public:
		const static object_type type = CompiledDatabaseType;

    	// Rubinius.primitive :compiled_database_new
    	static CompiledDatabase* open(STATE, Object* self, String* path);

		// Rubinius.primitive :compiled_database_write
		Object* write(STATE, String* file, String* sha, String* body);

		// Rubinius.primitive :compiled_database_get
		Object* get(STATE, String* file);

		void open_db(const char* path);

		typedef struct file_body {
			const char *sha;
			const char *body;
		} FileBody;

	private:
		Db *db_;
		// std::string path_;

		void close();
	};
}

#endif
