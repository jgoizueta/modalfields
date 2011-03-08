namespace :db do
  task :migrate do
    ModalFields.update
  end

  task :update => [:migrate] do
    ModalFields.update
  end

  namespace :migrate do
    [:up, :down, :reset, :redo].each do |t|
      task t do
        ModalFields.update
      end
    end
  end
end