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
