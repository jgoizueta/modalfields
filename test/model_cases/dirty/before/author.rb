class Author < ActiveRecord::Base

  fields {
    # The comments must be prerserved
    number :integer # as well as the order of field declarations,
      name :string  # indendation
      xxxx :string
      birthdate :integer, :unique # specifications...
    # etc.
    decnum :decimal, :default=>BigDecimal('1.2'), :precision=>11, :scale=>3
    eventx :datetime
  }

  has_many :books
end
