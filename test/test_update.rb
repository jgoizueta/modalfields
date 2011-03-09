require File.dirname(__FILE__)+'/helper'

def setup_model_case(case_id)
  load_schema
  FileUtils.mkdir_p File.dirname(__FILE__)+"/app/models"
  FileUtils.cp Dir[File.dirname(__FILE__)+"/model_cases/#{case_id}/before/*.rb"], File.dirname(__FILE__)+"/app/models/"
  Dir[File.dirname(__FILE__)+"/app/models/*.rb"].each do |model_file|
    puts "Loading #{model_file}"
    load model_file
  end
end

def teardown_model_case(case_id)
  Object.send(:remove_const, :Author) if defined?(Author)
  Object.send(:remove_const, :Book)  if defined?(Book)
end

def check_model_case(case_id)
  ModalFields.update
  Dir[File.dirname(__FILE__)+"/model_cases/#{case_id}/after/*.rb"].each do |ref_model_file|
    model_file = File.dirname(__FILE__)+"/app/models/" + File.basename(ref_model_file)
    assert_equal File.read(ref_model_file), File.read(model_file)
  end
end  

class TestUpdate < Test::Unit::TestCase
  
  context "Given model definitions without field declarations, update" do
    setup { setup_model_case 'bare' }
    should "annotate the models with proper field declarations" do
      check_model_case 'bare'
    end
    teardown { teardown_model_case 'bare' }
  end

  context "Given model definitions with up-to-date field declarations, update" do
    setup { setup_model_case 'clean' }
    should "not modify them" do
      check_model_case 'clean'
    end
    teardown { teardown_model_case 'clean' }
  end

  context "Given model definitions with outdated field declarations, update" do
    setup { setup_model_case 'dirty' }
    should "fix them preserving comments and specifiers" do
      check_model_case 'dirty'
    end
    teardown { teardown_model_case 'dirty' }
  end

end
