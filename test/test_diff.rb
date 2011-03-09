require File.dirname(__FILE__)+'/helper'

class TestDiff< Test::Unit::TestCase
  
  context "Given model definitions without field declarations" do
    
    setup do
      load_schema
      class Author < ActiveRecord::Base
        has_many :books
      end
      class Book < ActiveRecord::Base
        belongs_to :author
      end
    end
    
    should "Find all fields that are not primary or foreing keys" do
      new_fields, modified_fields, deleted_fields = ModalFields.send(:diff, Author)
      assert modified_fields.empty?
      assert deleted_fields.empty?
      assert_same_elements ["number", "name", "birthdate", "decnum", "event"], new_fields.map{|f| f.name.to_s}
      new_fields, modified_fields, deleted_fields = ModalFields.send(:diff, Book)
      assert modified_fields.empty?
      assert deleted_fields.empty?
      assert_same_elements ["title", "price", "code", "comments", "created_at", "updated_at"], new_fields.map{|f| f.name.to_s}
    end
    
    teardown do
      TestDiff.send(:remove_const, :Author) if defined?(Author)
      TestDiff.send(:remove_const, :Book) if defined?(Book)
    end
    
  end

  context "Given model definitions with up to date field declarations" do
    
    setup do
      load_schema
      class Author < ActiveRecord::Base
        fields do
          name :string
          number :integer
          birthdate :date
          event :datetime
          decnum :decimal, :precision=>10, :scale=>3
        end
        has_many :books
      end
      class Book < ActiveRecord::Base
        fields do
          title :string
          price :decimal, :precision=>8, :scale=>2
          code :string, :limit=>4
          comments :text
          timestamps
        end
        belongs_to :author
      end
    end
    
    should "not find any changes" do
      new_fields, modified_fields, deleted_fields = ModalFields.send(:diff, Author)
      # assert new_fields.empty?
      # assert modified_fields.empty?
      # assert deleted_fields.empty?
      assert_same_elements [], new_fields.map{|f| f.name.to_s}
      assert_same_elements [], modified_fields.map{|f| f.name.to_s}
      assert_same_elements [], deleted_fields.map{|f| f.name.to_s}
      
      new_fields, modified_fields, deleted_fields = ModalFields.send(:diff, Book)
      # assert new_fields.empty?
      # assert modified_fields.empty?
      # assert deleted_fields.empty?
      assert_same_elements [], new_fields.map{|f| f.name.to_s}
      assert_same_elements [], modified_fields.map{|f| f.name.to_s}
      assert_same_elements [], deleted_fields.map{|f| f.name.to_s}
    end
    
    teardown do
      TestDiff.send(:remove_const, :Author) if defined?(Author)
      TestDiff.send(:remove_const, :Book) if defined?(Book)
    end
    
  end  

  context "Given model definitions with unaccurate field declarations" do
    
    setup do
      load_schema
      class Author < ActiveRecord::Base
        fields do
          name :string
          birthdate :datetime
          nationality :string
          event :datetime
          decnum :decimal, :precision=>10, :scale=>3
        end
        has_many :books
      end
      class Book < ActiveRecord::Base
        fields do
          title :string
          price :decimal, :precision=>8, :scale=>2
          code :string, :limit=>5
          timestamps
        end
      end
    end
    
    should "Find schema modifications" do
      new_fields, modified_fields, deleted_fields = ModalFields.send(:diff, Author)
      assert_same_elements ['nationality'], deleted_fields.map{|f| f.name.to_s}
      assert_same_elements ['number'], new_fields.map{|f| f.name.to_s}
      assert_same_elements ['birthdate'], modified_fields.map{|f| f.name.to_s}
      new_fields, modified_fields, deleted_fields = ModalFields.send(:diff, Book)
      assert_same_elements [], deleted_fields.map{|f| f.name.to_s}
      assert_same_elements ['comments', 'author_id'], new_fields.map{|f| f.name.to_s}
      assert_same_elements ['code'], modified_fields.map{|f| f.name.to_s}
    end
    
    teardown do
      TestDiff.send(:remove_const, :Author) if defined?(Author)
      TestDiff.send(:remove_const, :Book) if defined?(Book)
    end
    
  end  
end
