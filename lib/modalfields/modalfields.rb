require 'modalsettings'

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

  # We'll use a somewhat conservative kind of 'blank slate' base for DSLs. that
  # works on Ruby 1.9 & 1.8
  class DslBase
    instance_methods.each { |m| undef_method m unless m =~ /^(__|instance_)/ }
  end

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

  class DefinitionsDsl < DslBase
    def field(name, attributes={})
      ModalFields.definitions[name.to_sym] = COMMON_ATTRIBUTES.merge(attributes)
    end
    def method_missing(name, *args)
      field(name, *args)
    end
  end

  class HooksDsl < DslBase
    def field_type(type, &blk)
      ModalFields.hooks[type.to_sym] = lambda{|model, column_declaration|
        blk[model, column_declaration]
      }
    end
    def field_migration(type, &blk)
      ModalFields.migration_hooks[type.to_sym] = lambda{|model, column_declaration|
        blk[model, column_declaration]
      }
    end
    # generic filter applied to all the fields (after a specific filter for the type, if there is one)
    def all_fields(&blk)
      field_type :all_fields, &blk
    end
    def method_missing(name, *args, &blk)
      field_type name, *args, &blk
    end
  end

  class DeclarationsDsl < DslBase
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
        if @model.table_exists? && @model.columns.detect{|c| c.name==declaration.name.to_s}
          if declaration.specifiers.include?(:unique)
            @model.validates_uniqueness_of declaration.name
          end
          if declaration.specifiers.include?(:required)
            @model.validates_presence_of declaration.name
          end
        end
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
    def fields(param=nil, &blk)
      if param == :omitted
        unless self.respond_to?(:fields_info)
          self.instance_eval do
            def fields_info
              :omitted
            end
          end
        end
      else
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
  end

  @show_primary_keys = false
  @hooks = {}
  @migration_hooks = {}
  @definitions = {}
  @column_to_field_declaration_hook = nil
  @type_aliases = {}
  @parameters = Settings[
    :check_all_models => false,     # consider all models (including those defined in plugins) for migration & check
    :check_dynamic_models => false, # consider models that may have been defined dynamically not in model files
    :update_vendor_models => false  # update also model files in vendor
  ]

  class <<self

    attr_reader :hooks, :migration_hooks, :definitions
    # Define declaration of primary keys
    #   ModalFields.show_primary_keys = false # the default: do not show primary keys
    #   ModalFields.show_primary_keys = true  # always declare primary keys
    #   ModalFields.show_primary_keys = :id   # only declare if named 'id' (otherwise the model will have a primary_key declaration)
    #   ModalFields.show_primary_keys = :except_id   # only declare if named differently from 'id'
    attr_accessor :show_primary_keys

    def parameters(params=nil)
      @parameters.merge! params if params
      @parameters
    end

    # Run a definition block that executes field type definitions
    def define(&blk)
      DefinitionsDsl.new.instance_eval(&blk)
    end

    # Define type synonyms
    def alias(aliases)
      @type_aliases.merge! aliases
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
      dbmodels(dbmodel_options).each do |model, file|
        next if file.nil?
        model.reset_column_information
        new_fields, modified_fields, deleted_fields, deleted_model = diff(model)
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
      dbmodels(dbmodel_options).each do |model, file|
        new_fields, modified_fields, deleted_fields, deleted_model = diff(model)
        unless new_fields.empty? && modified_fields.empty? && deleted_fields.empty?
          rel_file = file && file.sub(/\A#{Rails.root}/,'')
          puts "#{model} (#{rel_file}):"
          puts "  (deleted)" if deleted_model
          [['+',new_fields],['*',modified_fields],['-',deleted_fields]].each do |prefix, fields|
            puts fields.map{|field| "  #{prefix} #{field}"}*"\n" unless fields.empty?
            # TODO: report index differences
          end
          puts ""
        end
      end
    end

    def migration
      up = ""
      down = ""
      dbmodels(dbmodel_options).each do |model, file|
        new_fields, modified_fields, deleted_fields, deleted_model = diff(model).map{|fields|
          fields.kind_of?(Array) ? fields.map{|f| migration_declaration(model, f)} : fields
        }
        unless new_fields.empty? && modified_fields.empty? && deleted_fields.empty?
          up << "\n"
          down << "\n"
          rel_file = file && file.sub(/\A#{Rails.root}/,'')
          if deleted_model && modified_fields.empty? && new_fields.empty?
            up << "  create_table #{model.table_name.to_sym.inspect} do |t|\n"
            deleted_fields.each do |field|
              up << "    t.#{field.type} #{field.name.inspect}"
              unless field.attributes.empty?
                up << ", " + field.attributes.inspect.unwrap('{}')
              end
              up << "\n"
            end
            up << "  end\n"
            down << "  drop_table #{model.table_name.to_sym.inspect}\n"
          else
            deleted_fields.each do |field|
              up << "  add_column #{model.table_name.to_sym.inspect}, #{field.name.inspect}, #{field.type.inspect}"
              unless field.attributes.empty?
                up << ", " + field.attributes.inspect.unwrap('{}')
              end
              up << "\n"
              down << "  remove_column #{model.table_name.to_sym.inspect}, #{field.name.inspect}\n"
            end
            modified_fields.each do |field|
              changed = model.fields_info.find{|f| f.name.to_sym==field.name.to_sym}
              changed &&= migration_declaration(model, changed)
              up << "  change_column #{model.table_name.to_sym.inspect}, #{changed.name.inspect}, #{changed.type.inspect}"
              unless changed.attributes.empty?
                up << ", " + changed.attributes.inspect.unwrap('{}')
              end
              up << "\n"
              down << "  change_column #{model.table_name.to_sym.inspect}, #{field.name.inspect}, #{field.type.inspect}"
              unless field.attributes.empty?
                down << ", " + field.attributes.inspect.unwrap('{}')
              end
              down << "\n"
            end
            new_fields.each do |field|
              up << "  remove_column #{model.table_name.to_sym.inspect}, #{field.name.inspect}\n"
              down << "  add_column #{model.table_name.to_sym.inspect}, #{field.name.inspect}, #{field.type.inspect}"
              unless field.attributes.empty?
                down << ", " + field.attributes.inspect.unwrap('{}')
              end
              down << "\n"
            end
          end
          # TODO: indices
        end
      end
      unless up.blank?
        puts "\n\# up:"
        puts up
      end
      unless down.blank?
        puts "\n\# down:"
        puts down
      end
      puts ""
    end

    def validate(declaration)
      definition = definitions[declaration.type.to_sym]
      raise "Field type #{declaration.type} not defined (#{declaration.inspect})" unless definition
      # TODO: validate declaration.specifiers
      # TODO: validate declaration.attributes with definition
      true
    end

    def report(options={})
      models = Array(options[:model])
      models = dbmodels(dbmodel_options) if models.blank?
      models.each do |model, file|
        if options[:tables]
          yield :table, model.table_name, nil, {:model=>model}
        end

        submodels = model.send(:subclasses)
        existing_fields, association_fields, pk_fields = model_existing_fields(model, submodels)
        unless file.nil?
          pre, start_fields, fields, end_fields, post = split_model_file(file)
        else
        end

        pks = pk_fields.map{|pk_field_name| existing_fields.find{|f| f.name==pk_field_name}}
        existing_fields = existing_fields.reject{|f| f.name.in? pk_fields}
        if options[:primary_keys]
          pks.each do |pk_field|
            yield :primary_key, model.table_name, pk_field.name, field_data(pk_field)
          end
        end

        assoc_cols = []
        association_fields.each do |assoc, cols|

          if options[:associations]
            if assoc.options[:polymorphic]
              foreign_table = :polymorphic
            else
              foreign_table = assoc.klass.table_name
            end
            yield :association, model.table_name, assoc.name, {:foreign_table=>foreign_table}
          end
          Array(cols).each do |col|
            col = existing_fields.find{|f| f.name.to_s==col.to_s}
            assoc_cols << col
            if options[:foreign_keys]
              yield :foreign_key, model.table_name, col.name, field_data(col, :assoc=>assoc)
            end
          end
        end
        existing_fields -= assoc_cols

        has_fields_info = model.respond_to?(:fields_info) && model.fields_info != :omitted
        fields = Array(fields).reject{|line, name, comment| name.blank?}
        if has_fields_info
          field_order = model.fields_info.map(&:name).map(&:to_s) & existing_fields.map(&:name)
        else
          field_order = []
        end
        if options[:undeclared_fields]
          field_order += existing_fields.map(&:name).reject{|name| field_order.include?(name.to_s)}
        end
        field_comments = Hash[fields.map{|line, name, comment| [name,comment]}]
        field_extras = has_fields_info ? Hash[ model.fields_info.map{|fi| [fi.name.to_s,fi.attributes]}] : {}
        field_order.each do |field_name|
          field_info = existing_fields.find{|f| f.name.to_s==field_name}
          field_comment = field_comments[field_name]
          field_extra = field_extras[field_name]
          if field_info.blank?
            raise " MISSING FIELD: #{field_name} (#{model})"
          else
            yield :field, model.table_name, field_info.name, field_data(field_info, :comments=>field_comment, :extra=>field_extra)
          end
        end

      end
    end

    def models(options=nil)
      dbmodels options || dbmodel_options
    end

    private

      def migration_declaration(model, field_declaration)
        hook = ModalFields.migration_hooks[field_declaration.type.to_sym]
        hook[model, field_declaration] if hook
        field_declaration
      end

      def field_data(field_info, options={})
        comments = options[:comments]
        extra = options[:extra]
        assoc = options[:assoc]
        attrs = [:type, :sql_type, :default, :null]
        data = {}
        if comments.present?
          comments = comments.strip
          comments = comments[1..-1] if comments.starts_with?('#')
          comments = comments.strip
        end
        data[:comments] = comments if comments.present?
        if assoc.present?
          data[:foreign_name] = assoc.name
          if assoc.options[:polymorphic]
            data[:foreign_table] = :polymorphic
          else
            data[:foreign_table] = assoc.klass.table_name
          end
        end
        # case field_info.type
        # when :string, :text, :binary, :integer
        #   attrs << :limit
        # when :decimal
        #   attrs << :scale << :precision
        # when :geometry
        #   attrs << :srid
        # end
        attrs += ModalFields.definitions[field_info.type].keys
        attrs = attrs.uniq
        if extra.present?
          extra = extra.except(*attrs)
        end
        attrs.each do |attr|
          v = field_info.send(attr)
          data[attr] = v if v.present?
        end
        data[:extra] = extra if extra.present?
        data
      end

      # Return the database models
      # Options:
      #   :all_models                # Return also models in plugins, not only in the app (app/models)
      #   :dynamic_models            # Return dynamically defined models too (not defined in a model file)
      #   :exclude_sti_models        # Exclude derived (STI) models
      #   :exclude_non_sti_models    # Exclude top level models
      #   :include_files             # Return also the model definition file pathnames (return pairs of [model, file])
      #   :only_app_files            #   But return nil for files not in the app proper
      #   :only_app_tree_files       #   But return nil for files not in the app directory tree (app, vendor...)
      def dbmodels(options={})

        models_dir = 'app/models'
        if Rails.respond_to?(:application)
          model_dirs = Rails.application.paths[models_dir]
        else
          model_dirs = [models_dir]
        end
        models_dir = Rails.root.join(models_dir)
        model_dirs = model_dirs.map{|d| Rails.root.join(d)}

        if options[:all_models]
          # Include also models from plugins
          model_dirs = $:.grep(/\/models\/?\Z/)
        end

        models = []
        files = {}
        model_dirs.each do |base|
          Dir.glob(File.join(base,"**/*.rb")).each do |fn|
            model = File.basename(fn).chomp(".rb").camelize.constantize
            models << model
            files[model.to_s] = fn
          end
        end
        models = models.sort_by{|m| m.to_s}

        if options[:dynamic_models]
          # Now add dynamically generated models (not having dedicated files)
          # note that subclasses of these models are not added here
          models += ActiveRecord::Base.send(:subclasses)
          models = models.uniq
        end

        models = models.uniq.reject{|model| !has_table?(model)}

        non_sti_models, sti_models = models.partition{|model| model.base_class==model}

        models = []
        models += non_sti_models unless options[:exclude_non_sti_models]
        models += sti_models unless options[:exclude_sti_models]
        if options[:include_files]
          models = models.map{|model| [model, files[model.to_s]]}
          if options[:only_app_files] || options[:only_app_tree_files]
            if options[:only_app_files]
              suffix = models_dir.to_s
            else
              suffix = Rails.root.to_s
            end
            suffix += '/' unless suffix.ends_with?('/')
            models = models.map{|model, file| [model, file && (file.starts_with?(suffix) ? file : nil)]}
          end
        end
        models
      end

      def has_table?(cls)
       (cls != ActiveRecord::Base) && cls.respond_to?(:table_name) && cls.table_name.present?
      end

      def dbmodel_options
        {
          :all_models=>parameters.check_all_models,
          :dynamic_models=>parameters.check_dynamic_models,
          :exclude_sti_models=>true,
          :include_files=>true,
          :only_app_files=>!parameters.update_vendor_models,
          :only_app_tree_files=>parameters.update_vendor_models
        }
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
        submodels = model.send(:subclasses)
        existing_fields, association_fields, pk_fields = model_existing_fields(model, submodels)
        association_fields = association_fields.map{|assoc_name, cols| cols}.flatten.map(&:to_s)
        deleted_model = existing_fields.empty?
        case show_primary_keys
        when true
          pk_fields = []
        when :id
          pk_fields = pk_fields.reject{|pk| pk=='id'}
        when :except_id
          pk_fields = pk_fields.select{|pk| pk=='id'}
        end
        if model.respond_to?(:fields_info)
          return [[]]*4 if model.fields_info==:omitted
          declared_fields = model_fields_info(model)
          declared_fields += submodels.map{|sc| Array(model_fields_info(sc))}.flatten
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
          implicit_fields = association_fields.reject{|name|
            existing_declared_fields.detect{|df| df.name.to_s==name}
          }
          deleted_fields = declared_fields.reject{|f|
            name = f.name.to_s
            existing_declared_fields.detect{|df| df.name.to_s==name}
          }
          deleted_fields += implicit_fields.map{|name| FieldDeclaration.new(name.to_sym, :integer, [], {}) }
          modified_fields = (declared_fields - deleted_fields).map{ |field_declaration|
            column = existing_declared_fields.detect{|f| f.name.to_s == field_declaration.name.to_s}
            identical = false
            column = map_column_to_field_declaration(column)
            if unified_type(field_declaration.type) == unified_type(column.type.to_sym)
              attrs = definitions[column.type.to_sym]
              attr_keys = attrs.keys
              decl_attrs = attr_keys.map{|a|
                v = field_declaration.attributes[a]
                v==attrs[a] ? nil : (v==false ? nil : v)
              }
              col_attrs = attr_keys.map{|a|
                v = column.attributes[a]
                v==attrs[a] ? nil : (v==false ? nil : v)
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
        [new_fields, modified_fields, deleted_fields, deleted_model]
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

      def unified_type(type)
        type &&= type.to_sym
        @type_aliases[type] || type
      end

      def model_fields_info(model)
        fields_info = model && model.respond_to?(:fields_info) && model.fields_info
        fields_info.kind_of?(Array) ? fields_info : nil
      end

      # Returns three arrays:
      # * array of existing fields (column info objects)
      # * array of association fields: each element is the association information followed by the foreign key fields
      # * array of primary key field names
      def model_existing_fields(model, submodels=[])
        # model.columns will fail if the table does not exist
        existing_fields = model.columns rescue []
        assocs = model.reflect_on_all_associations(:belongs_to) +
                 submodels.map{|sc| sc.reflect_on_all_associations(:belongs_to)}.flatten
        association_fields = assocs.uniq.map{ |r|
          # up to ActiveRecord 3.1 we had primary_key_name in AssociationReflection; now it's foreign_key
          cols = [r.respond_to?(:primary_key_name) ? r.primary_key_name : r.foreign_key]
          if r.options[:polymorphic]
            t = r.options[:foreign_type]
            t ||= r.foreign_type if r.respond_to?(:foreign_type)
            t ||= cols.first.sub(/_id\Z/,'_type')
            cols <<  t
          end
          [r, cols]
        }
        pk_fields = Array(model.primary_key).map(&:to_s)
        [existing_fields, association_fields, pk_fields]
      end

    end



end
