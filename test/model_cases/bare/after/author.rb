class Author < ActiveRecord::Base

  fields do
    name :string
    number :integer
    birthdate :date
    event :datetime
    decnum :decimal, :default=>BigDecimal('1.2'), :precision=>10, :scale=>3
  end

  has_many :books
end
