namespace :fields do
  desc "Compare the current schema with existing field declarations"
  task :check=>:environment do
    ModalFields.check
  end  
end