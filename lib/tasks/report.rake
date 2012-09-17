namespace :fields do

  desc "Report the current schema"
  task :report=>:environment do
    ModalFields.report(
      :tables=>true, :primary_keys=>true, :foreign_keys=>true, :associations=>true,
      :undeclared_fields=>true) do |kind, table, name, data|
        case kind
        when :table
          puts "="*50
          puts table
        when :association
          puts "  Foreign keys for #{name} (table: #{data[:foreign_table]})"
        when :primary_key
          puts "  Primary key: #{name} #{data[:sql_type]}"
        when :foreign_key
          puts "    #{name} #{data[:sql_type]}"
        else
          puts "  #{name} #{data[:sql_type]}"
        end
    end
  end

end
