class Author < ActiveRecord::Base

  fields {
    # The comments must be prerserved
    number :integer # as well as the order of field declarations,
      name :string  # indendation
    birthdate :date, :unique # specifications...
    # etc.
    decnum :decimal, :default=>BigDecimal('1.2'), :precision=>10, :scale=>3
    event :datetime
  }

  has_many :books
end
