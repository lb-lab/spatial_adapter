module SpatialAdapter
  module ConnectionAdapters
    module Mysql2Adapter
      def supports_geographic?
        false
      end

      def native_database_types
        super.merge(SpatialAdapter::GEOMETRY_DATA_TYPES)
      end

      #Redefines the quote method to add behaviour for when a Geometry is encountered ; used when binding variables in find_by methods
      def quote(value, column = nil)
        if value.kind_of?(GeoRuby::SimpleFeatures::Geometry)
          "GeomFromWKB(0x#{value.as_hex_wkb},#{value.srid})"
        else
          super
        end
      end

      #Redefinition of columns to add the information that a column is geometric
      def columns(table_name, name = nil)#:nodoc:
        sql = "SHOW FIELDS FROM #{quote_table_name(table_name)}"
        columns = []
        result = execute(sql, name)
        result.each do |field|
          klass = field[1] =~ /geometry|point|linestring|polygon|multipoint|multilinestring|multipolygon|geometrycollection/i ? SpatialAdapter::ConnectionAdapters::SpatialMysqlColumn : ActiveRecord::ConnectionAdapters::MysqlColumn
          columns << klass.new(field[0], field[4], field[1], field[2] == "YES")
        end
        result.free
        columns
      end


      #operations relative to migrations

      #Redefines add_index to support the case where the index is spatial
      #If the :spatial key in the options table is true, then the sql string for a spatial index is created
      def add_index(table_name,column_name,options = {})
        index_name = options[:name] || index_name(table_name,:column => Array(column_name))

        if options[:spatial]
          execute "CREATE SPATIAL INDEX #{index_name} ON #{table_name} (#{Array(column_name).join(", ")})"
        else
          super
        end
      end

      #Check the nature of the index : If it is SPATIAL, it is indicated in the IndexDefinition object (redefined to add the spatial flag in spatial_adapter_common.rb)
      def indexes(table_name, name = nil)#:nodoc:
        indexes = []
        current_index = nil
        execute("SHOW KEYS FROM #{table_name}", name).each do |row|
          if current_index != row[2]
            next if row[2] == "PRIMARY" # skip the primary key
            current_index = row[2]
            indexes << ActiveRecord::ConnectionAdapters::IndexDefinition.new(row[0], row[2], row[1] == "0", [], row[10] == "SPATIAL")
          end
          indexes.last.columns << row[4]
        end
        indexes
      end

      #Get the table creation options : Only the engine for now. The text encoding could also be parsed and returned here.
      def options_for(table)
        result = execute("show table status like '#{table}'")
        engine = result.fetch_row[1]
        if engine !~ /inno/i #inno is default so do nothing for it in order not to clutter the migration
          "ENGINE=#{engine}" 
        else
          nil
        end
      end
    end
  end
end

ActiveRecord::ConnectionAdapters::MysqlAdapter.class_eval do
  include SpatialAdapter::ConnectionAdapters::MysqlAdapter
end