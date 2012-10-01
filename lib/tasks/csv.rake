namespace :fields do

  require 'csv'

  desc "Dump fields information in CSV"
  task :csv=>:environment do
    fn = Rails.root.join('tmp','fields.csv')
    if CSV.constants.map(&:to_sym).include?(:VERSION)
      options = [{
              :headers=>true,
              :col_sep=>';'
            }]
    else
      options = [';']
    end
    CSV.open(fn, 'w', *options) do |csv|
        csv << %w{table column pk assoc foreign sql_type type attributes extra comments}
        ModalFields.report(
          :primary_keys=>true, :foreign_keys=>true,
          :undeclared_fields=>true) do |kind, table, name, data|
            row_data = [table, name, kind==:primary_key]
            if kind==:foreign_key
              row_data << data[:foreign_name] << data[:foreign_table].to_s
            else
              row_data << '' << ''
            end
            attrs = data.except(:sql_type, :type, :extra, :comments).to_json
            extra = data[:extra]
            row_data << data[:sql_type] << data[:type] << attrs << data[:extra] << data[:comments]
            csv << row_data
        end
    end
    puts "Data written to #{fn}"
  end

end
