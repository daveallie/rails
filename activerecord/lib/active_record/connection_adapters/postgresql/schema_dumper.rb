# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module PostgreSQL
      class SchemaDumper < ConnectionAdapters::SchemaDumper # :nodoc:
        private
          def extensions(stream)
            extensions = @connection.extensions
            if extensions.any?
              stream.puts "  # These are extensions that must be enabled in order to support this database"
              extensions.sort.each do |extension|
                stream.puts "  enable_extension #{extension.inspect}"
              end
              stream.puts
            end
          end

          def types(stream)
            types = @connection.enum_types
            if types.any?
              stream.puts "  # Custom types defined in this database."
              stream.puts "  # Note that some types may not work with other database engines. Be careful if changing database."
              types.sort.each do |name, values|
                stream.puts "  create_enum #{name.inspect}, #{values.split(",").inspect}"
              end
              stream.puts
            end
          end

          def functions(stream)
            functions = @connection.functions
            if functions.any?
              stream.puts "  # Custom functions defined in this database."
              stream.puts "  # Note that create_function doesn't work with all database engines. Be careful if changing database."
              functions.sort_by(&:name).each do |function_def|
                options = function_def.options.compact.map do |key, value|
                  "#{key}: #{value.inspect}"
                end.join(", ")

                arg_defs = function_def.arguments.map do |a|
                  if a.key?(:argtype) && a.size == 1
                    ":#{a[:argtype]}"
                  else
                    arg_def = ["argtype: :#{a[:argtype]}"]
                    arg_def << ["argname: #{a[:argname].inspect}"] if a[:argname].present?
                    arg_def << ["argmode: #{a[:argmode].inspect}"] if a[:argmode].present?
                    arg_def << ["default: #{a[:default].inspect}"] if a[:default].present?

                    "{ #{arg_def.join(', ')} }"
                  end
                end

                token = "SQL"
                if function_def.definition.include?(token)
                  token = "SQL_#{ActiveSupport::Digest.hexdigest(function_def.definition).first(10)}"
                end

                create_function_args = [
                  function_def.name.inspect,
                  "[#{arg_defs.join(', ')}]",
                  ":#{function_def.return_type}",
                  "<<~#{token}",
                  options.presence,
                ].compact

                stream.puts "  create_function(#{create_function_args.join(', ')})"
                stream.puts function_def.definition.lines.map { |line| "    #{line}" }.join
                stream.puts "  #{token}"
                stream.puts
              end
            end
          end

          def prepare_column_options(column)
            spec = super
            spec[:array] = "true" if column.array?

            if @connection.supports_virtual_columns? && column.virtual?
              spec[:as] = extract_expression_for_virtual_column(column)
              spec[:stored] = true
              spec = { type: schema_type(column).inspect }.merge!(spec)
            end

            spec[:enum_type] = "\"#{column.sql_type}\"" if column.enum?

            spec
          end

          def default_primary_key?(column)
            schema_type(column) == :bigserial
          end

          def explicit_primary_key_default?(column)
            column.type == :uuid || (column.type == :integer && !column.serial?)
          end

          def schema_type(column)
            return super unless column.serial?

            if column.bigint?
              :bigserial
            else
              :serial
            end
          end

          def schema_expression(column)
            super unless column.serial?
          end

          def extract_expression_for_virtual_column(column)
            column.default_function.inspect
          end
      end
    end
  end
end
