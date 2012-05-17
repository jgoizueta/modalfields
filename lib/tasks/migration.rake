namespace :fields do
  desc "Show migration required to sync schema with field declarations"
  task :migration=>:environment do
    ModalFields.migration
  end
end