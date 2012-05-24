module Rubinius
  class CompiledDatabase
    def self.new(path)
      Rubinius.primitive :compiled_database_new
      raise PrimitiveFailure, "CompiledDatabase.new primitive failed"
    end
    
    def write(file, sha, body)
      Rubinius.primitive :compiled_database_write
      raise PrimitiveFailure, "Unable to write #{file}."
    end

    def get(file)
      Rubinius.primitive :compiled_database_get
      raise PrimitiveFailure, "Unable to get #{file}."
    end
	end
end