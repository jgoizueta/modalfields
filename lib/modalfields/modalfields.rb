# This is a hybrid between HoboFields and model annotators.
#
# It works like other annotators, by updating the model annotations from the DB schema.
# But the annotations are syntactic Ruby as in HoboFields rather than comments.
#
# Apart from looking better to my eyes, this allows triggering special functionality
# from the field declations (such as specifying validations).
#
# The annotations are kept up to date by the migration tasks.
# Comments and validation, etc. specifications modified manually are preserved, at least
# if the field block syntax is kept as generated (one line per field, one line for the
# block start and end...)
#
# Custom type fields and hooks can be define in files (e.g. fields.rb) in config/initializers/
#
module ModalFields

  SPECIFIERS = [:indexed, :unique, :required]
  COMMON_ATTRIBUTES = {:default=>nil, :null=>true}

  class FieldDeclaration < Struct.new(:name, :type, :specifiers, :attributes)

    def self.declare(name, type, *args)
      attributes = args.extract_options!
      new(name, type, args, attributes)
    end

    def replace!(replacements={})
      replacements.each_pair do |key, value|
        self[key] = value
      end
      self
    end

    def remove_attributes!(*attrs)
      self.attributes = self.attributes.except(*attrs)
      self
    end

    def add!(attrs)
      self.attributes.merge! attrs
      self
    end

    def to_s
      code = "#{name} :#{type}"
      code << ", "+specifiers.inspect[1...-1] unless specifiers.empty?
      unless attributes.empty?
        code << ", "+attributes.keys.sort_by{|attr| attr.to_s}.map{|attr|
          v = attributes[attr]
          v = v.kind_of?(BigDecimal) ? "BigDecimal('#{v.to_s}')" : v.inspect
          ":#{attr}=>#{v}"
        }*", "
      end
      code
    end

  end


  class DefinitionsDsl
    def field(name, attributes={})
      ModalFields.definitions[name.to_sym] = COMMON_ATTRIBUTES.merge(attributes)
    end
    def method_missing(name, *args)
      field(name, *args)
    end
  end

  class HooksDsl
    def field_type(type, &blk)
      ModalFields.hooks[type.to_sym] = lambda{|model, column_declaration|
        blk[model, column_declaration]
      }
    end
    # geric filter applied to all the fields (after a specific filter for the type, if there is one)
    def all_fields(&blk)
      field_type :all_fields, &blk
    end
    def method_missing(name, *args, &blk)
      field_type name, *args, &blk
    end
  end

  class DeclarationsDsl
    def initialize(model)
      @model = model
    end
    def field(name, type, *args)
      declaration = FieldDeclaration.declare(name, type, *args)
      specific_hook = ModalFields.hooks[type.to_sym]
      general_hook = ModalFields.hooks[:all_fields]
      [specific_hook, general_hook].compact.each do |hook|
        hook[@model, declaration] if hook
      end
      if ModalFields.validate(declaration)
        @model.fields_info << declaration
      end
    end
    def timestamps
      field :created_at, :datetime
      field :updated_at, :datetime
    end
    def method_missing(name, type, *args)
      field(name, type, *args)
    end
  end

  module FieldDeclarationClassMethods
    def fields(&blk)
      @fields_info ||= []
      unless self.respond_to?(:fields_info)
        self.instance_eval do
          def fields_info
            @fields_info
          end
        end
      end
      DeclarationsDsl.new(self).instance_eval(&blk)
    end
  end

  @show_primary_keys = false
  @hooks = {}
  @definitions = {}
  @column_to_field_declaration_hook = nil

  class <<self
    attr_reader :hooks, :definitions
    # Define declaration of primary keys
    #   ModalFields.show_primary_keys = false # the default: do not show primary keys
    #   ModalFields.show_primary_keys = true  # always declare primary keys
    #   ModalFields.show_primary_keys = :id   # only declare if named 'id' (otherwise the model will have a primary_key declaration)
    #   ModalFields.show_primary_keys = :except_id   # only declare if named differently from 'id'
    attr_accessor :show_primary_keys

    # Run a definition block that executes field type definitions
    def define(&blk)
      DefinitionsDsl.new.instance_eval(&blk)
    end

    # Run a hooks block that defines field declaration processors
    def hook(&blk)
      HooksDsl.new.instance_eval(&blk)
    end

    # Define a custom column to field declaration conversion
    def column_to_field_declaration(&blk)
      @column_to_field_declaration_hook = blk
    end

    # Enable the ModalFields plugin (adds the fields declarator to model classes)
    def enable
      if defined?(::Rails)
        # class ::ActiveRecord::Base
        #   extend FieldDeclarationClassMethods
        # end
        ::ActiveRecord::Base.send :extend, FieldDeclarationClassMethods
      end
    end

    # Update the field declarations of all the models.
    # This modifies the source files of all the models (touches only the fields block or adds one if not present).
    # It is recommended to run this on a clearn working directory (no uncommitted changes), so that the
    # changes can be easily reviewed.
    def update(modify=true)
      dbmodels.each do |model, file|
        new_fields, modified_fields, deleted_fields = diff(model)
        unless new_fields.empty? && modified_fields.empty? && deleted_fields.empty?
          pre, start_fields, fields, end_fields, post = split_model_file(file)
          deleted_names = deleted_fields.map{|f| f.name.to_s}
          fields = fields.reject{|line, name, comment| deleted_names.include?(name)}
          fields = fields.map{|line, name, comment|
            mod_field = modified_fields.detect{|f| f.name.to_s==name}
            if mod_field
              line = "    "+mod_field.to_s
              line << " #{comment}" if comment
              line << "\n"
            end
            [line, name, comment]
          }
          pk_names = Array(model.primary_key).map(&:to_s)
          created_at = new_fields.detect{|f| f.name.to_s=='created_at'}
          updated_at = new_fields.detect{|f| f.name.to_s=='updated_at'}
          if created_at && updated_at && created_at.type.to_sym==:datetime && updated_at.type.to_sym==:datetime
            with_timestamps = true
            new_fields -= [created_at, updated_at]
          end
          fields += new_fields.map{|f|
            comments = pk_names.include?(f.name.to_s) ? " \# PK" : ""
            ["    #{f}#{comments}\n" ]
          }
          fields << ["    timestamps\n"] if with_timestamps
          output_file = modify ? file : "#{file}_with_fields.rb"
          join_model_file(output_file, pre, start_fields, fields, end_fields, post)
        end
      end
    end

    def check
      dbmodels.each do |model, file|
        new_fields, modified_fields, deleted_fields = diff(model)
        unless new_fields.empty? && modified_fields.empty? && deleted_fields.empty?
          rel_file = file.sub(/\A#{Rails.root}/,'')
          puts "#{model} (#{rel_file}):"
          [['+',new_fields],['*',modified_fields],['-',deleted_fields]].each do |prefix, fields|
            puts fields.map{|field| "  #{prefix} #{field}"}*"\n" unless fields.empty?
            # TODO: report index differences
          end
          puts ""
        end
      end
    end

    def validate(declaration)
      definition = definitions[declaration.type.to_sym]
      raise "Field type #{declaration.type} not defined" unless definition
      # TODO: validate declaration.specifiers
      # TODO: validate declaration.attributes with definition
      true
    end

    private

      # return ActiveRecord classes corresponding to tables, without STI derived classes, but including indirectly
      # derived classes that do have their own tables (to achieve this we use the convention that in such cases
      # the base class, directly derived from ActiveRecord::Base has a nil table_name)
      def dbmodels
        models = Dir.glob(File.join(Rails.root,"app/models/**/*.rb"))\
                   .map{|f| [File.basename(f).chomp(".rb").camelize.constantize, f]}\
                   .select{|c,f| has_table(c)}\
                   .reject{|c,f| has_table(c.superclass)}
        models.uniq
      end

      def has_table(cls)
        (cls!=ActiveRecord::Base) && cls.respond_to?(:table_name) && !cls.table_name.blank?
      end

      def map_column_to_field_declaration(column)
        if @column_to_field_declaration_hook
          @column_to_field_declaration_hook[column]
        else
          type = column.type.to_sym
          attributes = {}
          attrs = definitions[type]
          attrs.keys.each do |attr|
            v = column.send(attr)
            attributes[attr] = v unless attrs[attr]==v
          end
          FieldDeclaration.new(column.name.to_sym, type, [], attributes)
        end
      end

      # Compare the declared fields of a model (in the fields block) to the actual model columns (in the schema).
      # returns the difference as [new_fields, modified_fields, deleted_fields]
      # where:
      # * new_fields are field declarations not present in the model (corresponding to model columns not declared
      #   in the fields declaration block).
      # * modified_fields are field declarations corresponding to model columns that are different from their existing
      #   declarations.
      # * deleted_fields are fields declared in the fields block but not present in the current schema.
      def diff(model)
        # model.columns will fail if the table does not exist
        existing_fields = model.columns rescue []
        association_fields = model.reflect_on_all_associations(:belongs_to).map(&:primary_key_name).flatten.map(&:to_s)
        pk_fields = Array(model.primary_key).map(&:to_s)
        case show_primary_keys
        when true
          pk_fields = []
        when :id
          pk_fields = pk_fields.reject{|pk| pk=='id'}
        when :except_id
          pk_fields = pk_fields.select{|pk| pk=='id'}
        end
        if model.respond_to?(:fields_info)
          declared_fields = model.fields_info
          indices = model.connection.indexes(model.table_name) # name, columns, unique, spatial

          existing_declared_fields = []
          existing_undeclared_fields = []
          existing_fields.each do |f|
            name = f.name.to_s
            if declared_fields.detect{|df| df.name.to_s==name} || association_fields.include?(name) || pk_fields.include?(name)
              existing_declared_fields << f
            else
              existing_undeclared_fields << f
            end
          end
          deleted_fields = declared_fields.reject{|f|
            name = f.name.to_s
            existing_declared_fields.detect{|df| df.name.to_s==name}
          }
          modified_fields = (declared_fields - deleted_fields).map{ |field_declaration|
            column = existing_declared_fields.detect{|f| f.name.to_s == field_declaration.name.to_s}
            identical = false
            column = map_column_to_field_declaration(column)
            if field_declaration.type.to_sym == column.type.to_sym
              attrs = definitions[column.type.to_sym]
              attr_keys = attrs.keys
              decl_attrs = attr_keys.map{|a|
                v = field_declaration.attributes[a]
                v==attrs[a] ? nil : v
              }
              col_attrs = attr_keys.map{|a|
                v = column.attributes[a]
                v==attrs[a] ? nil : v
              }
              if decl_attrs == col_attrs
                identical=true
                # specifiers are defined only in declarations
              end
            end
            column.specifiers = field_declaration.specifiers
            identical ? nil : column
          }.compact
        else
          modified_fields = deleted_fields = []
          existing_undeclared_fields = existing_fields.reject{|f|
            name = f.name.to_s
            association_fields.include?(name) || pk_fields.include?(name)
          }
        end
        new_fields = existing_undeclared_fields.map { |f|
          attributes = {}
          attrs = definitions[f.type.to_sym]
          attrs.keys.each do |attr|
            v = f.send(attr)
            attributes[attr] = v unless attrs[attr]==v
          end
          FieldDeclaration.new(f.name.to_sym, f.type.to_sym, [], attributes)
        }
        [new_fields, modified_fields, deleted_fields]
      end

      # Break up the lines of a model definition file into sections delimited by the fields declaration.
      # An empty fields declaration is added to the result if none is present in the file.
      # The split result is an array with these elements:
      # * pre: array of lines before the fields declaration
      # * start_fields: line which opens the fields block
      # * fields: array of triplets [line, name, comment] with the lines inside th fields block.
      #   Name is the name of the field defined in the line, if any and comment is a comment including in the line;
      #   both name and comment may be absent.
      # * end_fields: line which closes the fields declaration
      # * post: array of lines after the fields block
      # All the lines include a trailing end-of-line separator.
      def split_model_file(file)
        code = File.read(file)
        pre = []
        start_fields = nil
        fields = []
        end_fields = nil
        post = []
        state = :pre
        line_no = 0
        field_block_end = nil
        code.each_line do |line|
          # line.chomp!
          line_no += 1
          case state
          when :pre
            if line =~ /^\s*fields\s+do(?:\s(.+))?$/
              field_block_end = /^\s*end(?:\s(.+))?$/
              start_fields = line
              state = :fields
            elsif line =~ /^\s*fields\s+\{(?:\s(.+))?$/
              field_block_end = /^\s*\}(?:\s(.+))?$/
              start_fields = line
              state = :fields
            else
              pre << line
            end
          when :fields
            if line =~ field_block_end
              end_fields = line
              state = :post
            else
              if line =~ /^\s*field\s+:(\w+).+?(#.+)?$/
                name = $1
                comment = $2
              elsif line =~ /^\s*field\s+['"](.+?)['"].+?(#.+)?$/
                name = $1
                comment = $2
              elsif line =~ /^\s*(\w+).+?(#.+)?$/
                name = $1
                comment = $2
              else
                name = comment = nil
              end
              fields << [line, name, comment]
            end
          when :post
            post << line
          end
        end
        if !start_fields
          i = 0
          (0...pre.size).each do |i|
            break if pre[i] =~ /^\s*class\b/
          end
          raise "Model declaration not found in #{file}" unless i<pre.size
          post = pre[i+1..-1]
          pre = pre[0..i]
          pre << "\n"
          start_fields = "  fields do\n"
          end_fields = "  end\n"
          post.unshift "\n" unless post.first.strip.empty?
          fields = []
        end
        [pre,start_fields,fields,end_fields,post]
      end

      # Write a model definition file from its broken up parts
      def join_model_file(output_file, pre, start_fields, fields, end_fields, post)
        File.open(output_file,"w"){ |output|
          output.write pre*""
          output.write start_fields
          output.write fields.map{|f| f.first}*""
          output.write end_fields
          output.write post*""
        }
      end

    end



end
