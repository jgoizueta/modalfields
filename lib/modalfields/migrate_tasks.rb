Dir[File.join(File.dirname(__FILE__), '..', 'migrate_tasks', '**/*.rake')].each { |f| load f }
