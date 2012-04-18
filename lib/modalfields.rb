require 'modalfields/modalfields'
require 'modalfields/standardfields'

if defined?(Rails)
  if Rails.version.split('.').first.to_i > 2
    class BackupTask < Rails::Railtie
      rake_tasks do
        Dir[File.join(File.dirname(__FILE__), 'tasks', '**/*.rake')].each { |f| load f }
      end
    end
  else
    Dir[File.join(File.dirname(__FILE__), 'tasks', '**/*.rake')].each { |f| load f }
  end
end
