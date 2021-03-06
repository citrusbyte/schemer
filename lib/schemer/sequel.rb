require "sequel"

module Schemer
  module Sequel
    module ClassMethods
      # Define a schema on your Sequel model.
      # 
      #     schema :name, { :age => :integer }, { :birthdate => :datetime }, :summary
      # 
      # Table + columns will be added automatically based on your definition.
      # 
      # If you remove a column, it will be removed from the table the next time
      # the class is loaded.
      # 
      # If you change the type of a column, it will be also be updated the next
      # time the class is loaded.
      # 
      # Likewise, adding a new column will add the column to your schema on the
      # next class load.
      # 
      # Columns with no types are assumed to be strings.
      def schema(*args)
        @schema_columns = {}
        
        args.collect{ |a| a.is_a?(Hash) ? a : { a => String } }.each do |column|
          self.schema_columns.merge!(column)
        end
        
        update_schema
      end
      
      def protected_columns
        @protected_columns = [ :id ].freeze
      end
      
      def schema_columns
        @schema_columns
      end      
      
      # Update the underlying schema as defined by schema call
      def update_schema        
        db.create_table?(self.table_name) do
          primary_key :id
        end
        
        get_db_schema.reject{ |column, definition| protected_columns.include?(column) }.each do |column, definition|
          if !schema_columns.has_key?(column)
            # remove any extraneous columns
            db.drop_column(table_name, column)
            
            # remove the accessors (sequel doesn't appear to have a facility
            # for this)
            [ "#{column}", "#{column}=" ].each do |method|
              overridable_methods_module.send(:undef_method, method) if public_instance_methods.include?(method)
            end
          elsif (definition[:type] || definition[:db_type]) != schema_columns[column]
            # change any columns w/ wrong type
            db.set_column_type(table_name, column, schema_columns[column])
          end
        end

        # add any missing columns
        (schema_columns.keys - columns).each do |column|
          db.add_column(table_name, column, schema_columns[column])
          def_column_accessor column          
        end
      end
    end
    
    class Migrator
      # Outputs the Rails migration for the schema defined in the given class.
      # 
      # Outputs an empty string if no schema is defined on the class.
      def self.migration(klass)
        return nil unless klass.respond_to?(:schema_columns)

        "create_table :#{klass.table_name} do |t|\n" +
        (klass.schema_columns.keys - klass::protected_columns).collect do |column| 
          "  add_column :#{column}, " + (klass.schema_columns[column].is_a?(Symbol) ? ":#{klass.schema_columns[column]}" : klass.schema_columns[column].to_s)
        end.join("\n") +
        "\nend"
      end
    end    
  end
end
