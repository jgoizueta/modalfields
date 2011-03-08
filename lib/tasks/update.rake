namespace :fields do
  desc "Update the field declarations from the current schema"
  task :update=>:environment do
    ModalFields.update
  end
end